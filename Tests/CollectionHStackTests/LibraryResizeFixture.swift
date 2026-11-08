#if os(iOS) || os(macOS)
@testable import CollectionHStack
import SwiftUI

@MainActor
@Observable
final class LibraryFixtureState {
    var padding: CGFloat = 0
    var topInset: CGFloat = 0
    @ObservationIgnored
    var providedWidths: [Int: CGFloat] = [:]
    /// Includes views supplied to native items and the representative measurement host.
    @ObservationIgnored
    var suppliedViews = 0
    @ObservationIgnored
    var representativeViews = 0
}

struct StackResizeReport {
    let drift: [CGFloat]
    let frames: Int
    let suppliedViews: Int
    var maximumAnchorDrift: CGFloat {
        drift.max() ?? 0
    }
}

struct LibraryItem: Identifiable { let id: Int }

/// Rebuilds the row's configuration from its current width, like an adaptive
/// media shelf. Both kits use the same poster content and proposal sequence.
struct LibraryFixtureRoot: View {
    let state: LibraryFixtureState
    private let items: [LibraryItem]
    init(state: LibraryFixtureState, itemCount: Int) {
        self.state = state
        items = (0 ..< itemCount).map(LibraryItem.init)
    }

    var body: some View {
        GeometryReader { outer in
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    CollectionHStack(
                        uniqueElements: items,
                        minWidth: geometry.size.width < 600 ? 160 : 200,
                        columnFraction: 0.5, rows: 2
                    ) { item in
                        card(item, width: geometry.size.width)
                    }
                    .insets(EdgeInsets(top: state.topInset, leading: 20, bottom: 0, trailing: 20))
                    .itemSpacing(10)
                    .scrollBehavior(.continuousLeadingEdge)
                    #if canImport(UIKit)
                    .contentInsetAdjustmentBehavior(.never)
                    #endif
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, state.padding)
            .frame(width: outer.size.width, height: outer.size.height)
            .animation(.smooth(duration: 0.35), value: state.padding)
        }
        .ignoresSafeArea()
    }

    private func card(_ item: LibraryItem, width: CGFloat) -> LibraryCard {
        state.providedWidths[item.id] = width
        state.suppliedViews += 1
        if item.id == 0 {
            state.representativeViews += 1
        }
        return LibraryCard(index: item.id) { _ = width }
    }
}

/// Shaped like a media poster button: artwork with overlays, a matched transition
/// source, hover and context menu effects, geometry tracking, and an action closure,
/// which makes every re-render evaluate the card's body.
struct LibraryCard: View {
    @Namespace
    private var namespace
    @State
    private var size: CGSize = .zero

    let index: Int
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill").padding(4)
                    }
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(.white)
                            .frame(width: max(0, size.width * 0.4), height: 4)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    #if os(iOS)
                    .contentShape(.contextMenuPreview, Rectangle())
                    .matchedTransitionSource(id: "item", in: namespace)
                    #endif
                    .shadow(radius: 2)
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif
                Text("Title \(index)").font(.footnote).lineLimit(1)
                Text("2024 · Drama").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.borderless)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Play", systemImage: "play.fill") {}
            Button("Mark Played", systemImage: "checkmark") {}
        }
    }
}
#endif
