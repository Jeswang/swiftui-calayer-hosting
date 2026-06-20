import AppKit

/// External owner of expensive render *views* (the NSView variant of
/// `RendererPool`). Same principle: the costly object lives here, keyed by a
/// stable token, so SwiftUI identity churn can destroy the host but never this.
final class ViewRendererPool {
    static let shared = ViewRendererPool()

    private var byID: [String: ExpensiveRenderView] = [:]

    private init() {}

    func view(for id: String) -> ExpensiveRenderView {
        if let existing = byID[id] {
            NSLog("✅ ViewPool HIT  id=\(id) (reusing, no cost)")
            return existing
        }
        NSLog("⏳ ViewPool MISS id=\(id) — building (this is the expensive part)")
        let v = ExpensiveRenderView(id: id)
        byID[id] = v
        return v
    }

    func evict(id: String) {
        byID[id] = nil
    }
}
