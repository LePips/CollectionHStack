import CollectionHStack
import SwiftUI

extension MusicGenreView {
    struct TwoRowHStack: View {

        let title: String

        var body: some View {
            VStack(alignment: .leading) {
                HeaderView(title: title)
                    .padding(.leading, 18)

                CollectionHStack(
                    uniqueElements: sampleAlbums.random(in: 25 ..< 35),
                    columns: 2,
                    rows: 2
                ) { album in
                    Group {
                        SquareView(album: album)
                    }
                    .exampleFocusable()
                }
                .scrollBehavior(.fullPaging)
                .insets(.init(horizontal: 18))
                .itemSpacing(8)
            }
        }
    }
}
