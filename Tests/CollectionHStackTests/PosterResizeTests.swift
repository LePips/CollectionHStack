@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct PosterResizeTests {
    #if canImport(UIKit)
    @Test
    func `committed subpixel width does not collapse rows measured at rounded proposal`() throws {
        let configuration = CollectionHStack(count: 100, columns: 3, rows: 2) { _ in
            VStack(spacing: 6) {
                Color.blue.aspectRatio(2 / 3, contentMode: .fit)
                Text("Title").frame(height: 28)
            }
        }
        .insets(horizontal: 10)
        .itemSpacing(10)
        let stack = makeStack(configuration)
        stack.traitOverrides.displayScale = 2
        let proposal = stack.fittingSize(forWidth: 700)
        // Animation interpolation can commit a width slightly beyond the proposal
        // while keeping its pixel-aligned height.
        stack.frame = CGRect(x: 0, y: 0, width: 700.0001, height: proposal.height)
        stack.layoutIfNeeded()
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.layoutIfNeeded()
        let first = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame
        let second = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame
        #expect(abs(first.minX - second.minX) < 0.001)
        #expect(second.minY >= first.maxY + 10 - 0.001)
    }

    @Test
    func `hosted animated reserved captions keep rows and following siblings separated`() async throws {
        let state = AnimatedPosterState()
        let host = UIHostingController(rootView: AnimatedPosterRoot(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1050, height: 1400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        let collection = try #require(findCollection(host.view))
        let pixel = 1 / max(collection.traitCollection.displayScale, 1)
        let nextSibling = try #require(findSibling(host.view))
        let retained = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let initialWidth = retained.frame.width
        state.padding = 450
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        var intermediateSamples = 0
        for _ in 0 ..< 45 {
            try await Task.sleep(for: .milliseconds(16))
            host.view.layoutIfNeeded()
            collection.layoutIfNeeded()
            let width = retained.frame.width
            if width < initialWidth - 1, width > 190 {
                intermediateSamples += 1
            }
            let measurement = ContentMeasurement()
            let reference = UIHostingController(rootView: ContentMeasurementLayout(width: width, measurement: measurement) {
                WrappingPoster(reservesCaptionSpace: true).frame(width: width)
            })
            reference.safeAreaRegions.remove(.container)
            _ = reference.sizeThatFits(in: .zero)
            #expect(abs(retained.frame.height - measurement.size.height) < 1)
            let second = try #require(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
            #expect(
                second.frame.minY >= retained.frame.maxY + 10 - pixel,
                "Cell \(retained.frame), next \(second.frame), viewport \(collection.bounds), outer \(String(describing: collection.superview?.bounds))"
            )
            let contentBottom = collection.convert(CGPoint(x: 0, y: second.frame.maxY), to: host.view).y
            let siblingTop = nextSibling.convert(nextSibling.bounds, to: host.view).minY
            #expect(contentBottom <= siblingTop + pixel + 0.001, "Content bottom \(contentBottom), next sibling \(siblingTop)")
            #expect(collection.cellForItem(at: IndexPath(item: 0, section: 0)) === retained)
        }
        #expect(intermediateSamples > 0)
    }

    @Test
    func `live wrapping captions resize without overlapping following siblings`() async throws {
        let state = AnimatedPosterState()
        let host = UIHostingController(rootView: AnimatedPosterRoot(state: state, reservesCaptionSpace: false, animates: false))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1050, height: 1400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for padding: CGFloat in [0, 120.1, 120.2, 450, 290.1, 0] {
            state.padding = padding
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            host.view.layoutIfNeeded()
            let collection = try #require(findCollection(host.view))
            let pixel = 1 / max(collection.traitCollection.displayScale, 1)
            collection.layoutIfNeeded()
            let first = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            let second = try #require(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
            let sibling = try #require(findSibling(host.view))
            let measurement = ContentMeasurement()
            let width = first.frame.width
            let reference = UIHostingController(rootView: ContentMeasurementLayout(width: width, measurement: measurement) {
                WrappingPoster().frame(width: width)
            })
            reference.safeAreaRegions.remove(.container)
            _ = reference.sizeThatFits(in: .zero)
            #expect(abs(first.frame.height - measurement.size.height) < 1)
            #expect(second.frame.minY >= first.frame.maxY + 10 - pixel)
            let contentBottom = collection.convert(CGPoint(x: 0, y: second.frame.maxY), to: host.view).y
            #expect(contentBottom <= sibling.convert(sibling.bounds, to: host.view).minY + pixel + 0.001)
        }
    }

    private func findCollection(_ view: UIView) -> UICollectionView? {
        (view as? UICollectionView) ?? view.subviews.lazy.compactMap(findCollection).first
    }

    private func findSibling(_ view: UIView) -> UIView? {
        if view.accessibilityIdentifier == "next-poster-sibling" {
            return view
        }
        return view.subviews.lazy.compactMap(findSibling).first
    }

    @Test
    func `animated poster captions are measured at every intermediate width`() throws {
        var requests = 0
        let configuration = CollectionHStack(count: 10000, columns: 3, rows: 2) { _ in
            requests += 1
            return WrappingPoster()
        }
        .insets(horizontal: 10)
        .itemSpacing(10)
        let stack = makeStack(configuration)
        let source: CGFloat = 390
        let target: CGFloat = 1200
        stack.frame = CGRect(origin: .zero, size: stack.fittingSize(forWidth: source))
        stack.layoutIfNeeded()
        let sourceItem = stack.computeSizes(forWidth: source).itemSize
        stack.prepareForLayout()
        _ = stack.fittingSize(forProposedWidth: target)
        let targetWidth = try #require(LayoutMetrics(
            layout: configuration.layout, insets: configuration.insets, itemSpacing: 10
        ).itemWidth(for: target))
        let requestsBefore = requests

        // These samples cross several caption line breaks. Endpoint height
        // interpolation cannot describe those discontinuous changes.
        for step in 0 ... 120 {
            let progress = CGFloat(step) / 120
            let width = source + (target - source) * progress
            let itemWidth = sourceItem.width + (targetWidth - sourceItem.width) * progress
            let measurement = ContentMeasurement()
            let reference = UIHostingController(rootView: ContentMeasurementLayout(width: itemWidth, measurement: measurement) {
                WrappingPoster().frame(width: itemWidth)
            })
            reference.safeAreaRegions.remove(.container)
            _ = reference.sizeThatFits(in: .zero)
            let result = stack.computeSizes(forWidth: width)
            #expect(abs(result.itemSize.width - itemWidth) < 0.001)
            #expect(
                abs(result.itemSize.height - measurement.size.height) < 0.001,
                "Caption height at \(itemWidth) must match its actual line count"
            )
            #expect(result.selfSize.height >= 2 * measurement.size.height + 10 - 0.001)
        }
        #expect(requests == requestsBefore, "Intermediate proposals reuse the content and hosting hierarchy")
    }
    #endif

    @Test
    func `poster buttons resize during subpoint width changes`() throws {
        let configuration = CollectionHStack(count: 10000, columns: 3, rows: 2) { _ in
            Button {} label: {
                VStack(spacing: 6) {
                    Rectangle()
                        .fill(.blue)
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .background(PosterGeometryMarker())
                    Text("Poster title")
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .frame(height: 28)
                        .background(PosterGeometryMarker(role: .caption))
                }
            }
            .buttonStyle(.plain)
        }
        .insets(horizontal: 10)
        .itemSpacing(10)
        #if os(macOS)
        _ = NSApplication.shared
        let stack = NSCollectionHStack(configuration: configuration)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let parent = try NSView(frame: #require(window.contentView?.bounds))
        window.contentView = parent
        parent.addSubview(stack)
        window.orderBack(nil)
        defer { stack.disconnect()
            window.close()
        }
        #else
        let stack = makeStack(configuration)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        window.rootViewController = UIViewController()
        try #require(window.rootViewController?.view.addSubview(stack))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        #endif

        let widths = (0 ... 24).map { CGFloat(700) + CGFloat($0) / 10 }
            + (0 ... 24).map { CGFloat(700) - CGFloat($0) / 10 }
        var previousWidth: CGFloat?
        var renderedWidths: Set<CGFloat> = []
        for width in widths {
            let itemWidth = (width - 40) / 3
            let fittingSize = stack.fittingSize(forWidth: width)
            stack.frame = CGRect(origin: .zero, size: fittingSize)
            #if os(macOS)
            stack.needsLayout = true
            stack.layoutSubtreeIfNeeded()
            let collection = stack.collectionView
            let cell = try #require(collection.item(at: IndexPath(item: 0, section: 0)))
            cell.view.layoutSubtreeIfNeeded()
            let renderedArtwork = try #require(findArtwork(cell.view))
            let renderedCaption = try #require(findCaption(cell.view))
            let artworkFrame = renderedArtwork.convert(renderedArtwork.bounds, to: collection)
            let captionFrame = renderedCaption.convert(renderedCaption.bounds, to: collection)
            let pixel = 1 / max(window.backingScaleFactor, 1)
            let size = try #require(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).size
            let second = try #require(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame
            #expect(collection.visibleItems().count < 30)
            #else
            stack.setNeedsLayout()
            stack.layoutIfNeeded()
            let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
            collection.layoutIfNeeded()
            let cell = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            cell.layoutIfNeeded()
            let renderedArtwork = try #require(findArtwork(cell))
            let renderedCaption = try #require(findCaption(cell))
            let artworkFrame = renderedArtwork.convert(renderedArtwork.bounds, to: collection)
            let captionFrame = renderedCaption.convert(renderedCaption.bounds, to: collection)
            let pixel = 1 / max(collection.traitCollection.displayScale, 1)
            let size = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).size
            let second = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame
            #expect(collection.visibleCells.count < 30)
            #endif
            #expect(abs(size.width - itemWidth) < 0.001)
            #expect(abs(size.height - (itemWidth * 1.5 + 34)) < 0.001)
            #expect(
                second.minY >= size.height + 10 - 0.001,
                "Rows retain spacing at \(width); item \(size), next \(second), collection \(collection.bounds)"
            )
            if let previousWidth, previousWidth != itemWidth {
                #expect(size.width != previousWidth, "Each subpoint resize updates layout attributes")
            }
            previousWidth = size.width
            let artwork = renderedArtwork.bounds.size
            renderedWidths.insert(artwork.width)
            // Hosting views align rendering to physical pixels; the underlying
            // collection metrics above must still respond to every proposal.
            #expect(abs(artwork.width - itemWidth) < 1)
            #expect(abs(artwork.height - artwork.width * 1.5) < 1)
            #expect(artworkFrame.maxY <= captionFrame.minY + pixel)
            #expect(captionFrame.maxY <= second.minY + pixel, "Rendered caption remains above the next row")
        }
        #expect(renderedWidths.count > 1, "Hosted artwork must resize as fine changes accumulate")
    }

    #if canImport(UIKit)
    private func makeStack<Content: View>(_ configuration: CollectionHStack<Int, [Int], Int, Content>)
    -> UICollectionHStack<Int, [Int], Int, Content> {
        let stack = UICollectionHStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: true,
            data: configuration.data, dataPrefix: nil, insets: configuration.insets,
            isCarousel: false, itemSpacing: configuration.itemSpacing, layout: configuration.layout,
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: .continuous, viewProvider: configuration.viewProvider
        )
        // These fixtures provide their full viewport explicitly, including on TVs
        // whose automatic overscan safe area would otherwise be added a second time.
        stack.configure(configuration.contentInsetAdjustmentBehavior(.never))
        return stack
    }
    #endif
}

private struct WrappingPoster: View {
    var reservesCaptionSpace = false

    var body: some View {
        VStack(spacing: 6) {
            Rectangle().fill(.blue).aspectRatio(2 / 3, contentMode: .fill)
            if reservesCaptionSpace {
                caption.lineLimit(3, reservesSpace: true)
            } else {
                caption.fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var caption: some View {
        Text("A very long poster title that must wrap into several lines at narrow widths")
            .font(.system(size: 17))
    }
}

#if canImport(UIKit)
@MainActor
@Observable
private final class AnimatedPosterState {
    var padding: CGFloat = 0
}

private struct AnimatedPosterRoot: View {
    let state: AnimatedPosterState
    var reservesCaptionSpace = true
    var animates = true

    var body: some View {
        VStack(spacing: 0) {
            CollectionHStack(count: 100, columns: 3, rows: 2) { _ in
                WrappingPoster(reservesCaptionSpace: reservesCaptionSpace)
            }
            .insets(horizontal: 10)
            .itemSpacing(10)
            .contentInsetAdjustmentBehavior(.never)
            Color.clear
                .frame(height: 2)
                .background(PosterGeometryMarker(identifier: "next-poster-sibling"))
            Spacer(minLength: 0)
        }
        .padding(.leading, state.padding)
        .animation(animates ? .linear(duration: 0.4) : nil, value: state.padding)
        .ignoresSafeArea()
    }
}
#endif

#if os(macOS)
private typealias PosterNativeView = NSView
private final class PosterMarkerView: NSView {
    var role = PosterMarkerRole.artwork
}

private struct PosterGeometryMarker: NSViewRepresentable {
    var role = PosterMarkerRole.artwork

    func makeNSView(context: Context) -> PosterMarkerView {
        let view = PosterMarkerView()
        view.role = role
        return view
    }

    func updateNSView(_ nsView: PosterMarkerView, context: Context) {}
}
#else
private typealias PosterNativeView = UIView
private final class PosterMarkerView: UIView {
    var role = PosterMarkerRole.artwork
}

private struct PosterGeometryMarker: UIViewRepresentable {
    var role = PosterMarkerRole.artwork
    var identifier = ""

    func makeUIView(context: Context) -> PosterMarkerView {
        let view = PosterMarkerView()
        view.role = role
        view.accessibilityIdentifier = identifier
        return view
    }

    func updateUIView(_ uiView: PosterMarkerView, context: Context) {}
}
#endif

@MainActor
private func findArtwork(_ view: PosterNativeView) -> PosterMarkerView? {
    if let marker = view as? PosterMarkerView, marker.role == .artwork {
        return marker
    }
    return view.subviews.lazy.compactMap(findArtwork).first
}

@MainActor
private func findCaption(_ view: PosterNativeView) -> PosterMarkerView? {
    if let marker = view as? PosterMarkerView, marker.role == .caption {
        return marker
    }
    return view.subviews.lazy.compactMap(findCaption).first
}

private enum PosterMarkerRole { case artwork, caption }
