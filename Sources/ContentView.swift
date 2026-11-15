import SwiftUI

struct ContentView: View {
    @StateObject private var m = LinkModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasMonitoring = true

    private let teal = Color(red: 0.11, green: 0.62, blue: 0.46)
    private let panel = Color(white: 0.12)

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("LinkMeter").font(.title2.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(m.monitoring && m.connected ? teal : Color.gray).frame(width: 8, height: 8)
                    Text(m.monitoring ? "Live" : "Paused").font(.footnote).foregroundStyle(.secondary)
                }
                Button { m.setMonitoring(!m.monitoring) } label: {
                    Image(systemName: m.monitoring ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                        .background(panel).clipShape(Circle())
                }
                .tint(.white)
            }

            Picker("Connection", selection: $m.selected) {
                ForEach(LinkKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            connectionCard

            HStack(spacing: 12) {
                tile("Link down", value: m.result?.down, unit: "Mbps", icon: "arrow.down")
                tile("Link up", value: m.result?.up, unit: "Mbps", icon: "arrow.up")
            }

            trafficCard

            Spacer(minLength: 0)

            if let e = m.errorText {
                Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            Text("Link speed comes from short, repeating test bursts, about 80 MB a minute on Wi-Fi and 15 MB on cellular. iOS doesn't share the band, true dBm, or router link rate with apps.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Color(white: 0.06).ignoresSafeArea())
        .onChange(of: scenePhase) { phase in
            if phase == .active { if wasMonitoring { m.setMonitoring(true) } }
            else { wasMonitoring = m.monitoring; m.setMonitoring(false) }
        }
    }

    // MARK: Cards

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(m.selected.rawValue).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(m.connected ? m.pillText : "Not connected")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(m.connected ? teal.opacity(0.25) : Color.gray.opacity(0.25))
                    .foregroundStyle(m.connected ? teal : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(m.bigSignalText).font(.system(size: 44, weight: .semibold)).minimumScaleFactor(0.6)
                Spacer()
                signalBars
            }
            Text(m.signalCaption).font(.footnote).foregroundStyle(.secondary)

            if m.selected == .wifi {
                Divider().overlay(Color.white.opacity(0.1))
                HStack {
                    Text("Band").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(WifiBand.allCases) { b in
                            Button(b.rawValue) { m.band = b }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(m.band == .unset ? "Set band" : m.band.rawValue).font(.headline)
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                        .foregroundStyle(teal)
                    }
                }
                if let hint = m.bandHint {
                    Text(hint).font(.footnote).foregroundStyle(.secondary)
                } else if m.band != .unset {
                    Text("Set by you. iOS can't read the band.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live traffic", systemImage: "waveform.path.ecg").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("↓ \(fmt(m.liveRx))  ↑ \(fmt(m.liveTx)) Mbps").font(.footnote.monospacedDigit())
            }
            Sparkline(values: m.history).stroke(teal, lineWidth: 2).frame(height: 54)
            HStack {
                Label("Latency", systemImage: "timer").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(m.result.map { String(format: "%.0f ms", $0.latencyMs) } ?? "—")
                    .font(.footnote.monospacedDigit())
            }
        }
        .padding(14)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= m.bars ? barColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: CGFloat(8 + i * 8))
            }
        }
    }

    private var barColor: Color {
        switch m.bars { case 1: return .red; case 2: return .orange; default: return teal }
    }

    private func fmt(_ v: Double) -> String { v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v) }

    private func tile(_ title: String, value: Double?, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map(fmt) ?? "—").font(.system(size: 28, weight: .semibold))
                Text(unit).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct Sparkline: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else {
            p.move(to: CGPoint(x: 0, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return p
        }
        let top = max(values.max() ?? 1, 1)
        for (i, v) in values.enumerated() {
            let x = rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat(v / top)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
