import SwiftUI

/// Observable counters so the SwiftUI UI can show what the host/renderer layer
/// is actually doing. Mutations are dispatched async to avoid SwiftUI's
/// "publishing changes from within view updates" warning, since make/dismantle
/// happen during the view-update pass.
final class Metrics: ObservableObject {
    static let shared = Metrics()

    @Published var renderersBuilt = 0   // how many ExpensiveRenderer instances were ever constructed
    @Published var makeCalls = 0        // SwiftUI -> makeNSView
    @Published var dismantleCalls = 0   // SwiftUI -> dismantleNSView
    @Published var lastEvent = "—"

    private init() {}

    func recordMake(_ note: String) {
        DispatchQueue.main.async {
            self.makeCalls += 1
            self.renderersBuilt = ExpensiveRenderer.creationCount
            self.lastEvent = note
        }
    }

    func recordDismantle(_ note: String) {
        DispatchQueue.main.async {
            self.dismantleCalls += 1
            self.renderersBuilt = ExpensiveRenderer.creationCount
            self.lastEvent = note
        }
    }
}
