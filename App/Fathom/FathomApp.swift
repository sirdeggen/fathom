import FathomCore
import SwiftUI

@main
struct FathomApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var controller: GameController?
    private let failure: String?

    init() {
        do {
            let catalog = try RegionDatabase.load()
            _controller = State(initialValue: GameController(catalog: catalog))
            failure = nil
        } catch {
            _controller = State(initialValue: nil)
            failure = "The bundled region outlines could not be read."
        }
    }

    var body: some View {
        if let controller {
            GameScreen(controller: controller)
        } else {
            ContentUnavailableView(
                "Outlines unavailable",
                systemImage: "map",
                description: Text(failure ?? "The region data is missing.")
            )
            .background(Ink.paper.ignoresSafeArea())
        }
    }
}
