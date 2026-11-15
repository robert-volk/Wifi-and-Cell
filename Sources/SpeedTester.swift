import Foundation
import Network

struct SpeedResult {
    var down: Double      // Mbps
    var up: Double        // Mbps
    var latencyMs: Double
}

enum SpeedError: LocalizedError {
    case noRoute
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noRoute: return "No route on that connection. Check it's on, and that Cellular Data is allowed for this app."
        case .failed(let s): return s
        }
    }
}

/// Thin async wrapper over NWConnection pinned to one interface type.
/// Pinning is what lets the Wi-Fi / Cellular selector test a specific link.
final class Conn {
    private let c: NWConnection

    init(host: String, iface: NWInterface.InterfaceType) {
        let params = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        params.requiredInterfaceType = iface
        c = NWConnection(host: NWEndpoint.Host(host), port: 443, using: params)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            var finished = false
            c.stateUpdateHandler = { state in
                if finished { return }
                switch state {
                case .ready:
                    finished = true; k.resume()
                case .waiting:
                    finished = true; k.resume(throwing: SpeedError.noRoute)
                case .failed(let e):
                    finished = true; k.resume(throwing: SpeedError.failed(e.localizedDescription))
                case .cancelled:
                    finished = true; k.resume(throwing: CancellationError())
                default: break
                }
            }
            c.start(queue: DispatchQueue(label: "linkmeter.conn"))
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            c.send(content: data, completion: .contentProcessed { e in
                if let e = e { k.resume(throwing: e) } else { k.resume() }
            })
        }
    }

    func receive() async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<(Data?, Bool), Error>) in
            c.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { data, _, isComplete, error in
                if let error = error { k.resume(throwing: error) }
                else { k.resume(returning: (data, isComplete)) }
            }
        }
    }

    func cancel() { c.cancel() }
}

enum SpeedTester {
    static let host = "speed.cloudflare.com"

    /// Best of N time-to-first-byte readings on fresh connections.
    static func latency(_ iface: NWInterface.InterfaceType, samples: Int = 3) async throws -> Double {
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<samples {
            let c = Conn(host: host, iface: iface)
            try await c.start()
            let req = "GET /__down?bytes=0 HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
            let t0 = Date()
            try await c.send(Data(req.utf8))
            _ = try await c.receive()
            best = min(best, Date().timeIntervalSince(t0) * 1000)
            c.cancel()
        }
        return best
    }

    static func download(_ iface: NWInterface.InterfaceType,
                         bytes: Int = 80_000_000,
                         seconds: Double = 8,
                         progress: @escaping (Double) -> Void) async throws -> Double {
        let c = Conn(host: host, iface: iface)
        try await c.start()
        defer { c.cancel() }
        let req = "GET /__down?bytes=\(bytes) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
        try await c.send(Data(req.utf8))

        var total = 0
        var t0: Date?
        var elapsed = 0.0
        loop: while true {
            var chunk: (Data?, Bool) = (nil, true)
            do { chunk = try await c.receive() }
            catch { if total > 0 { break loop } else { throw error } }
            let data = chunk.0
            let done = chunk.1

            if t0 == nil {
                // First chunk carries headers; start the clock after it arrives.
                if data != nil { t0 = Date() }
                if done { break loop }
                continue
            }
            total += data?.count ?? 0
            elapsed = Date().timeIntervalSince(t0!)
            if elapsed > 0.3 { progress(Double(total) * 8 / elapsed / 1_000_000) }
            if done || elapsed >= seconds { break loop }
        }
        guard total > 0, elapsed > 0 else { throw SpeedError.failed("Download test returned no data.") }
        return Double(total) * 8 / elapsed / 1_000_000
    }

    static func upload(_ iface: NWInterface.InterfaceType,
                       bytes: Int = 40_000_000,
                       seconds: Double = 8,
                       progress: @escaping (Double) -> Void) async throws -> Double {
        let c = Conn(host: host, iface: iface)
        try await c.start()
        defer { c.cancel() }
        let body = bytes
        let header = "POST /__up HTTP/1.1\r\nHost: \(host)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body)\r\nConnection: close\r\n\r\n"
        try await c.send(Data(header.utf8))

        let chunk = Data(count: 262_144)
        var sent = 0
        let t0 = Date()
        var elapsed = 0.0
        while sent < body {
            try await c.send(chunk)
            sent += chunk.count
            elapsed = Date().timeIntervalSince(t0)
            if elapsed > 0.3 { progress(Double(sent) * 8 / elapsed / 1_000_000) }
            if elapsed >= seconds { break }
        }
        guard elapsed > 0 else { throw SpeedError.failed("Upload test didn't run.") }
        return Double(sent) * 8 / elapsed / 1_000_000
    }
}
