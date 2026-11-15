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

@MainActor
final class LinkModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var selected: LinkKind = .wifi
    @Published var wifiConnected = false
    @Published var cellularConnected = false
    @Published var ssid: String?
    @Published var wifiStrength: Double?          // 0...1, only when iOS allows it
    @Published var cellularTech: String?          // "5G", "LTE", ...
    @Published var results: [LinkKind: SpeedResult] = [:]

    @Published var running = false
    @Published var phase = ""
    @Published var liveMbps: Double = 0
    @Published var errorText: String?

    private let monitor = NWPathMonitor()
    private let telephony = CTTelephonyNetworkInfo()
    private let location = CLLocationManager()
    private var timer: Timer?

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
                self?.refresh()
            }
        }
        monitor.start(queue: DispatchQueue(label: "linkmeter.path"))
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    // MARK: Live info

    func refresh() {
        cellularTech = currentTech()
        Task {
            let net = await NEHotspotNetwork.fetchCurrent()
            self.ssid = net?.ssid
            self.wifiStrength = net?.signalStrength
        }
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

    // MARK: Derived display values

    var connected: Bool { selected == .wifi ? wifiConnected : cellularConnected }

    var pillText: String {
        switch selected {
        case .wifi:
            if let s = ssid { return s }
            return "Wi-Fi"
        case .cellular:
            return cellularTech ?? "Cellular"
        }
    }

    var result: SpeedResult? { results[selected] }

    /// 0...1 quality. Real Wi-Fi strength when iOS provides it, otherwise estimated from the last test.
    var quality: Double? {
        if selected == .wifi, let w = wifiStrength { return w }
        guard let r = result else { return nil }
        let speed = min(1, log10(1 + r.down) / log10(1 + 200))
        let lat = max(0, min(1, 1 - (r.latencyMs - 20) / 200))
        return 0.7 * speed + 0.3 * lat
    }

    var qualityIsEstimate: Bool { !(selected == .wifi && wifiStrength != nil) }

    var qualityLabel: String {
        guard let q = quality else { return "—" }
        if selected == .wifi, wifiStrength != nil { return "\(Int((q * 100).rounded()))%" }
        switch q {
        case ..<0.25: return "Poor"
        case ..<0.5: return "Fair"
        case ..<0.75: return "Good"
        default: return "Excellent"
        }
    }

    var bars: Int {
        guard let q = quality else { return 0 }
        return max(1, min(4, Int((q * 4).rounded(.up))))
    }

    // MARK: Speed test

    func runTest() {
        guard !running else { return }
        let kind = selected
        guard connected else {
            errorText = "\(kind.rawValue) isn't connected."
            return
        }
        running = true
        errorText = nil
        liveMbps = 0
        phase = "Starting"
        Task {
            do {
                let r = try await SpeedTester.run(on: kind.iface,
                    phase: { p in Task { @MainActor in self.phase = p; self.liveMbps = 0 } },
                    live: { v in Task { @MainActor in self.liveMbps = v } })
                results[kind] = r
            } catch {
                errorText = error.localizedDescription
            }
            running = false
            phase = ""
        }
    }
}
