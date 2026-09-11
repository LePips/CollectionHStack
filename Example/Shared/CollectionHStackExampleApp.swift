import SwiftUI

@main
struct CollectionHStackExampleApp: App {
    var body: some Scene {
        WindowGroup("CollectionHStack") {
            ContentView()
                #if os(macOS)
                    .frame(minWidth: 680, minHeight: 480)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 720)
        #endif
    }
}
