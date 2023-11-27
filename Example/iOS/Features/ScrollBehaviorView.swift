import CollectionHStack
import SwiftUI

struct ScrollBehaviorView: View {

    enum ColumnOptions: String, CaseIterable {
        case oneRow = "One Row"
        case twoRows = "Two Rows"
        case variadicWidths = "Variadic Widths"
    }

    @State
    var columnOption: ColumnOptions = .oneRow

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading) {

                // continuous

                HeaderPopover(
                    title: "Continuous",
                    description: "Continuously scroll (default)"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    0 ..< 20,
                    columns: 2
                ) { _ in
                    Color.blue
                        .aspectRatio(1.77, contentMode: .fill)
                        .cornerRadius(5)
                }

                // continuous leading edge

                HStack {
                    HeaderPopover(
                        title: "Continuous Leading edge",
                        description: "Continuously scroll and align along the leading edge of the column"
                    )

                    Spacer()

                    Menu {
                        ForEach(ColumnOptions.allCases, id: \.rawValue) { option in
                            Button(option.rawValue) {
                                columnOption = option
                            }
                        }
                    } label: {
                        Text(columnOption.rawValue)
                    }
                }
                .padding(.top, 30)
                .padding(.horizontal, 15)

                if columnOption == .variadicWidths {
                    CollectionHStack(
                        0 ..< 40,
                        rows: 2,
                        variadicWidths: true
                    ) { i in
                        Color.blue
                            .cornerRadius(5)
                            .frame(width: CGFloat(i % 4 + 1) * 50, height: 100)
                    }
                    .scrollBehavior(.continuousLeadingEdge)
                    .id(columnOption)
                } else {
                    CollectionHStack(
                        0 ..< 20,
                        columns: 2.5,
                        rows: columnOption == .oneRow ? 1 : 2
                    ) { _ in
                        Color.blue
                            .aspectRatio(1.77, contentMode: .fill)
                            .cornerRadius(5)
                    }
                    .scrollBehavior(.continuousLeadingEdge)
                    .id(columnOption)
                }

                // column paging

                HeaderPopover(
                    title: "Column Paging",
                    description: "Page along items"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    0 ..< 20,
                    columns: 2.5
                ) { _ in
                    Color.blue
                        .aspectRatio(1.77, contentMode: .fill)
                        .cornerRadius(5)
                }
                .scrollBehavior(.columnPaging)

                // full paging

                HeaderPopover(
                    title: "Full Paging",
                    description: "Page along the full width of the view. Best used with whole numbered column layouts"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    0 ..< 20,
                    columns: 2
                ) { _ in
                    Color.blue
                        .aspectRatio(1.77, contentMode: .fill)
                        .cornerRadius(5)
                }
                .scrollBehavior(.fullPaging)
            }
        }
        .navigationTitle("Scroll Behavior")
    }
}
