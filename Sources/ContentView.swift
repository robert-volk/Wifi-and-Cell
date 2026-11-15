import SwiftUI

struct ContentView: View {
    @StateObject private var m = LinkModel()

    private let teal = Color(red: 0.11, green: 0.62, blue: 0.46)

    var body: some View {
        VStack(spacing: 16) {
            Text("LinkMeter")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Connection", selection: $m.selected) {
                ForEach(LinkKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            connectionCard

            HStack(spacing: 12) {
                tile("Download", value: m.result?.down, unit: "Mbps", icon: "arrow.down")
                tile("Upload", value: m.result?.up, unit: "Mbps", icon: "arrow.up")
            }
            tile("Latency", value: m.result?.latencyMs, unit: "ms", icon: "timer", wide: true)

            Spacer(minLength: 0)

            if let e = m.errorText {
                Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            Button(action: m.runTest) {
                HStack {
                    if m.running { ProgressView().tint(.white) }
                    Text(m.running ? "\(m.phase)  \(Int(m.liveMbps)) Mbps" : "Run speed test")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(m.running ? Color.gray.opacity(0.4) : teal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(m.running)

            Text("iOS doesn't share the radio band or dBm with apps, so band shows the connection type and signal is a quality reading.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Color(white: 0.06).ignoresSafeArea())
    }

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
                Text(m.qualityLabel).font(.system(size: 44, weight: .semibold))
                Spacer()
                bars
            }
            Text(m.quality == nil ? "Run a test to estimate signal"
                 : (m.qualityIsEstimate ? "Signal quality (estimated from last test)" : "Signal strength"))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var bars: some View {
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

    private func tile(_ title: String, value: Double?, unit: String, icon: String, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { $0 >= 100 ? String(format: "%.0f", $0) : String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .semibold))
                Text(unit).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
