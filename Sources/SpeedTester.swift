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
        case .noRoute: return "Couldn't reach the server over Wi-Fi."
        case .failed(let s): return s
        }
    }
}

/// Where a test talks to: the internet (Cloudflare, TLS) or your PC on the LAN (plain HTTP).
struct Target {
    var host: String
    var port: UInt16
    var tls: Bool
    var downPath: String      // "%d" is replaced with the byte count
    var upPath: String
    var pingPath: String

    static let internet = Target(host: "speed.cloudflare.com", port: 443, tls: true,
                                 downPath: "/__down?bytes=%d", upPath: "/__up", pingPath: "/__down?bytes=0")

    static func lan(_ host: String) -> Target {
        Target(host: host, port: 8765, tls: false,
               downPath: "/down?bytes=%d", upPath: "/up", pingPath: "/ping")
    }

    var isLAN: Bool { !tls }
}

/// Thin async wrapper over NWConnection pinned to one interface type.
final class Conn {
    private let c: NWConnection
    private let q = DispatchQueue(label: "linkmeter.conn")

    init(target: Target, iface: NWInterface.InterfaceType) {
        let params: NWParameters = target.tls
            ? NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
            : NWParameters.tcp
        params.requiredInterfaceType = iface
        c = NWConnection(host: NWEndpoint.Host(target.host),
                         port: NWEndpoint.Port(rawValue: target.port)!, using: params)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            var finished = false
            func finish(_ error: Error?) {
                if finished { return }
                finished = true
                if let error = error { c.cancel(); k.resume(throwing: error) } else { k.resume() }
            }
            c.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(nil)
                case .waiting: finish(SpeedError.noRoute)
                case .failed(let e): finish(SpeedError.failed(e.localizedDescription))
                case .cancelled: finish(CancellationError())
                default: break
                }
            }
            c.start(queue: q)
            q.asyncAfter(deadline: .now() + 4) { finish(SpeedError.noRoute) }
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
    static let iface: NWInterface.InterfaceType = .wifi

    /// Time to first byte of a tiny request on a fresh connection.
    static func latency(_ t: Target, samples: Int = 1) async throws -> Double {
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<samples {
            let c = Conn(target: t, iface: iface)
            try await c.start()
            let req = "GET \(t.pingPath) HTTP/1.1\r\nHost: \(t.host)\r\nConnection: close\r\n\r\n"
            let t0 = Date()
            try await c.send(Data(req.utf8))
            _ = try await c.receive()
            best = min(best, Date().timeIntervalSince(t0) * 1000)
            c.cancel()
        }
        return best
    }

    static func download(_ t: Target, bytes: Int, seconds: Double) async throws -> Double {
        let c = Conn(target: t, iface: iface)
        try await c.start()
        defer { c.cancel() }
        let path = t.downPath.replacingOccurrences(of: "%d", with: String(bytes))
        let req = "GET \(path) HTTP/1.1\r\nHost: \(t.host)\r\nConnection: close\r\n\r\n"
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
            if done || elapsed >= seconds { break loop }
        }
        guard total > 0, elapsed > 0 else { throw SpeedError.failed("Download test returned no data.") }
        return Double(total) * 8 / elapsed / 1_000_000
    }

    static func upload(_ t: Target, bytes: Int, seconds: Double) async throws -> Double {
        let c = Conn(target: t, iface: iface)
        try await c.start()
        defer { c.cancel() }
        let header = "POST \(t.upPath) HTTP/1.1\r\nHost: \(t.host)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(bytes)\r\nConnection: close\r\n\r\n"
        try await c.send(Data(header.utf8))

        let chunk = Data(count: 262_144)
        var sent = 0
        let t0 = Date()
        var elapsed = 0.0
        while sent < bytes {
            try await c.send(chunk)
            sent += chunk.count
            elapsed = Date().timeIntervalSince(t0)
            if elapsed >= seconds { break }
        }
        guard elapsed > 0 else { throw SpeedError.failed("Upload test didn't run.") }
        return Double(sent) * 8 / elapsed / 1_000_000
    }

    /// Round-trip time to the router. A TCP connection to port 80 either opens or is refused;
    /// both mean the router answered, so both give a valid time. Returns nil if there's no reply.
    static func routerLatency(host: String) async -> Double? {
        let params = NWParameters.tcp
        params.requiredInterfaceType = iface
        let c = NWConnection(host: NWEndpoint.Host(host), port: 80, using: params)
        let q = DispatchQueue(label: "linkmeter.router")
        return await withCheckedContinuation { (k: CheckedContinuation<Double?, Never>) in
            var done = false
            let t0 = Date()
            func finish(_ v: Double?) {
                if done { return }
                done = true
                c.cancel()
                k.resume(returning: v)
            }
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(Date().timeIntervalSince(t0) * 1000)
                case .waiting(let e), .failed(let e):
                    if case .posix(let code) = e, code == .ECONNREFUSED {
                        finish(Date().timeIntervalSince(t0) * 1000)
                    } else {
                        finish(nil)
                    }
                default: break
                }
            }
            c.start(queue: q)
            q.asyncAfter(deadline: .now() + 1.5) { finish(nil) }
        }
    }
}
