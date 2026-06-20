import SwiftUI

/// Self-contained UI for the RN-style demo. It deliberately does NOT observe
/// RNDemoState (the 20Hz counter) so the hosted surface isn't re-evaluated by
/// the metrics; only `height` changes drive the host — which is exactly what we
/// want to measure.
struct RNDemoView: View {
    @State private var cycleSafe = true
    @State private var height: CGFloat = 60
    @State private var identity = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $cycleSafe) {
                Text("Cycle-safe forwarding").bold()
                    + Text(cycleSafe ? "  — dedupe + async (RN loop contained)"
                                     : "  — NAIVE: forward every render (loop leaks into SwiftUI)")
                    .foregroundColor(cycleSafe ? .green : .red)
            }
            .toggleStyle(.switch)

            HStack(spacing: 12) {
                Button("Reset counters") { RNDemoState.shared.reset() }
                Button { identity += 1 } label: {
                    Label("Force teardown", systemImage: "arrow.triangle.2.circlepath")
                }
                Spacer()
                Text(String(format: "RN height = %.0f", height))
                    .monospacedDigit().foregroundStyle(.secondary)
            }

            RNMetricsPanel()
            explanation
            Divider()

            ScrollView {
                MockRNView(surfaceID: "rn-surface", cycleSafe: cycleSafe, height: $height)
                    .frame(maxWidth: .infinity)        // SwiftUI owns width
                    .frame(height: max(height, 1))     // height follows the surface's report
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
                    .id(identity)
                Text("↑ width owned by SwiftUI (resize the window); height reported one-way by the surface")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            .frame(maxHeight: 300)
        }
        .onAppear { RNDemoState.shared.reset() }
        .onChange(of: cycleSafe) { _ in RNDemoState.shared.reset() }
    }

    private var explanation: some View {
        Text("The surface re-renders ~20×/sec (like RN committing frames) and changes its content height every ~2s. “forwards” = how often a render reached SwiftUI's binding. Cycle-safe keeps it ≈ the number of real height changes; naive lets every render through, so SwiftUI re-lays out at RN's frame rate.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct RNMetricsPanel: View {
    @StateObject private var state = RNDemoState.shared

    var body: some View {
        HStack(spacing: 22) {
            stat("surface renders", state.renders, color: .primary, hint: "RN frame commits")
            stat("forwards → SwiftUI", state.forwards, color: forwardColor, hint: "binding writes")
            stat("updateNSView", state.updateCalls, color: .primary, hint: "host re-updates")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
    }

    private var forwardColor: Color {
        guard state.renders > 20 else { return .primary }
        return Double(state.forwards) > Double(state.renders) * 0.25 ? .red : .green
    }

    private func stat(_ title: String, _ value: Int, color: Color, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title2).monospacedDigit().foregroundColor(color)
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
