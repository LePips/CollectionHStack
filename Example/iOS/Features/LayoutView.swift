import CollectionHStack
import SwiftUI

struct LayoutView: View {

    @State
    var minWidth: CGFloat = 120

    @StateObject
    var proxy: CollectionHStackProxy = .init()

    var columnCount: Int {
        if UIDevice.current.userInterfaceIdiom == .pad {
            6
        } else {
            3
        }
    }

    var fractionalColumnCount: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
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
                    Color.blue
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                }

                // minwidth

                HStack {
                    HeaderPopover(
                        title: "Minimum Width",
                        description: "Each column must have the given minimum width"
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
                            minWidth: minWidth
                        ) { _ in
                            Color.blue
                                .aspectRatio(1.77, contentMode: .fill)
                                .cornerRadius(5)
                        }
                    }
                    .scrollDisabledBackport(true)
                    .frame(height: 150)
                }

                Slider(value: $minWidth, in: 70 ... 150, step: 2)
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
                    Color.blue
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
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
                    HStack(spacing: 0) {
                        Color.blue

                        Color.pink
                    }
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .cornerRadius(5)
                }

                // self sizing

                HeaderPopover(
                    title: "Self Sizing",
                    description: "Views can be self sizing but must be the same size"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(count: 20) { _ in
                    Color.blue
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .frame(height: 200)
                        .cornerRadius(5)
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
                    colors[mod: i]
                        .frame(width: 50 * (CGFloat(i % 3) + 1), height: 200)
                        .cornerRadius(5)
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
                    Color.blue
                        .aspectRatio(1, contentMode: .fill)
                        .cornerRadius(5)
                }
            }
        }
        .navigationTitle("Layout")
    }
}
