import CollectionHStack
import SwiftUI

struct CarouselView: View {

    let colors: [Color] = [
        .blue,
        .green,
        .yellow,
        .red,
        .orange,
        .purple,
        .pink,
        .cyan,
        .indigo,
        .mint,
        .teal,
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 50) {

                Spacer(minLength: 50)

                CollectionHStack(
                    count: 10,
                    columns: 1
                ) { _ in
                    Button {} label: {
                        colors.randomElement()!
                            .aspectRatio(3, contentMode: .fill)
                    }
                    .exampleCardButtonStyle()
                }
                .asCarousel()
                .scrollBehavior(.fullPaging)

                CollectionHStack(
                    count: 72,
                    columns: usesCompactExampleLayout ? 3 : 6
                ) { i in
                    Button {} label: {
                        Color(hue: Double(i * 5) / 360, saturation: 1, brightness: 1)
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .cornerRadius(5)
                    }
                    .exampleCardButtonStyle()
                }
                .asCarousel()
                .scrollBehavior(.continuousLeadingEdge)

                CollectionHStack(
                    count: 30,
                    columns: usesCompactExampleLayout ? 3 : 6
                ) { _ in
                    Button {} label: {
                        colors.randomElement()!
                            .aspectRatio(2 / 3, contentMode: .fill)
                    }
                    .exampleCardButtonStyle()
                }
                .scrollBehavior(.continuousLeadingEdge)

                CollectionHStack(
                    count: 30,
                    columns: usesCompactExampleLayout ? 3 : 6
                ) { _ in
                    Button {} label: {
                        colors.randomElement()!
                            .aspectRatio(2 / 3, contentMode: .fill)
                    }
                    .exampleCardButtonStyle()
                }
                .scrollBehavior(.continuousLeadingEdge)

                CollectionHStack(
                    count: 30,
                    columns: usesCompactExampleLayout ? 3 : 6
                ) { _ in
                    Button {} label: {
                        colors.randomElement()!
                            .aspectRatio(2 / 3, contentMode: .fill)
                    }
                    .exampleCardButtonStyle()
                }
                .scrollBehavior(.continuousLeadingEdge)

                Spacer(minLength: 50)
            }
        }
        .navigationTitle("Carousels")
    }
}
