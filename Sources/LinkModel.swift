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
    @Published var peakDown: Double = 0
    @Published var errorText: String?
    @Published var band: WifiBand = WifiBand(rawValue: UserDefaults.standard.string(forKey: "band") ?? "") ?? .unset {
        didSet { UserDefaults.standard.set(band.rawValue, forKey: "band") }
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
                    if !wifi { self.result = nil; self.peakDown = 0 }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "linkmeter.path"))
        restartProbe()
    }

    func setMonitoring(_ on: Bool) {
        monitoring = on
        restartProbe()
    }

    // MARK: Continuous link probe (Wi-Fi only)

    private func restartProbe() {
        probeTask?.cancel()
        probeTask = nil
        guard monitoring else { return }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.wifiConnected { await self.probe() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func probe() async {
        do {
            let lat = try await SpeedTester.latency(.wifi, samples: 1)
            if Task.isCancelled { return }
            let down = try await SpeedTester.download(.wifi, bytes: 8_000_000, seconds: 2.5, progress: { _ in })
            if Task.isCancelled { return }
            let up = try await SpeedTester.upload(.wifi, bytes: 3_000_000, seconds: 2, progress: { _ in })
            if Task.isCancelled { return }
            func ema(_ o: Double?, _ n: Double) -> Double { o.map { $0 * 0.5 + n * 0.5 } ?? n }
            result = SpeedResult(down: ema(result?.down, down),
                                 up: ema(result?.up, up),
                                 latencyMs: ema(result?.latencyMs, lat))
            peakDown = max(peakDown, down)
            errorText = nil
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Band hint when the user hasn't set one: 2.4 GHz rarely sustains more than about 150 Mbps in practice.
    var bandHint: String? {
        guard band == .unset, peakDown > 200 else { return nil }
        return "Speeds suggest 5 or 6 GHz"
    }
}
