import Foundation
import Network

/// iOS never tells apps which Wi-Fi band they're on, so the user can set it.
enum WifiBand: String, CaseIterable, Identifiable {
    case unset = "Not set"
    case g24 = "2.4 GHz"
    case g5 = "5 GHz"
    case g6 = "6 GHz"
    var id: String { rawValue }
}

@MainActor
final class LinkModel: ObservableObject {
    @Published var monitoring = true
    @Published var wifiConnected = false
    @Published var result: SpeedResult?
    @Published var routerMs: Double?
    @Published var peakDown: Double = 0
    @Published var errorText: String?

    @Published var band: WifiBand = WifiBand(rawValue: UserDefaults.standard.string(forKey: "band") ?? "") ?? .unset {
        didSet { UserDefaults.standard.set(band.rawValue, forKey: "band") }
    }
    /// PC running Server/lan_speed_server.py. Empty means measure to the internet instead.
    @Published var lanHost: String = UserDefaults.standard.string(forKey: "lanHost") ?? "" {
        didSet {
            UserDefaults.standard.set(lanHost, forKey: "lanHost")
            resetMeasurements()
        }
    }
    @Published var routerHost: String = UserDefaults.standard.string(forKey: "routerHost") ?? "" {
        didSet {
            UserDefaults.standard.set(routerHost, forKey: "routerHost")
            routerMs = nil
        }
    }

    private let monitor = NWPathMonitor()
    private var probeTask: Task<Void, Never>?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.availableInterfaces.contains { $0.type == .wifi }
            Task { @MainActor in
                guard let self else { return }
                if self.wifiConnected != wifi {
                    self.wifiConnected = wifi
                    if !wifi { self.resetMeasurements() }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "linkmeter.path"))
        restartProbe()
    }

    // MARK: Derived

    var target: Target {
        let h = lanHost.trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? .internet : .lan(h)
    }

    /// Router address: the one you typed, else the PC's address with the last number set to 1.
    var effectiveRouter: String? {
        let r = routerHost.trimmingCharacters(in: .whitespaces)
        if !r.isEmpty { return r }
        let parts = lanHost.trimmingCharacters(in: .whitespaces).split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts[0...2].joined(separator: ".") + ".1"
    }

    var sourceCaption: String {
        target.isLAN ? "Measured to your PC at \(target.host), over Wi-Fi only"
                     : "Measured to the internet. Add your PC's address below for true Wi-Fi speed."
    }

    /// Band hint when the user hasn't set one: 2.4 GHz rarely sustains more than about 150 Mbps in practice.
    var bandHint: String? {
        guard band == .unset, peakDown > 200 else { return nil }
        return "Speeds suggest 5 or 6 GHz"
    }

    // MARK: Control

    func setMonitoring(_ on: Bool) {
        monitoring = on
        restartProbe()
    }

    private func resetMeasurements() {
        result = nil
        peakDown = 0
        errorText = nil
        restartProbe()
    }

    // MARK: Continuous probe (Wi-Fi only)

    private func restartProbe() {
        probeTask?.cancel()
        probeTask = nil
        guard monitoring else { return }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.wifiConnected { await self.probe() }
                let lan = self.target.isLAN
                try? await Task.sleep(nanoseconds: lan ? 1_000_000_000 : 2_000_000_000)
            }
        }
    }

    private func probe() async {
        let t = target
        let lan = t.isLAN
        if let r = effectiveRouter, lan {
            let ms = await SpeedTester.routerLatency(host: r)
            if Task.isCancelled { return }
            routerMs = ms.map { old in routerMs.map { $0 * 0.5 + old * 0.5 } ?? old }
        } else {
            routerMs = nil
        }
        do {
            let lat = try await SpeedTester.latency(t)
            if Task.isCancelled { return }
            let down = try await SpeedTester.download(t, bytes: lan ? 40_000_000 : 8_000_000, seconds: 2.5)
            if Task.isCancelled { return }
            let up = try await SpeedTester.upload(t, bytes: lan ? 20_000_000 : 3_000_000, seconds: 2)
            if Task.isCancelled { return }
            func ema(_ o: Double?, _ n: Double) -> Double { o.map { $0 * 0.5 + n * 0.5 } ?? n }
            result = SpeedResult(down: ema(result?.down, down),
                                 up: ema(result?.up, up),
                                 latencyMs: ema(result?.latencyMs, lat))
            peakDown = max(peakDown, down)
            errorText = nil
        } catch is CancellationError {
        } catch {
            errorText = lan ? "Can't reach your PC. Check the address, that Wi-Fi is on, and that the server is running."
                            : error.localizedDescription
        }
    }
}
