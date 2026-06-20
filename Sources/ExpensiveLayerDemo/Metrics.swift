import SwiftUI

/// Observable counters so the SwiftUI UI can show what the host/renderer is
/// actually doing. Mutations are dispatched async to avoid SwiftUI's
/// "publishing changes from within view updates" warning, since make/dismantle
/// happen during the view-update pass.
final class Metrics: ObservableObject {
    static let shared = Metrics()

    @Published var renderersBuilt = 0   // instances ever constructed (for the active demo)
    @Published var makeCalls = 0        // SwiftUI -> makeNSView
    @Published var dismantleCalls = 0   // SwiftUI -> dismantleNSView
    @Published var lastEvent = "—"

    private init() {}

    func recordMake(_ note: String, built: Int) {
        DispatchQueue.main.async {
            self.makeCalls += 1
            self.renderersBuilt = built
            self.lastEvent = note
        }
    }

    func recordDismantle(_ note: String, built: Int) {
        DispatchQueue.main.async {
            self.dismantleCalls += 1
            self.renderersBuilt = built
            self.lastEvent = note
        }
    }

    /// Reset the make/dismantle counters when switching demos so the numbers
    /// stay meaningful per scenario. `renderersBuilt` reflects the cumulative
    /// static counter and is overwritten on the next make.
    func reset() {
        DispatchQueue.main.async {
            self.makeCalls = 0
            self.dismantleCalls = 0
            self.lastEvent = "— (reset)"
        }
    }
}
