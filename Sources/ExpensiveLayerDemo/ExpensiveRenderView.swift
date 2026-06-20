import AppKit
import MetalKit

/// Stand-in for a heavy render component that is ALREADY a full `NSView` (not a
/// bare layer): it owns a live GPU draw loop via Metal AND an AppKit subview
/// (the HUD). This is the case where you must reparent the *view*, not a layer.
///
/// It demonstrates the lifecycle hooks that matter when a view is moved between
/// hosts: `viewDidMoveToWindow` (pause/resume the loop) and
/// `viewDidChangeBackingProperties` (keep crisp across displays).
final class ExpensiveRenderView: MTKView, MTKViewDelegate {
    /// Instances ever built. Climbs on every naive teardown; stays 1 when pooled.
    static var creationCount = 0

    let rendererID: String
    private let instanceNumber: Int
    private let createdAt = Date()
    private var buildTime: TimeInterval = 0

    private var commandQueue: MTLCommandQueue?
    private var frameCount = 0
    private let hud = NSTextField(labelWithString: "")

    init(id: String, simulatedCostSeconds: Double = 1.0) {
        self.rendererID = id
        ExpensiveRenderView.creationCount += 1
        self.instanceNumber = ExpensiveRenderView.creationCount

        let start = Date()
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)

        self.commandQueue = device?.makeCommandQueue()
        self.colorPixelFormat = .bgra8Unorm
        self.delegate = self
        self.isPaused = false
        self.enableSetNeedsDisplay = false   // free-running loop (MTKView uses a CVDisplayLink)
        self.preferredFramesPerSecond = 60

        // An AppKit subview living inside the render view — proves the subview
        // tree (not just a layer) survives reparenting between hosts.
        hud.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hud.textColor = .white
        hud.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        hud.drawsBackground = true
        hud.isBezeled = false
        hud.isEditable = false
        hud.maximumNumberOfLines = 0
        addSubview(hud)

        // Artificial blocking cost so recreation is obviously painful.
        if simulatedCostSeconds > 0 { Thread.sleep(forTimeInterval: simulatedCostSeconds) }
        self.buildTime = Date().timeIntervalSince(start)

        NSLog("🛠  ExpensiveRenderView #\(instanceNumber) (id=\(id)) built in %.2fs", buildTime)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    deinit { NSLog("💥 ExpensiveRenderView #\(instanceNumber) (id=\(rendererID)) DEINIT — work thrown away") }

    // MARK: - Lifecycle hooks that matter when reparenting

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isPaused = true   // left the hierarchy: stop the GPU loop, don't waste cycles
            NSLog("⏸  RenderView #\(instanceNumber) PAUSED (left window) — frames=\(frameCount)")
        } else {
            isPaused = false  // back in a window: resume; frameCount continues where it left off
            updateContentsScale()
            NSLog("▶️  RenderView #\(instanceNumber) RESUMED (entered window) — frames=\(frameCount)")
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()   // moved to a display with a different backing scale factor
    }

    private func updateContentsScale() {
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        hud.frame = CGRect(x: 10, y: bounds.height - 92, width: 320, height: 82)
    }

    // Events still work — it's a real NSView in the responder chain.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        NSLog("🖱  RenderView #\(instanceNumber) mouseDown at \(convert(event.locationInWindow, from: nil))")
    }

    // MARK: - MTKViewDelegate: the live GPU draw loop

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        frameCount += 1

        // Animate the clear color so it's visibly a running loop.
        let alive = Date().timeIntervalSince(createdAt)
        let hue = (alive * 0.1).truncatingRemainder(dividingBy: 1.0)
        if let c = NSColor(calibratedHue: hue, saturation: 0.6, brightness: 0.5, alpha: 1)
            .usingColorSpace(.deviceRGB) {
            clearColor = MTLClearColor(red: Double(c.redComponent),
                                       green: Double(c.greenComponent),
                                       blue: Double(c.blueComponent), alpha: 1)
        }

        guard let rpd = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let cmd = commandQueue?.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.endEncoding()        // a clear-only pass is enough to prove the loop runs
        cmd.present(drawable)
        cmd.commit()

        if frameCount % 6 == 0 { updateHUD(alive: alive) }
    }

    private func updateHUD(alive: TimeInterval) {
        hud.stringValue = """
        ExpensiveRenderView #\(instanceNumber)
        id: \(rendererID)
        frames: \(frameCount)   alive: \(String(format: "%.1f", alive))s
        built in: \(String(format: "%.2f", buildTime))s
        """
    }
}
