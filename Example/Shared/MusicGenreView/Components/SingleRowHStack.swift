import CollectionHStack
import SwiftUI

extension MusicGenreView {
    struct SingleRowHStack: View {

        let title: String

        var body: some View {
            VStack(alignment: .leading) {
                HeaderView(title: title)
                    .padding(.leading, 18)

                CollectionHStack(
                    uniqueElements: sampleAlbums.random(in: 21 ..< 31),
                    columns: 2
                ) { album in
                    Group {
                        SquareView(album: album)
                    }
                    .exampleFocusable()
                }
                .scrollBehavior(.continuousLeadingEdge)
                .insets(horizontal: 18)
                .itemSpacing(8)
            }
        }
    }
}
