import SwiftUI
import Combine

enum Demo: String, CaseIterable, Identifiable {
    case layer = "Layer hosting"
    case view  = "NSView hosting (Metal)"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var metrics = Metrics.shared

    @State private var demo: Demo = .layer
    @State private var usePool = true
    @State private var identityToken = 0   // changing this forces a SwiftUI teardown
    @State private var heartbeat = 0       // unrelated state; proves cheap re-eval is harmless

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Picker("Demo", selection: $demo) {
                ForEach(Demo.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            controls
            metricsPanel
            hint
            Divider()
            hostedArea
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 720)
        .onReceive(tick) { _ in heartbeat += 1 }
        .onChange(of: demo) { _ in Metrics.shared.reset() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hosting an expensive render component out of SwiftUI")
                .font(.title2).bold()
            Text("The expensive object lives in an external pool keyed by a stable token. SwiftUI owns only a disposable host that reparents it in/out, so identity churn no longer triggers recreation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $usePool) {
                Text("Use pool (reuse across teardown)").bold()
                    + Text(usePool ? "  — pooled" : "  — NAIVE: rebuild every teardown")
                    .foregroundColor(usePool ? .green : .red)
            }
            .toggleStyle(.switch)

            HStack(spacing: 12) {
                Button {
                    identityToken += 1   // change identity -> SwiftUI tears down & rebuilds the host
                } label: {
                    Label("Force SwiftUI teardown (toggle .id)", systemImage: "arrow.triangle.2.circlepath")
                }
                Button("Reset metrics") { Metrics.shared.reset() }
                Spacer()
                Text("identity = \(identityToken)").monospacedDigit().foregroundStyle(.secondary)
                Text("heartbeat = \(heartbeat)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var hint: some View {
        Text(demoHint)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var demoHint: String {
        switch demo {
        case .layer:
            return "Reparents a CALayer between host NSViews. In pooled mode the spinner keeps spinning and the tick counter keeps climbing across teardown — the backing store survived."
        case .view:
            return "Reparents a full NSView (live Metal draw loop + an AppKit HUD subview). On pooled teardown the view leaves its window (⏸ logged via viewDidMoveToWindow) then re-enters (▶️); the frame counter keeps climbing. Watch the console for the lifecycle logs."
        }
    }

    private var metricsPanel: some View {
        HStack(spacing: 24) {
            stat("Built", metrics.renderersBuilt,
                 color: metrics.renderersBuilt <= 1 ? .green : .red,
                 hint: "stays 1 when pooled")
            stat("makeNSView", metrics.makeCalls, color: .primary, hint: "hosts created")
            stat("dismantleNSView", metrics.dismantleCalls, color: .primary, hint: "hosts destroyed")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
        .overlay(alignment: .bottomLeading) {
            Text("last: \(metrics.lastEvent)")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.bottom, 4)
        }
    }

    private func stat(_ title: String, _ value: Int, color: Color, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title).monospacedDigit().foregroundColor(color)
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var hostedArea: some View {
        Group {
            switch (demo, usePool) {
            case (.layer, true):  PooledLayerView(rendererID: "main-canvas")
            case (.layer, false): NaiveLayerView(rendererID: "main-canvas")
            case (.view, true):   PooledRenderViewRepresentable(rendererID: "main-view")
            case (.view, false):  NaiveRenderViewRepresentable(rendererID: "main-view")
            }
        }
        .id(identityToken) // forcing a new identity = forcing make/dismantle of the host
        .frame(maxWidth: .infinity, minHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
    }
}
