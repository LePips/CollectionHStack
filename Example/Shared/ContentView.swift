import SwiftUI

struct ContentView: View {
    #if os(macOS) || os(iOS)
    @State private var selection: ExamplePage? = .playground
    #endif
    #if os(iOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #endif

    var body: some View {
        #if os(macOS)
        sidebarNavigation
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            sidebarNavigation
        } else {
            stackNavigation
        }
        #else
        stackNavigation
        #endif
    }

    #if os(macOS) || os(iOS)
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        #if os(macOS)
        .constant(.all)
        #else
        $columnVisibility
        #endif
    }

    private var sidebarNavigation: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            List(selection: $selection) {
                navigationRows
            }
            .listStyle(.sidebar)
            .navigationTitle("CollectionHStack")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let selection {
                selection.destination
            } else {
                ContentUnavailableView("Select an example", systemImage: "sidebar.left")
            }
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .toolbar(removing: .sidebarToggle)
        #endif
    }
    #endif

    private var stackNavigation: some View {
        NavigationStack {
            List {
                navigationRows
            }
            .navigationTitle("CollectionHStack")
            .navigationDestination(for: ExamplePage.self) { page in
                page.destination
            }
        }
    }

    @ViewBuilder
    private var navigationRows: some View {
        Section("Features") {
            ForEach(ExamplePage.features) { page in
                NavigationLink(value: page) {
                    Label(page.rawValue, systemImage: page.systemImage)
                }
            }
        }

        Section("Examples") {
            ForEach(ExamplePage.examples) { page in
                NavigationLink(value: page) {
                    Label(page.rawValue, systemImage: page.systemImage)
                }
            }
        }
    }
}

private enum ExamplePage: String, Identifiable {
    case playground = "Playground"
    case layout = "Layout"
    case scrollBehavior = "Scroll Behavior"
    case other = "Other"
    case carousels = "Carousels"
    case appStoreApps = "App Store Apps"
    case musicGenre = "Apple Music Genre"

    static let features: [Self] = [.playground, .layout, .scrollBehavior, .other]
    static let examples: [Self] = [.carousels, .appStoreApps, .musicGenre]

    var id: Self {
        self
    }

    var systemImage: String {
        switch self {
        case .playground: "slider.horizontal.3"
        case .layout: "rectangle.split.3x1"
        case .scrollBehavior: "arrow.left.and.right"
        case .other: "ellipsis.circle"
        case .carousels: "rectangle.stack"
        case .appStoreApps: "square.grid.2x2"
        case .musicGenre: "music.note"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .playground: PlaygroundView()
        case .layout: LayoutView()
        case .scrollBehavior: ScrollBehaviorView()
        case .other: OtherBehaviorView()
        case .carousels: CarouselView()
        case .appStoreApps: AppStoreAppsView()
        case .musicGenre: MusicGenreView()
        }
    }
}

#Preview {
    ContentView()
}
