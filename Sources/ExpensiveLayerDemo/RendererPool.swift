import Foundation

/// The external owner of the expensive renderers.
///
/// This is the crux of "Option A": the costly objects live HERE, outside the
/// SwiftUI view tree, keyed by a stable token *you* mint. SwiftUI identity
/// churn (if/else, ForEach id changes, .id(), navigation) can freely destroy
/// the host NSView — it can never destroy what the pool retains.
final class RendererPool {
    static let shared = RendererPool()

    private var byID: [String: ExpensiveRenderer] = [:]

    private init() {}

    /// Return the existing renderer for this stable key, or build one once.
    func renderer(for id: String) -> ExpensiveRenderer {
        if let existing = byID[id] {
            NSLog("✅ Pool HIT  id=\(id) (reusing, no cost)")
            return existing
        }
        NSLog("⏳ Pool MISS id=\(id) — building (this is the expensive part)")
        let r = ExpensiveRenderer(id: id)
        byID[id] = r
        return r
    }

    /// Optional: truly evict a renderer when you know it's gone for good.
    func evict(id: String) {
        byID[id] = nil
    }
}
