import SwiftUI
import AppKit

/// Strategies for what happens to a heavy layer-backed view when SwiftUI tears
/// down its host (e.g. a scroll-recycle).
enum FenceStrategy: String, CaseIterable, Identifiable {
    case evict     = "Evict to nil (fence)"
    case park      = "Park in window (no fence)"
    case skipSuper = "Skip super (unsafe)"
    var id: String { rawValue }
}

/// Stand-in for a heavy, layer-backed view (à la ELMNView): a deep tree of
/// gradient/shadow sublayers. Leaving a window forces a CoreAnimation fence
/// ("synchronize with render server"), and the cost scales with this tree.
final class HeavyLayerView: NSView {
    static var creationCount = 0
    let id: String
    let instanceNumber: Int

    /// When true, skip `[super viewWillMoveToWindow:nil]` (the other-session hack).
    var skipWindowDetach = false

    init(id: String, topLayers: Int = 60) {
        self.id = id
        HeavyLayerView.creationCount += 1
        self.instanceNumber = HeavyLayerView.creationCount
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildHeavyTree(topLayers)
        NSLog("🛠  HeavyLayerView #\(instanceNumber) built (\(topLayers) top layers)")
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildHeavyTree(_ count: Int) {
        for i in 0..<count {
            let g = CAGradientLayer()
            let hue = CGFloat(i) / CGFloat(count)
            g.colors = [NSColor(calibratedHue: hue, saturation: 0.6, brightness: 0.95, alpha: 1).cgColor,
                        NSColor(calibratedHue: hue, saturation: 0.8, brightness: 0.5, alpha: 1).cgColor]
            g.cornerRadius = 6
            g.shadowColor = NSColor.black.cgColor
            g.shadowOpacity = 0.3
            g.shadowRadius = 4
            g.shadowOffset = CGSize(width: 0, height: 1)
            for _ in 0..<2 {                       // nested sublayers thicken the tree
                let s = CALayer()
                s.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
                s.cornerRadius = 3
                g.addSublayer(s)
            }
            layer?.addSublayer(g)
        }
    }

    override func layout() {
        super.layout()
        guard let subs = layer?.sublayers, bounds.width > 0 else { return }
        let cols = 8
        let rows = max(1, Int(ceil(Double(subs.count) / Double(cols))))
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, s) in subs.enumerated() {
            let r = i / cols, c = i % cols
            s.frame = CGRect(x: CGFloat(c) * cellW + 2, y: CGFloat(r) * cellH + 2,
                             width: cellW - 4, height: cellH - 4)
            for (k, sub) in (s.sublayers ?? []).enumerated() {
                sub.frame = CGRect(x: 3, y: 3 + CGFloat(k) * 6, width: max(s.frame.width - 6, 0), height: 4)
            }
        }
        CATransaction.commit()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if skipWindowDetach, newWindow == nil, window != nil {
            NSLog("⏭  HeavyLayerView #\(instanceNumber) SKIP [super viewWillMoveToWindow:nil]")
            return                                  // the hack: short-circuit AppKit teardown
        }
        if newWindow == nil, window != nil {
            NSLog("🧊 HeavyLayerView #\(instanceNumber) leaving window (fence path)")
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// Owns one persistent, in-window container per window. Reparenting a view INTO
/// this (from another view in the same window) moves it window→window — no
/// `_setWindow:nil`, so no fence — while keeping AppKit's invariants intact.
final class WindowPoolHost {
    static let shared = WindowPoolHost()
    private var containers: [ObjectIdentifier: NSView] = [:]
    private init() {}

    func container(in window: NSWindow) -> NSView {
        let key = ObjectIdentifier(window)
        if let c = containers[key], c.window === window { return c }
        let c = NSView(frame: NSRect(x: -10_000, y: -10_000, width: 1, height: 1)) // off-screen, in-window
        c.wantsLayer = true
        window.contentView?.addSubview(c)
        containers[key] = c
        NSLog("🪟 WindowPoolHost: created persistent in-window container")
        return c
    }
}

/// Pool so the heavy view is built once (the recreation cost is a separate axis
/// from the fence cost — this isolates the fence).
final class HeavyViewPool {
    static let shared = HeavyViewPool()
    private var byID: [String: HeavyLayerView] = [:]
    private init() {}
    func view(for id: String) -> HeavyLayerView {
        if let v = byID[id] { return v }
        let v = HeavyLayerView(id: id); byID[id] = v; return v
    }
}

final class FenceMetrics: ObservableObject {
    static let shared = FenceMetrics()
    @Published var recycles = 0
    @Published var windowLostCount = 0     // teardowns where the heavy view actually left the window
    @Published var lastTeardownMs = 0.0
    @Published var avgTeardownMs = 0.0
    @Published var maxTeardownMs = 0.0
    private var totalMs = 0.0
    private init() {}

    func recordTeardown(windowLost: Bool, ms: Double) {
        DispatchQueue.main.async {
            self.recycles += 1
            if windowLost { self.windowLostCount += 1 }
            self.lastTeardownMs = ms
            self.totalMs += ms
            self.maxTeardownMs = max(self.maxTeardownMs, ms)
            self.avgTeardownMs = self.totalMs / Double(self.recycles)
        }
    }
    func reset() {
        DispatchQueue.main.async {
            self.recycles = 0; self.windowLostCount = 0
            self.lastTeardownMs = 0; self.avgTeardownMs = 0; self.maxTeardownMs = 0; self.totalMs = 0
        }
    }
}

/// The cheap, disposable SwiftUI-owned host. It borrows the heavy view while
/// on-screen and, on the way out of the window, applies the chosen strategy.
final class HeavyHostView: NSView {
    let heavy: HeavyLayerView
    var strategy: FenceStrategy = .evict

    init(heavy: HeavyLayerView) {
        self.heavy = heavy
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() { super.layout(); heavy.frame = bounds }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        _ = WindowPoolHost.shared.container(in: w)   // ensure the persistent container exists
        if heavy.superview !== self {                // borrow the heavy view in (window→window if parked)
            heavy.skipWindowDetach = (strategy == .skipSuper)
            addSubview(heavy)
            heavy.frame = bounds
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, let w = window, heavy.superview === self else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        switch strategy {
        case .park:
            // Move the heavy view into the persistent in-window container BEFORE
            // this host leaves the window. Same window → no fence.
            WindowPoolHost.shared.container(in: w).addSubview(heavy)
        case .evict, .skipSuper:
            heavy.removeFromSuperview()              // heavy → window nil (fence), unless it skips super
        }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        FenceMetrics.shared.recordTeardown(windowLost: heavy.window == nil, ms: ms)
    }
}

struct FenceHostRepresentable: NSViewRepresentable {
    let id: String
    let strategy: FenceStrategy

    func makeNSView(context: Context) -> HeavyHostView {
        let host = HeavyHostView(heavy: HeavyViewPool.shared.view(for: id))
        host.strategy = strategy
        host.heavy.skipWindowDetach = (strategy == .skipSuper)
        return host
    }

    func updateNSView(_ nsView: HeavyHostView, context: Context) {
        nsView.strategy = strategy
        nsView.heavy.skipWindowDetach = (strategy == .skipSuper)
    }
}
