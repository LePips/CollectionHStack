import SwiftUI

extension MusicGenreView {
    struct HeaderView: View {

        let title: String

        var body: some View {
            HStack(spacing: 2) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }
}
