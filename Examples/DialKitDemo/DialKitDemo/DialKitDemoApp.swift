import SwiftUI

#if DEBUG
import DialkitmacOSAgent
#endif

@main
struct DialKitDemoApp: App {
    init() {
        #if DEBUG
        DialKitAgent.shared.start(appName: "Dialkit Demo")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
