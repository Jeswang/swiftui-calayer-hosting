import SwiftUI
import AppKit

/// A cheap, disposable container `NSView`. SwiftUI owns this; its only job is to
/// host the pooled render *view* by reparenting it via addSubview/removeFromSuperview.
///
/// Note: you generally don't *need* `wantsLayer` here — SwiftUI's NSHostingView
/// is layer-backed and layer-backing is inherited downward, so this subtree
/// becomes layer-backed anyway. It's set explicitly only for clarity.
final class ContainerHostView: NSView {
    var content: NSView? {
        didSet {
            // Detach the old content only if it's still parented to *us* (the new
            // host may have grabbed it first during an identity swap).
            if let old = oldValue, old !== content, old.superview === self {
                old.removeFromSuperview()
            }
            if let c = content, c.superview !== self {
                c.removeFromSuperview()                 // detach from any previous host
                c.frame = bounds
                c.autoresizingMask = [.width, .height]  // track the container's bounds
                addSubview(c)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

// MARK: - Pooled: reparent the whole NSView across SwiftUI teardown

struct PooledRenderViewRepresentable: NSViewRepresentable {
    let rendererID: String

    func makeNSView(context: Context) -> ContainerHostView {
        let host = ContainerHostView()
        host.content = ViewRendererPool.shared.view(for: rendererID)   // reparent (build only on miss)
        Metrics.shared.recordMake("makeNSView (POOLED NSView) — reparented render view \(rendererID)",
                                  built: ExpensiveRenderView.creationCount)
        return host
    }

    func updateNSView(_ nsView: ContainerHostView, context: Context) {
        nsView.content = ViewRendererPool.shared.view(for: rendererID) // no-op when same view
    }

    static func dismantleNSView(_ nsView: ContainerHostView, coordinator: ()) {
        Metrics.shared.recordDismantle("dismantleNSView (POOLED NSView) — detach only, pool keeps it alive",
                                       built: ExpensiveRenderView.creationCount)
        nsView.content = nil   // removeFromSuperview -> viewDidMoveToWindow(nil) -> loop pauses
    }
}

// MARK: - Naive baseline: rebuild the expensive NSView every time

struct NaiveRenderViewRepresentable: NSViewRepresentable {
    let rendererID: String

    func makeNSView(context: Context) -> ContainerHostView {
        let host = ContainerHostView()
        host.content = ExpensiveRenderView(id: rendererID)   // full cost, every time
        Metrics.shared.recordMake("makeNSView (NAIVE NSView) — building a brand-new render view 😱",
                                  built: ExpensiveRenderView.creationCount)
        return host
    }

    func updateNSView(_ nsView: ContainerHostView, context: Context) {}

    static func dismantleNSView(_ nsView: ContainerHostView, coordinator: ()) {
        Metrics.shared.recordDismantle("dismantleNSView (NAIVE NSView) — destroying render view",
                                       built: ExpensiveRenderView.creationCount)
        nsView.content = nil   // released -> deinit -> GPU loop + HUD thrown away
    }
}
