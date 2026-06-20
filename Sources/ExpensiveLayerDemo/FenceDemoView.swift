import SwiftUI

struct FenceDemoView: View {
    @StateObject private var m = FenceMetrics.shared
    @State private var strategy: FenceStrategy = .evict
    @State private var identity = 0
    @State private var autoRecycle = false

    private let ticker = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Strategy", selection: $strategy) {
                ForEach(FenceStrategy.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Toggle("Auto-recycle (simulate scrolling)", isOn: $autoRecycle).toggleStyle(.switch)
                Button("Recycle once") { identity += 1 }
                Button("Reset") { FenceMetrics.shared.reset() }
                Spacer()
            }

            metrics
            explanation
            Divider()

            FenceHostRepresentable(id: "heavy", strategy: strategy)
                .id(identity)   // bumping this = a SwiftUI teardown (a scroll-recycle)
                .frame(maxWidth: .infinity, minHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.3)))
        }
        .onReceive(ticker) { _ in if autoRecycle { identity += 1 } }
        .onAppear { FenceMetrics.shared.reset() }
        .onChange(of: strategy) { _ in FenceMetrics.shared.reset() }
    }

    private var metrics: some View {
        HStack(spacing: 22) {
            stat("recycles", "\(m.recycles)", .primary, "teardown/rebuilds")
            stat("window→nil", "\(m.windowLostCount)", m.windowLostCount == 0 ? .green : .red, "fence-causing")
            stat("avg teardown", String(format: "%.2f ms", m.avgTeardownMs), .primary, "main thread")
            stat("max", String(format: "%.2f ms", m.maxTeardownMs), .primary, "worst case")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.12)))
    }

    private func stat(_ t: String, _ v: String, _ c: Color, _ h: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.title3).monospacedDigit().foregroundColor(c)
            Text(h).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var explanation: some View {
        Text("Each recycle tears down the SwiftUI host (like a scroll list recycling a cell). “window→nil” counts how often the heavy layer-backed view actually left the window — the event that triggers the CoreAnimation fence. Evict: every recycle. Park (reparent into a persistent in-window container before the host leaves): zero, with AppKit invariants intact. Skip-super: measured, so you can see whether faking the window pointer actually avoids the nil transition on this OS.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
