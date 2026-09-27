@testable import CollectionHStack
import SwiftUI
import Testing

struct LayoutMetricsTests {
    private let insets = EdgeInsets(top: 5, leading: 20, bottom: 7, trailing: 30)

    @Test
    func fractionalColumnsReserveOnlyTheLeadingInset() throws {
        let whole = LayoutMetrics(layout: .grid(columns: 3, rows: 2, columnTrailingInset: 5), insets: insets, itemSpacing: 10)
        let fractional = LayoutMetrics(layout: .grid(columns: 2.5, rows: 2, columnTrailingInset: 5), insets: insets, itemSpacing: 10)
        #expect(try abs(#require(whole.itemWidth(for: 500)) - 425 / 3) < 0.0001)
        #expect(fractional.itemWidth(for: 500) == 182)
        #expect(fractional.height(for: CGSize(width: 182, height: 40)) == 102)
    }

    @Test
    func minimumWidthChangesColumnsAtTheSpacingBoundary() throws {
        let metrics = LayoutMetrics(layout: .minimumWidth(columnWidth: 100, rows: 1), insets: insets, itemSpacing: 10)
        #expect(try abs(#require(metrics.itemWidth(for: 259.9)) - 209.9) < 0.0001)
        #expect(metrics.itemWidth(for: 260) == 100)
        #expect(metrics.itemWidth(for: 70) == 20)
        #expect(metrics.itemWidth(for: 30) == 0)
    }

    @Test
    func selfSizingUsesNaturalWidthAndAllConfiguredRows() {
        for layout: CollectionHStackLayout in [.selfSizingSameSize(rows: 3), .selfSizingVariadicWidth(rows: 3)] {
            let metrics = LayoutMetrics(layout: layout, insets: insets, itemSpacing: 10)
            #expect(metrics.itemWidth(for: 500) == nil)
            #expect(metrics.height(for: CGSize(width: 80, height: 40)) == 152)
        }
    }

    @Test
    func invalidConfigurationAndWidthsStayFinite() {
        for value: CGFloat in [0, -1, .nan, .infinity] {
            let metrics = LayoutMetrics(layout: .grid(columns: value, rows: 0, columnTrailingInset: 0), insets: insets, itemSpacing: value)
            #expect(metrics.rows == 1)
            #expect(metrics.itemWidth(for: 500) == 450)
            #expect(metrics.itemWidth(for: value) == 0)
        }
    }

    @Test
    func naturalMeasurementIsCachedSeparatelyFromWidthProposals() {
        var cache = ItemSizeCache()
        var measurements = 0
        for _ in 0 ..< 3 {
            let size = cache.size(width: nil) {
                measurements += 1
                return CGSize(width: 81.25, height: 40)
            }
            #expect(size == CGSize(width: 81.25, height: 40))
        }
        #expect(measurements == 1)
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 25) } == CGSize(width: 100, height: 25))
    }
}

struct ItemSizeCacheTests {
    @Test
    func resizingCachesUnroundedMeasurementsByWidth() {
        var cache = ItemSizeCache()
        var measurements = 0
        for width: CGFloat in [81.25, 100, 240.5, 100, 81.25] {
            let size = cache.size(width: width) {
                measurements += 1
                return CGSize(width: width, height: width * 1.5 + 40)
            }
            #expect(size.width == width)
            #expect(abs(size.height - (width * 1.5 + 40)) < 0.0001)
        }
        #expect(measurements == 3)
    }

    @Test
    func invalidMeasurementsDoNotPoisonTheCache() {
        var cache = ItemSizeCache()
        var measurements = 0
        for height: CGFloat in [0, .nan, .infinity] {
            #expect(cache.size(width: 100) {
                measurements += 1
                return CGSize(width: 100, height: height)
            }.height == 0)
        }
        #expect(measurements == 3)
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 50) }.height == 50)
        #expect(cache.size(width: 100) { Issue.record("The measured width should be cached")
            return .zero
        }.height == 50)
        #expect(cache.size(width: 200) { CGSize(width: 200, height: 60) }.height == 60)
        cache = ItemSizeCache()
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 75) }.height == 75)
    }

    @Test
    func invalidWidthsNeverMeasureContent() {
        var cache = ItemSizeCache()
        for width: CGFloat in [0, -1, .nan, .infinity] {
            #expect(cache.size(width: width) { Issue.record("Invalid widths must not measure")
                return .zero
            } == .zero)
        }
        #expect(cache.size(width: 100) { CGSize(width: 100, height: 50) }.height == 50)
    }

    @Test
    func liveResizeKeepsOnlyRecentMeasurements() {
        var cache = ItemSizeCache()
        for width in 1 ... 1000 {
            _ = cache.size(width: CGFloat(width)) { CGSize(width: width, height: 50) }
        }
        #expect(cache.size(width: 1000) {
            Issue.record("The latest width should be cached")
            return .zero
        }.height == 50)
        var remeasured = false
        _ = cache.size(width: 1) {
            remeasured = true
            return CGSize(width: 1, height: 50)
        }
        #expect(remeasured, "A continuous resize must not retain every past width")
    }
}
