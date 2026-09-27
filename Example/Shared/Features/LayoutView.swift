import CollectionHStack
import SwiftUI

struct LayoutView: View {

    @State
    var minWidth: CGFloat = 120

    @State
    var columnFraction: CGFloat = 0.5

    @StateObject
    var proxy: CollectionHStackProxy = .init()

    var columnCount: Int {
        if !usesCompactExampleLayout {
            6
        } else {
            3
        }
    }

    var fractionalColumnCount: CGFloat {
        if !usesCompactExampleLayout {
            5.5
        } else {
            3.5
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading) {

                // columns

                HeaderPopover(
                    title: "Columns",
                    description: "\(columnCount) columns"
                )
                .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: columnCount
                ) { _ in
                    Group {
                        Color.blue
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .cornerRadius(5)
                    }
                    .exampleFocusable()
                }

                // minwidth

                HStack {
                    HeaderPopover(
                        title: "Minimum Width",
                        description: "Fit as many whole or partial columns as possible at the minimum width. Half columns reduce item-size changes as the window resizes. A narrower container fits one item."
                    )

                    Spacer()

                    Text("\(minWidth, format: .number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 15)
                }
                .padding(.top, 30)
                .padding(.leading, 15)

                ZStack {
                    ScrollView {
                        CollectionHStack(
                            count: 20,
                            minWidth: minWidth,
                            columnFraction: columnFraction
                        ) { _ in
                            Group {
                                Color.blue
                                    .aspectRatio(1.77, contentMode: .fill)
                                    .cornerRadius(5)
                            }
                            .exampleFocusable()
                        }
                    }
                    .scrollDisabled(true)
                    .frame(height: 150)
                }

                ExampleWidthControl(value: $minWidth, range: 70 ... 150, step: 2)
                    .padding(.horizontal, 15)

                Picker("Partial column", selection: $columnFraction) {
                    Text("Whole only").tag(CGFloat(0))
                    Text("Half").tag(CGFloat(0.5))
                    Text("Quarter").tag(CGFloat(0.25))
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 15)

                // column trailing inset

                HeaderPopover(
                    title: "Column Trailing Inset",
                    description: "Size columns after subtracting an inset from the trailing side. 3 columns, 60 column trailing inset"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: columnCount,
                    columnTrailingInset: 60
                ) { _ in
                    Group {
                        Color.blue
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .cornerRadius(5)
                    }
                    .exampleFocusable()
                }

                // fractional columns

                HeaderPopover(
                    title: "Fractional Columns",
                    description: "Columns can be determined fractionally"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: fractionalColumnCount
                ) { _ in
                    Group {
                        HStack(spacing: 0) {
                            Color.blue

                            Color.pink
                        }
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                    }
                    .exampleFocusable()
                }

                // self sizing

                HeaderPopover(
                    title: "Self Sizing",
                    description: "Views can be self sizing but must be the same size"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(count: 20) { _ in
                    Group {
                        Color.blue
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .frame(height: 200)
                            .cornerRadius(5)
                    }
                    .exampleFocusable()
                }

                // variadic widths

                HeaderPopover(
                    title: "Variadic Widths",
                    description: "Views can have different widths but must be the same height"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    variadicWidths: true
                ) { i in
                    Group {
                        colors[mod: i]
                            .frame(width: 50 * (CGFloat(i % 3) + 1), height: 200)
                            .cornerRadius(5)
                    }
                    .exampleFocusable()
                }

                // rows

                HeaderPopover(
                    title: "Rows",
                    description: "4 columns, 4 rows"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: 4,
                    rows: 4
                ) { _ in
                    Group {
                        Color.blue
                            .aspectRatio(1, contentMode: .fill)
                            .cornerRadius(5)
                    }
                    .exampleFocusable()
                }
            }
        }
        .navigationTitle("Layout")
    }
}
