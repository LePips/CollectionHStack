import SwiftUI

extension MusicGenreView {
    struct SquareView: View {

        let album: SampleAlbum

        var body: some View {
            VStack(alignment: .leading) {
                album.color
                    .opacity(0.5)
                    .aspectRatio(1, contentMode: .fill)
                    .cornerRadius(5)

                Text(album.album)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(album.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
