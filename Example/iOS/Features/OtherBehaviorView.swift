import CollectionHStack
import SwiftUI

struct OtherBehaviorView: View {

    @Environment(\.colorScheme)
    var colorScheme

    @State
    var allowBouncing = true
    @State
    var allowScrolling = true
    @State
    var dataPrefix: Int? = nil
    @State
    var onEdgeColor = Color.blue
    @State
    var colors = (0 ..< 20).map { colorWheel(radius: $0 * 18) }

    var columnCount: Int {
        if UIDevice.current.userInterfaceIdiom == .pad {
            6
        } else {
            3
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading) {

                // carousel

                HeaderPopover(
                    title: "Carousel",
                    description: "Cells are reused and wrapped around the trailing end"
                )
                .padding(.leading, 15)

                CollectionHStack(
                    count: 72,
                    columns: columnCount
                ) { i in
                    colorWheel(radius: i * 5)
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                }
                .asCarousel()

                // On edge modifiers

                HeaderPopover(
                    title: "On edge modifiers",
                    description: "Modifiers for reaching the leading and trailing edges"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    count: 10,
                    columns: columnCount
                ) { _ in
                    OnEdgeColorView(color: $onEdgeColor)
                }
                .onReachedLeadingEdge {
                    withAnimation {
                        onEdgeColor = .blue
                    }
                }
                .onReachedTrailingEdge {
                    withAnimation {
                        onEdgeColor = .pink
                    }
                }

                // Bouncing

                HStack {
                    HeaderPopover(
                        title: "Toggle bouncing",
                        description: "Enable/disable bouncing"
                    )

                    Spacer()

                    Button {
                        allowBouncing.toggle()
                    } label: {
                        Text(allowBouncing ? "Disable" : "Enable")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 15)
                    }
                }
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: columnCount
                ) { _ in
                    Color.blue
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                }
                .allowBouncing(allowBouncing)

                // Scrolling

                HStack {
                    HeaderPopover(
                        title: "Toggle scrolling",
                        description: "Enable/disable scrolling"
                    )

                    Spacer()

                    Button {
                        allowScrolling.toggle()
                    } label: {
                        Text(allowScrolling ? "Disable" : "Enable")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 15)
                    }
                }
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: columnCount
                ) { _ in
                    Color.blue
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                }
                .scrollDisabled(!allowScrolling)

                // Clips to bounds

                HeaderPopover(
                    title: "Clips to bounds",
                    description: "Disable clipping cells along the view's bounds"
                )
                .padding(.top, 30)
                .padding(.leading, 15)

                Text("Clipped (default)")
                    .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: columnCount
                ) { _ in
                    Color.blue
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                        .shadow(
                            color: colorScheme == .light ? Color.black : Color.white,
                            radius: 10
                        )
                }

                Text("Not clipped")
                    .padding(.leading, 15)

                CollectionHStack(
                    count: 20,
                    columns: columnCount
                ) { _ in
                    Color.blue
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                        .shadow(
                            color: colorScheme == .light ? Color.black : Color.white,
                            radius: 10
                        )
                }
                .clipsToBounds(false)

                HStack {
                    HeaderPopover(
                        title: "Data Prefix",
                        description: "Enable/disable data prefixing"
                    )

                    Spacer()

                    Button {
                        colors.shuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 15)
                    }

                    Button {
                        colors.rotate()
                    } label: {
                        Image(systemName: "arrow.circlepath")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 15)
                    }

                    Button {
                        if dataPrefix == nil {
                            dataPrefix = columnCount
                        } else {
                            dataPrefix = nil
                        }
                    } label: {
                        Text("Toggle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 15)
                    }
                }
                .padding(.top, 30)
                .padding(.leading, 15)

                CollectionHStack(
                    uniqueElements: colors,
                    id: \.self,
                    columns: columnCount
                ) { color in
                    color
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .cornerRadius(5)
                }
                .dataPrefix(dataPrefix)
            }
        }
        .navigationTitle("Other")
    }
}
