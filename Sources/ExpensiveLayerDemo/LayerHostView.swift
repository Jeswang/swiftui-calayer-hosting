import SwiftUI
import AppKit

/// A cheap, disposable, layer-backed NSView whose only job is to host a
/// (possibly shared) CALayer. SwiftUI is allowed to create and destroy this
/// freely — it owns nothing expensive.
final class LayerHostView: NSView {
    var renderer: ExpensiveRenderer? {
        didSet {
            // Detach the old layer only if it is still parented to *us*. During
            // an identity swap SwiftUI may build the new host before tearing
            // down the old one, in which case the shared layer has already been
            // reparented away and must not be yanked out.
            if let old = oldValue, old !== renderer, old.rootLayer.superlayer === layer {
                old.rootLayer.removeFromSuperlayer()
            }
            if let r = renderer, r.rootLayer.superlayer !== layer {
                r.rootLayer.removeFromSuperlayer() // detach from any previous host
                layer?.addSublayer(r.rootLayer)
            }
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        guard let r = renderer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true) // no implicit animation on resize
        r.rootLayer.frame = bounds
        r.layoutSublayers()
        CATransaction.commit()
    }
}

// MARK: - Option A: pooled renderer (reused across SwiftUI teardown)

struct PooledLayerView: NSViewRepresentable {
    let rendererID: String

    func makeNSView(context: Context) -> LayerHostView {
        let host = LayerHostView()
        host.renderer = RendererPool.shared.renderer(for: rendererID)
        Metrics.shared.recordMake("makeNSView (POOLED) — reparenting shared layer for \(rendererID)",
                                  built: ExpensiveRenderer.creationCount)
        return host
    }

    func updateNSView(_ nsView: LayerHostView, context: Context) {
        // Cheap struct re-evaluation lands here. Re-bind in case the id changed;
        // the pool makes this a no-op when it's the same renderer.
        nsView.renderer = RendererPool.shared.renderer(for: rendererID)
    }

    static func dismantleNSView(_ nsView: LayerHostView, coordinator: ()) {
        Metrics.shared.recordDismantle("dismantleNSView (POOLED) — detach only, pool keeps it alive",
                                       built: ExpensiveRenderer.creationCount)
        nsView.renderer = nil // didSet detaches the layer; the pool still owns the renderer
    }
}

// MARK: - The naive baseline (rebuilds the expensive renderer every time)

struct NaiveLayerView: NSViewRepresentable {
    let rendererID: String

    func makeNSView(context: Context) -> LayerHostView {
        let host = LayerHostView()
        host.renderer = ExpensiveRenderer(id: rendererID) // full cost, every single time
        Metrics.shared.recordMake("makeNSView (NAIVE) — building a brand-new renderer 😱",
                                  built: ExpensiveRenderer.creationCount)
        return host
    }

    func updateNSView(_ nsView: LayerHostView, context: Context) {}

    static func dismantleNSView(_ nsView: LayerHostView, coordinator: ()) {
        Metrics.shared.recordDismantle("dismantleNSView (NAIVE) — destroying renderer, work discarded",
                                       built: ExpensiveRenderer.creationCount)
        nsView.renderer = nil // released -> deinit -> everything thrown away
    }
}
