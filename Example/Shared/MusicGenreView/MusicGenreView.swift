import CollectionHStack
import SwiftUI

struct MusicGenreView: View {

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                CollectionHStack(
                    uniqueElements: sampleAlbums.random(in: 15 ..< 21),
                    columns: 1
                ) { album in
                    Group {
                        HeroCard(album: album)
                    }
                    .exampleFocusable()
                }
                .scrollBehavior(.fullPaging)
                .insets(horizontal: 18)

                TwoRowHStack(title: "Albums")

                SingleRowHStack(title: "New Releases")

                SingleRowHStack(title: "Coming Soon")

                SingleRowHStack(title: "New Releases")

                SongsRow(title: "Best New Songs")

                SingleRowHStack(title: "Hits by Decade")

                SingleRowHStack(title: "Hits by Year")
            }
        }
        .navigationTitle("Pop")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
