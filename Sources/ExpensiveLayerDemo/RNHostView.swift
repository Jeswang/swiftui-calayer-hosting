import SwiftUI
import AppKit

/// The cycle-safe wrapper. This is where the loop-prevention logic lives — you
/// can't change RN's internals, only how your host forwards size back to SwiftUI.
///
///  * width flows DOWN (SwiftUI -> surface) via `layout()`
///  * height flows UP (surface -> SwiftUI) through `onHeight`, and in cycle-safe
///    mode it is **deduped + dispatched async** so RN's render loop never drives
///    SwiftUI layout and never writes state inside SwiftUI's current pass.
final class RNHostContainer: NSView, MockRNSurfaceDelegate {
    let surface: MockRNSurfaceView
    var cycleSafe = true
    var onHeight: ((CGFloat) -> Void)?
    private var lastForwarded: CGFloat = -1

    init(surface: MockRNSurfaceView) {
        self.surface = surface
        super.init(frame: .zero)
        wantsLayer = true
        if surface.superview !== self {     // reparent the pooled surface into this host
            surface.removeFromSuperview()
            addSubview(surface)
        }
        surface.surfaceDelegate = self      // re-wire (a pooled surface may have had an old host)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        surface.frame = bounds              // width owned by SwiftUI; surface re-measures height
    }

    // RN-style size report. The whole point of the demo is the difference here.
    func surface(_ s: MockRNSurfaceView, didRenderWithIntrinsicHeight height: CGFloat) {
        RNDemoState.shared.bumpRender()
        if cycleSafe {
            guard abs(height - lastForwarded) > 0.5 else { return }   // dedupe identical heights
            lastForwarded = height
            DispatchQueue.main.async { [weak self] in                 // out of the current pass
                RNDemoState.shared.bumpForward(height: height)
                self?.onHeight?(height)
            }
        } else {
            // NAIVE: forward every render, synchronously, no dedupe. RN's frame
            // loop now drives SwiftUI's binding (and layout) at ~20Hz.
            lastForwarded = height
            RNDemoState.shared.bumpForward(height: height)
            onHeight?(height)
        }
    }
}

struct MockRNView: NSViewRepresentable {
    let surfaceID: String
    let cycleSafe: Bool
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> RNHostContainer {
        let host = RNHostContainer(surface: RNSurfacePool.shared.surface(for: surfaceID))
        host.cycleSafe = cycleSafe
        host.onHeight = { h in height = h }
        return host
    }

    func updateNSView(_ nsView: RNHostContainer, context: Context) {
        RNDemoState.shared.bumpUpdate()
        nsView.cycleSafe = cycleSafe
        nsView.onHeight = { h in height = h }   // capture the latest binding
    }

    static func dismantleNSView(_ nsView: RNHostContainer, coordinator: ()) {
        if nsView.surface.superview === nsView { nsView.surface.removeFromSuperview() }
    }
}
