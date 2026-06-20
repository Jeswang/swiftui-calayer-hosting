import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var metrics = Metrics.shared

    @State private var usePool = true
    @State private var identityToken = 0   // changing this forces a SwiftUI teardown
    @State private var heartbeat = 0       // unrelated state; proves cheap re-eval is harmless

    // Fires once a second to re-evaluate this view's body (a cheap update that
    // must NOT cause make/dismantle).
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            metricsPanel
            Divider()
            hostedArea
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 660)
        .onReceive(tick) { _ in heartbeat += 1 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hosting an expensive CALayer system out of SwiftUI")
                .font(.title2).bold()
            Text("Option A: the renderer lives in an external pool; SwiftUI owns only a disposable host view that reparents the layer in/out.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $usePool) {
                Text("Use pooled renderer (Option A)").bold()
                    + Text(usePool ? "  — reuse across teardown" : "  — NAIVE: rebuild every teardown")
                    .foregroundColor(usePool ? .green : .red)
            }
            .toggleStyle(.switch)

            HStack(spacing: 12) {
                Button {
                    identityToken += 1   // change identity -> SwiftUI tears down & rebuilds the representable
                } label: {
                    Label("Force SwiftUI teardown (toggle .id)", systemImage: "arrow.triangle.2.circlepath")
                }
                Text("identity = \(identityToken)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("heartbeat = \(heartbeat)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var metricsPanel: some View {
        HStack(spacing: 24) {
            stat("Renderers built", metrics.renderersBuilt,
                 color: metrics.renderersBuilt <= 1 ? .green : .red,
                 hint: "stays 1 when pooled")
            stat("makeNSView", metrics.makeCalls, color: .primary, hint: "host views created")
            stat("dismantleNSView", metrics.dismantleCalls, color: .primary, hint: "host views destroyed")
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
            if usePool {
                PooledLayerView(rendererID: "main-canvas")
            } else {
                NaiveLayerView(rendererID: "main-canvas")
            }
        }
        .id(identityToken) // forcing a new identity = forcing make/dismantle of the host
        .frame(maxWidth: .infinity, minHeight: 340)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
    }
}
