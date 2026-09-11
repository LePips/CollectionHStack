import SwiftUI

private let heroCardTags: [String] = [
    "new album",
    "featured playlist",
    "new single just added",
    "essential album",
    "just updated",
    "listen now",
    "updated playlist",
    "new music",
    "special announcement",
    "radio station",
    "only on apple music",
]

extension MusicGenreView {
    struct HeroCard: View {

        let album: SampleAlbum

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(heroCardTags.randomElement()!.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(album.album)
                    .font(.title)
                    .lineLimit(1)

                album.color
                    .opacity(0.5)
                    .aspectRatio(1.77, contentMode: .fill)
                    .cornerRadius(8)
            }
        }
    }
}
