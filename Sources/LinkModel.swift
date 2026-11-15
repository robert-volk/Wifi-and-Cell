import Foundation
import Network
import CoreTelephony
import CoreLocation
import NetworkExtension

enum LinkKind: String, CaseIterable, Identifiable {
    case wifi = "Wi-Fi"
    case cellular = "Cellular"
    var id: String { rawValue }
    var iface: NWInterface.InterfaceType { self == .wifi ? .wifi : .cellular }
}

/// iOS never tells apps which Wi-Fi band they're on, so the user can set it.
enum WifiBand: String, CaseIterable, Identifiable {
    case unset = "Not set"
    case g24 = "2.4 GHz"
    case g5 = "5 GHz"
    case g6 = "6 GHz"
    var id: String { rawValue }
}

@MainActor
final class LinkModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var selected: LinkKind = .wifi {
        didSet {
            guard selected != oldValue else { return }
            history = []
            lastCounters = nil
            liveRx = 0; liveTx = 0
            errorText = nil
            restartProbe()
        }
    }
    @Published var monitoring = true
    @Published var wifiConnected = false
    @Published var cellularConnected = false
    @Published var ssid: String?
    @Published var wifiStrength: Double?          // 0...1, only when iOS allows it
    @Published var cellularTech: String?
    @Published var results: [LinkKind: SpeedResult] = [:]
    @Published var peakDown: [LinkKind: Double] = [:]
    @Published var history: [Double] = []         // recent downstream Mbps, one per second
    @Published var liveRx: Double = 0
    @Published var liveTx: Double = 0
    @Published var errorText: String?
    @Published var band: WifiBand = WifiBand(rawValue: UserDefaults.standard.string(forKey: "band") ?? "") ?? .unset {
        didSet { UserDefaults.standard.set(band.rawValue, forKey: "band") }
    }

    private let monitor = NWPathMonitor()
    private let telephony = CTTelephonyNetworkInfo()
    private let location = CLLocationManager()
    private var timer: Timer?
    private var probeTask: Task<Void, Never>?
    private var lastCounters: (rx: UInt32, tx: UInt32, at: Date)?

    override init() {
        super.init()
        location.delegate = self
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.availableInterfaces.contains { $0.type == .wifi }
            let cell = path.availableInterfaces.contains { $0.type == .cellular }
            Task { @MainActor in
                self?.wifiConnected = wifi
                self?.cellularConnected = cell
            }
        }
        monitor.start(queue: DispatchQueue(label: "linkmeter.path"))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        restartProbe()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}

    // MARK: Control

    func setMonitoring(_ on: Bool) {
        monitoring = on
        restartProbe()
    }

    // MARK: One-second tick: signal, tech, live traffic

    private func tick() {
        cellularTech = currentTech()
        Task {
            let net = await NEHotspotNetwork.fetchCurrent()
            self.ssid = net?.ssid
            self.wifiStrength = net?.signalStrength
        }
        guard monitoring else { lastCounters = nil; return }
        let c = Self.counters(wifi: selected == .wifi)
        let now = Date()
        if let p = lastCounters {
            let dt = now.timeIntervalSince(p.at)
            if dt > 0.2 {
                liveRx = Double(c.rx &- p.rx) * 8 / dt / 1_000_000
                liveTx = Double(c.tx &- p.tx) * 8 / dt / 1_000_000
                history.append(liveRx)
                if history.count > 60 { history.removeFirst(history.count - 60) }
            }
        }
        lastCounters = (c.rx, c.tx, now)
    }

    /// Byte counters for the Wi-Fi (en0) or cellular (pdp_ip*) interface.
    private static func counters(wifi: Bool) -> (rx: UInt32, tx: UInt32) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt32 = 0, tx: UInt32 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let name = String(cString: cur.pointee.ifa_name)
            let match = wifi ? name == "en0" : name.hasPrefix("pdp_ip")
            if match,
               let addr = cur.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx = rx &+ d.ifi_ibytes
                tx = tx &+ d.ifi_obytes
            }
            p = cur.pointee.ifa_next
        }
        return (rx, tx)
    }

    private func currentTech() -> String? {
        guard let map = telephony.serviceCurrentRadioAccessTechnology, !map.isEmpty else { return nil }
        let raw = map.values.first ?? ""
        switch raw {
        case CTRadioAccessTechnologyNR: return "5G"
        case CTRadioAccessTechnologyNRNSA: return "5G (NSA)"
        case CTRadioAccessTechnologyLTE: return "LTE"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA, CTRadioAccessTechnologyeHRPD,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB: return "3G"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyCDMA1x: return "2G"
        default: return "Cellular"
        }
    }

    // MARK: Continuous link probe

    private func restartProbe() {
        probeTask?.cancel()
        probeTask = nil
        guard monitoring else { return }
        let kind = selected
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isConnected(kind) { await self.probe(kind) }
                // Cellular probes less often to go easy on data.
                let pause: UInt64 = kind == .wifi ? 2_000_000_000 : 10_000_000_000
                try? await Task.sleep(nanoseconds: pause)
            }
        }
    }

    private func isConnected(_ kind: LinkKind) -> Bool {
        kind == .wifi ? wifiConnected : cellularConnected
    }

    private func probe(_ kind: LinkKind) async {
        let big = kind == .wifi
        do {
            let lat = try await SpeedTester.latency(kind.iface, samples: 1)
            if Task.isCancelled { return }
            let down = try await SpeedTester.download(kind.iface,
                bytes: big ? 8_000_000 : 2_000_000, seconds: big ? 2.5 : 3, progress: { _ in })
            if Task.isCancelled { return }
            let up = try await SpeedTester.upload(kind.iface,
                bytes: big ? 3_000_000 : 1_000_000, seconds: big ? 2 : 3, progress: { _ in })
            if Task.isCancelled { return }
            let old = results[kind]
            func ema(_ o: Double?, _ n: Double) -> Double { o.map { $0 * 0.5 + n * 0.5 } ?? n }
            results[kind] = SpeedResult(down: ema(old?.down, down),
                                        up: ema(old?.up, up),
                                        latencyMs: ema(old?.latencyMs, lat))
            peakDown[kind] = max(peakDown[kind] ?? 0, down)
            errorText = nil
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: Derived display values

    var connected: Bool { isConnected(selected) }

    var pillText: String {
        switch selected {
        case .wifi: return ssid ?? "Wi-Fi"
        case .cellular: return cellularTech ?? "Cellular"
        }
    }

    var result: SpeedResult? { results[selected] }

    /// iOS reports Wi-Fi strength as 0...1 only. This maps it onto a rough dBm scale (about -100 to -40).
    var approxDbm: Int? {
        guard selected == .wifi, let s = wifiStrength else { return nil }
        return Int((-100 + 60 * s).rounded())
    }

    var hasRealStrength: Bool { selected == .wifi && wifiStrength != nil }

    /// 0...1 quality. Real Wi-Fi strength when available, otherwise estimated from measured speed and latency.
    var quality: Double? {
        if selected == .wifi, let w = wifiStrength { return w }
        guard let r = result else { return nil }
        let speed = min(1, log10(1 + r.down) / log10(1 + 200))
        let lat = max(0, min(1, 1 - (r.latencyMs - 20) / 200))
        return 0.7 * speed + 0.3 * lat
    }

    var bigSignalText: String {
        if let d = approxDbm { return "\(d) dBm" }
        guard let q = quality else { return "—" }
        switch q {
        case ..<0.25: return "Poor"
        case ..<0.5: return "Fair"
        case ..<0.75: return "Good"
        default: return "Excellent"
        }
    }

    var signalCaption: String {
        if quality == nil { return connected ? "Measuring…" : "Not connected" }
        if hasRealStrength { return "Approx. dBm, scaled from iOS's 0 to 1 strength reading" }
        return "Quality estimated from measured speed and latency"
    }

    var bars: Int {
        guard let q = quality else { return 0 }
        return max(1, min(4, Int((q * 4).rounded(.up))))
    }

    /// Band hint when the user hasn't set one: 2.4 GHz rarely sustains more than about 150 Mbps in practice.
    var bandHint: String? {
        guard selected == .wifi, band == .unset, let peak = peakDown[.wifi] else { return nil }
        return peak > 200 ? "Speeds suggest 5 or 6 GHz" : nil
    }
}
