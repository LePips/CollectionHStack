import CollectionHStack
import SwiftUI

@main
struct CollectionHStackExampleApp: App {
    var body: some Scene {
        WindowGroup("CollectionHStack") {
            #if os(tvOS)
            if ProcessInfo.processInfo.arguments.contains("--focus-demo") {
                if ProcessInfo.processInfo.arguments.contains("--nested-focus-scope") {
                    CollectionHStackFocusScope {
                        NavigationStack { FocusBehaviorView() }
                    }
                } else {
                    NavigationStack { FocusBehaviorView() }
                }
            } else {
                ContentView()
            }
            #else
            ContentView()
                #if os(macOS)
                    .frame(minWidth: 680, minHeight: 480)
                #endif
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 720)
        #endif
    }
}
