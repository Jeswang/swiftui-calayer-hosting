import AppKit
import Combine

/// Analogous to RCTRootViewDelegate.rootViewDidChangeIntrinsicSize: the surface
/// notifies its host after it "renders" (here: on every internal JS-style tick).
protocol MockRNSurfaceDelegate: AnyObject {
    func surface(_ surface: MockRNSurfaceView, didRenderWithIntrinsicHeight height: CGFloat)
}

/// Stand-in for an RCTRootView / Fabric surface. The contract mirrors RN with
/// `sizeFlexibility = .height`: **width is owned by the host (SwiftUI); height
/// is computed from content (Yoga-style) and reported back one-way.**
///
/// It re-renders ~20x/sec to simulate RN committing frames, and changes its
/// content height every ~2s. Expensive to build (so it's pooled).
final class MockRNSurfaceView: NSView {
    static var creationCount = 0

    weak var surfaceDelegate: MockRNSurfaceDelegate?
    let surfaceID: String
    private let instanceNumber: Int

    private var rowCount = 6
    private var renderTimer: Timer?
    private(set) var renderCount = 0
    private(set) var intrinsicHeight: CGFloat = 0
    private var lastLaidOutWidth: CGFloat = -1

    override var isFlipped: Bool { true }   // top-left origin so rows read top-down

    init(id: String, simulatedCostSeconds: Double = 0.8) {
        self.surfaceID = id
        MockRNSurfaceView.creationCount += 1
        self.instanceNumber = MockRNSurfaceView.creationCount
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        if simulatedCostSeconds > 0 { Thread.sleep(forTimeInterval: simulatedCostSeconds) }
        startRendering()
        NSLog("🛠  MockRNSurface #\(instanceNumber) (id=\(id)) built")
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { renderTimer?.invalidate(); NSLog("💥 MockRNSurface #\(instanceNumber) DEINIT") }

    private func startRendering() {
        // ~20Hz "JS renders": most ticks don't change height; every ~2s the
        // content (rowCount) changes and height changes.
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        renderTimer = t
    }

    private func tick() {
        renderCount += 1
        if renderCount % 40 == 0 {          // content change roughly every 2s
            rowCount = Int.random(in: 4...12)
            recomputeHeight()               // changes intrinsicHeight + reports
        } else {
            notifyRendered()                // a render that does NOT change layout
        }
    }

    /// Yoga-style measure: height depends on width + content (narrower => taller).
    private func recomputeHeight() {
        let w = max(bounds.width, 1)
        let rowH: CGFloat = 30
        let widthPenalty = max(0, (320 - w)) / 320 * 10
        intrinsicHeight = CGFloat(rowCount) * (rowH + widthPenalty) + 16
        renderRows()
        notifyRendered()
    }

    private func notifyRendered() {
        surfaceDelegate?.surface(self, didRenderWithIntrinsicHeight: intrinsicHeight)
    }

    private func renderRows() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        let w = bounds.width
        let rowH: CGFloat = 30
        let widthPenalty = max(0, (320 - w)) / 320 * 10
        var y: CGFloat = 8
        for i in 0..<rowCount {
            let bar = CALayer()
            bar.frame = CGRect(x: 8, y: y, width: max(w - 16, 0), height: rowH + widthPenalty - 6)
            bar.backgroundColor = NSColor(calibratedHue: CGFloat(i) / CGFloat(max(rowCount, 1)),
                                          saturation: 0.6, brightness: 0.9, alpha: 1).cgColor
            bar.cornerRadius = 4
            layer?.addSublayer(bar)
            y += rowH + widthPenalty
        }
    }

    override func layout() {
        super.layout()
        // Width flows in from the host (SwiftUI). When it changes, RN re-measures.
        if abs(bounds.width - lastLaidOutWidth) > 0.5 {
            lastLaidOutWidth = bounds.width
            recomputeHeight()
        }
        renderRows()
    }
}

/// External owner of the expensive surfaces (same pooling principle as the others).
final class RNSurfacePool {
    static let shared = RNSurfacePool()
    private var byID: [String: MockRNSurfaceView] = [:]
    private init() {}
    func surface(for id: String) -> MockRNSurfaceView {
        if let s = byID[id] { return s }
        let s = MockRNSurfaceView(id: id)
        byID[id] = s
        return s
    }
}

/// Observable counters for the RN demo. Kept separate from `Metrics` so its
/// 20Hz updates only re-render the metrics panel, not the hosted surface.
final class RNDemoState: ObservableObject {
    static let shared = RNDemoState()
    @Published var renders = 0       // surface "frame commits"
    @Published var forwards = 0      // reports that reached SwiftUI's binding
    @Published var updateCalls = 0   // host updateNSView calls
    @Published var height: CGFloat = 0
    private init() {}

    func bumpRender()  { DispatchQueue.main.async { self.renders += 1 } }
    func bumpForward(height: CGFloat) { DispatchQueue.main.async { self.forwards += 1; self.height = height } }
    func bumpUpdate()  { DispatchQueue.main.async { self.updateCalls += 1 } }
    func reset() { DispatchQueue.main.async { self.renders = 0; self.forwards = 0; self.updateCalls = 0 } }
}
