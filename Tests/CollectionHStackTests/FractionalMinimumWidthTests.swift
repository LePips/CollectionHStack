@testable import CollectionHStack
import SwiftUI
import Testing

struct FractionalMinimumWidthTests {
    private let insets = EdgeInsets(top: 5, leading: 20, bottom: 7, trailing: 30)

    @Test
    func halfColumnsSwitchAtExactFitBoundariesInBothDirections() throws {
        let metrics = metrics()
        // At 180, 1.5 items fit; at 260, two full items and both insets fit.
        let cases: [(CGFloat, CGFloat)] = [
            (179.9, 129.9), (180, 100), (259.9, 229.9 / 1.5),
            (260, 100), (289.9, 114.95), (290, 100),
            (370, 100), (290, 100), (260, 100), (259.9, 229.9 / 1.5),
            (180, 100), (179.9, 129.9), (70, 20), (30, 0),
        ]
        for (width, expected) in cases {
            #expect(try abs(#require(metrics.itemWidth(for: width)) - expected) < 0.0001)
        }
    }

    @Test
    func aWidthImmediatelyBelowABreakpointDoesNotFitAnotherColumn() throws {
        let metrics = metrics()
        for boundary: CGFloat in [180, 260, 290, 370] {
            #expect(try #require(metrics.itemWidth(for: boundary.nextDown)) > 100)
            #expect(metrics.itemWidth(for: boundary) == 100)
            #expect(try #require(metrics.itemWidth(for: boundary.nextUp)) >= 100)
        }
    }

    @Test
    func decimalMinimumsAndSpacingSwitchExactlyAtTheirGeometryBoundary() throws {
        for minimum: CGFloat in [79.3, 123.4, 160.5] {
            for spacing: CGFloat in [0.1, 7.3, 10] {
                let insets = EdgeInsets(top: 0, leading: 15.5, bottom: 0, trailing: 20.2)
                let metrics = LayoutMetrics(
                    layout: .minimumWidth(columnWidth: minimum, rows: 1, columnFraction: 0.5),
                    insets: insets,
                    itemSpacing: spacing
                )
                for columns: CGFloat in [1.5, 2, 2.5, 3, 3.5, 4] {
                    let whole = floor(columns) == columns
                    let occupied = insets.leading + (whole ? insets.trailing : 0) + (whole ? columns - 1 : floor(columns)) * spacing
                    let boundary = occupied + columns * minimum
                    #expect(try abs(#require(metrics.itemWidth(for: boundary)) - minimum) < 0.0001)
                    #expect(try #require(metrics.itemWidth(for: boundary.nextDown)) > minimum + 0.1)
                    #expect(try #require(metrics.itemWidth(for: boundary.nextUp)) >= minimum)
                }
            }
        }
    }

    @Test
    func fractionalAndWholeLayoutsUseTheSameInsetsAndGapsAsGrid() throws {
        for (width, columns): (CGFloat, CGFloat) in [(200, 1.5), (270, 2), (310, 2.5)] {
            let grid = LayoutMetrics(layout: .grid(columns: columns, rows: 2, columnTrailingInset: 0), insets: insets, itemSpacing: 10)
            #expect(metrics().itemWidth(for: width) == grid.itemWidth(for: width))
        }
        // Large spacing must count the entire gap before a partially visible item.
        let wideGaps = metrics(spacing: 80)
        #expect(wideGaps.itemWidth(for: 250) == 100)
        #expect(try #require(wideGaps.itemWidth(for: 249.9)) > 100)
    }

    @Test
    func customFractionsChooseTheLargestFittingWholeOrPartialColumnCount() throws {
        for fraction: CGFloat in [0.25, 1 / 3, 0.5, 0.75] {
            for spacing: CGFloat in [0, 10, 80] {
                for trailing: CGFloat in [0, 30, 180] {
                    let insets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: trailing)
                    let metrics = LayoutMetrics(
                        layout: .minimumWidth(columnWidth: 100, rows: 1, columnFraction: fraction),
                        insets: insets,
                        itemSpacing: spacing
                    )
                    for step in 1 ... 800 {
                        let width = CGFloat(step) * 1.25
                        // Enumerate actual geometry independently of the resolver.
                        var bestColumns: CGFloat = 1
                        var expected = max(0, width - 20 - trailing)
                        for whole in 1 ... 10 {
                            for columns in [CGFloat(whole), CGFloat(whole) + fraction] {
                                let isWhole = columns == floor(columns)
                                let gaps = isWhole ? columns - 1 : floor(columns)
                                let occupied = 20 + (isWhole ? trailing : 0) + gaps * spacing
                                if columns > bestColumns, columns * 100 + occupied <= width {
                                    bestColumns = columns
                                    expected = (width - occupied) / columns
                                }
                            }
                        }
                        #expect(try abs(#require(metrics.itemWidth(for: width)) - expected) < 0.0001)
                    }
                }
            }
        }
    }

    @Test
    func halfColumnsReduceTheSizeJumpWhenTwoColumnsStopFitting() throws {
        let whole = LayoutMetrics(layout: .minimumWidth(columnWidth: 100, rows: 1), insets: .init(), itemSpacing: 10)
        let half = LayoutMetrics(layout: .minimumWidth(columnWidth: 100, rows: 1, columnFraction: 0.5), insets: .init(), itemSpacing: 10)
        #expect(whole.itemWidth(for: 210) == 100)
        #expect(half.itemWidth(for: 210) == 100)
        #expect(whole.itemWidth(for: 209) == 209)
        #expect(try abs(#require(half.itemWidth(for: 209)) - 199 / 1.5) < 0.0001)
        // Minimum-width sizing still proposes a width; it never requests natural sizing.
        #expect(try #require(half.itemWidth(for: 209)) >= 100)
    }

    @Test
    func invalidFractionsKeepExistingWholeColumnBehavior() {
        let whole = metrics(fraction: 0)
        for fraction: CGFloat in [-1, 1, 1.5, .nan, .infinity, -.infinity] {
            for width: CGFloat in [30, 70, 180, 259.9, 260, 500] {
                #expect(metrics(fraction: fraction).itemWidth(for: width) == whole.itemWidth(for: width))
            }
        }
        for width: CGFloat in [0, -1, .nan, .infinity] {
            #expect(metrics().itemWidth(for: width) == 0)
        }
    }

    @Test
    @MainActor
    func allConvenienceInitializersForwardTheFractionAndKeepTheDefault() {
        struct Item: Identifiable { let id: Int }
        let items = [Item(id: 1)]
        let expected = CollectionHStackLayout.minimumWidth(columnWidth: 100, rows: 2, columnFraction: 0.5)
        let explicit = CollectionHStack(uniqueElements: items, id: \.id, minWidth: 100, columnFraction: 0.5, rows: 2) { _ in Color.blue }
        let identifiable = CollectionHStack(uniqueElements: items, minWidth: 100, columnFraction: 0.5, rows: 2) { _ in Color.blue }
        let counted = CollectionHStack(count: 10, minWidth: 100, columnFraction: 0.5, rows: 2) { _ in Color.blue }
        #expect(explicit.layout == expected)
        #expect(identifiable.layout == expected)
        #expect(counted.layout == expected)
        let legacy = CollectionHStack(count: 10, minWidth: 100, rows: 2) { _ in Color.blue }
        #expect(legacy.layout == .minimumWidth(columnWidth: 100, rows: 2, columnFraction: 0))
        #expect(legacy.layout != expected)
    }

    private func metrics(fraction: CGFloat = 0.5, spacing: CGFloat = 10) -> LayoutMetrics {
        LayoutMetrics(layout: .minimumWidth(columnWidth: 100, rows: 2, columnFraction: fraction), insets: insets, itemSpacing: spacing)
    }
}
