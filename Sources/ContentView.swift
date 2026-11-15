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
                    Circle().fill(m.monitoring && m.wifiConnected ? teal : Color.gray).frame(width: 8, height: 8)
                    Text(m.monitoring ? "Live" : "Paused").font(.footnote).foregroundStyle(.secondary)
                }
                Button { m.setMonitoring(!m.monitoring) } label: {
                    Image(systemName: m.monitoring ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                        .background(panel).clipShape(Circle())
                }
                .tint(.white)
            }

            bandCard
            speedCard

            Spacer(minLength: 0)

            if !m.wifiConnected {
                Text("Connect to Wi-Fi to measure the link.").font(.footnote).foregroundStyle(.secondary)
            }
            if let e = m.errorText {
                Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            Text("Link speed is measured with short repeating test bursts, about 80 MB a minute. iOS doesn't share the band or the router's negotiated rate with apps, so choose the band yourself.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Color(white: 0.06).ignoresSafeArea())
        .onChange(of: scenePhase) { phase in
            if phase == .active { if wasMonitoring { m.setMonitoring(true) } }
            else { wasMonitoring = m.monitoring; m.setMonitoring(false) }
        }
    }

    private var bandCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Band").font(.subheadline).foregroundStyle(.secondary)
            Menu {
                ForEach(WifiBand.allCases) { b in
                    Button(b.rawValue) { m.band = b }
                }
            } label: {
                HStack {
                    Text(m.band == .unset ? "Set band" : m.band.rawValue)
                        .font(.system(size: 44, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.body)
                    Spacer()
                }
                .foregroundStyle(m.band == .unset ? Color.secondary : teal)
            }
            if let hint = m.bandHint {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(m.band == .unset ? "Tap to choose" : "Set by you").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link speed").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                speed("Down", m.result?.down, "arrow.down")
                speed("Up", m.result?.up, "arrow.up")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func speed(_ title: String, _ v: Double?, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.footnote).foregroundStyle(.secondary)
            Text(v.map(fmt) ?? "—").font(.system(size: 44, weight: .semibold)).minimumScaleFactor(0.6)
            Text("Mbps").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fmt(_ v: Double) -> String { v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v) }
}
