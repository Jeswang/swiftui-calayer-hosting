import AppKit
import QuartzCore

/// Stand-in for your real, heavy CALayer-based rendering system.
///
/// It is deliberately expensive to construct:
///   * builds a large tree of gradient/shadow sublayers, and
///   * blocks for `simulatedCostSeconds` to make the cost of *recreation*
///     impossible to miss in the UI (the window visibly freezes).
///
/// The important property for the demo: the rendered content + live state
/// (the spinning layer and the incrementing tick counter) live entirely on
/// CALayers owned by THIS object. Moving the root layer between host NSViews
/// preserves all of it — Core Animation does not re-render on reparent.
final class ExpensiveRenderer {
    /// Total instances ever built. If this climbs every time you force a
    /// teardown, you are paying the recreation cost. With the pool it stays put.
    static var creationCount = 0

    let id: String
    let rootLayer = CALayer()

    private let instanceNumber: Int
    private let createdAt = Date()
    private let buildTime: TimeInterval

    private let spinner = CALayer()
    private let tickLayer = CATextLayer()
    private var gridLayers: [CAGradientLayer] = []

    private var timer: Timer?
    private var ticks = 0

    init(id: String, simulatedCostSeconds: Double = 1.0, sublayerCount: Int = 400) {
        self.id = id
        ExpensiveRenderer.creationCount += 1
        self.instanceNumber = ExpensiveRenderer.creationCount

        let scale = NSScreen.main?.backingScaleFactor ?? 2

        let start = Date()

        // --- Real-ish expense: a big tree of gradient + shadow layers. ---
        for i in 0..<sublayerCount {
            let g = CAGradientLayer()
            let hue = CGFloat((i * 7 + instanceNumber * 23) % 360) / 360.0
            g.colors = [
                NSColor(calibratedHue: hue, saturation: 0.65, brightness: 0.95, alpha: 0.9).cgColor,
                NSColor(calibratedHue: hue, saturation: 0.85, brightness: 0.55, alpha: 0.9).cgColor
            ]
            g.cornerRadius = 4
            g.shadowColor = NSColor.black.cgColor
            g.shadowOpacity = 0.25
            g.shadowRadius = 3
            g.shadowOffset = CGSize(width: 0, height: 1)
            g.contentsScale = scale
            rootLayer.addSublayer(g)
            gridLayers.append(g)
        }

        // --- Artificial blocking cost so recreation is obviously painful. ---
        if simulatedCostSeconds > 0 {
            Thread.sleep(forTimeInterval: simulatedCostSeconds)
        }
        self.buildTime = Date().timeIntervalSince(start)

        configureSpinner(scale: scale)
        configureTickLabel(scale: scale)
        startAnimating()

        NSLog("🛠  ExpensiveRenderer #\(instanceNumber) (id=\(id)) built in %.2fs", buildTime)
    }

    deinit {
        timer?.invalidate()
        NSLog("💥 ExpensiveRenderer #\(instanceNumber) (id=\(id)) DEINIT — work thrown away")
    }

    // MARK: - Layout (called by the host view whenever its bounds change)

    func layoutSublayers() {
        let bounds = rootLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Background grid.
        let n = gridLayers.count
        let cols = max(1, Int(ceil(sqrt(Double(n)))))
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        for (i, layer) in gridLayers.enumerated() {
            let r = i / cols
            let c = i % cols
            layer.frame = CGRect(x: CGFloat(c) * cellW + 1,
                                 y: CGFloat(r) * cellH + 1,
                                 width: cellW - 2,
                                 height: cellH - 2)
        }

        // Spinner: set bounds + position (not frame) because it carries a transform.
        let side = min(bounds.width, bounds.height) * 0.30
        spinner.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        spinner.position = CGPoint(x: bounds.midX, y: bounds.midY)

        // Tick label centered.
        let labelW: CGFloat = 280, labelH: CGFloat = 110
        tickLayer.frame = CGRect(x: bounds.midX - labelW / 2,
                                 y: bounds.midY - labelH / 2,
                                 width: labelW, height: labelH)

        CATransaction.commit()
    }

    // MARK: - Setup

    private func configureSpinner(scale: CGFloat) {
        spinner.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        spinner.cornerRadius = 12
        spinner.borderColor = NSColor.systemBlue.cgColor
        spinner.borderWidth = 6
        spinner.shadowColor = NSColor.black.cgColor
        spinner.shadowOpacity = 0.4
        spinner.shadowRadius = 12
        spinner.zPosition = 50
        rootLayer.addSublayer(spinner)
    }

    private func configureTickLabel(scale: CGFloat) {
        tickLayer.foregroundColor = NSColor.white.cgColor
        tickLayer.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        tickLayer.cornerRadius = 8
        tickLayer.fontSize = 14
        tickLayer.alignmentMode = .center
        tickLayer.isWrapped = true
        tickLayer.contentsScale = scale
        tickLayer.zPosition = 100
        rootLayer.addSublayer(tickLayer)
        updateTickText()
    }

    private func startAnimating() {
        // Continuous rotation. Persists across reparenting because the animation
        // is attached to the layer object, which the pool keeps alive.
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = 3
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        spinner.add(rotation, forKey: "spin")

        // Live mutable state, ticking 10x/sec, owned by this object.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            self.updateTickText()
        }
        RunLoop.main.add(t, forMode: .common) // keep firing during resize/menus
        self.timer = t
    }

    private func updateTickText() {
        let alive = Date().timeIntervalSince(createdAt)
        let text = """
        renderer instance #\(instanceNumber)
        id: \(id)
        ticks: \(ticks)   alive: \(String(format: "%.1f", alive))s
        built in: \(String(format: "%.2f", buildTime))s
        """
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tickLayer.string = text
        CATransaction.commit()
    }
}
