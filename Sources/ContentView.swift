import SwiftUI

struct ContentView: View {
    @StateObject private var m = LinkModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasMonitoring = true
    @State private var pcField = ""
    @State private var routerField = ""

    private let teal = Color(red: 0.11, green: 0.62, blue: 0.46)
    private let panel = Color(white: 0.12)

    var body: some View {
        ScrollView {
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
                setupCard

                if !m.wifiConnected {
                    Text("Connect to Wi-Fi to measure the link.").font(.footnote).foregroundStyle(.secondary)
                }
                if let e = m.errorText {
                    Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                Text("iOS doesn't share the band or the router's negotiated rate with apps, so choose the band yourself and speed is measured with repeating test bursts.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(white: 0.06).ignoresSafeArea())
        .onAppear { pcField = m.lanHost; routerField = m.routerHost }
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
            Divider().overlay(Color.white.opacity(0.1))
            HStack {
                Label("To router", systemImage: "wifi.router").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(m.routerMs.map { String(format: "%.1f ms", $0) } ?? "—").font(.footnote.monospacedDigit())
            }
            Text(m.sourceCaption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PC address").font(.subheadline).foregroundStyle(.secondary)
            field("e.g. 192.168.1.20", text: $pcField) { m.lanHost = pcField.trimmingCharacters(in: .whitespaces) }
            Text("Router address, optional").font(.subheadline).foregroundStyle(.secondary)
            field(m.effectiveRouter ?? "e.g. 192.168.1.1", text: $routerField) {
                m.routerHost = routerField.trimmingCharacters(in: .whitespaces)
            }
            Text("Run Server/run_server.bat on the PC. It prints the address to enter here.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func field(_ placeholder: String, text: Binding<String>, commit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(commit)
            .padding(10)
            .background(Color(white: 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
