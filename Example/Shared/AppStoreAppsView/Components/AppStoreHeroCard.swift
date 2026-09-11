import SwiftUI

private let heroCardTags: [String] = [
    "now available",
    "our favorites",
    "featured",
    "happening now",
    "now on ipad",
    "limited time",
    "see update",
    "major update",
]

extension AppStoreAppsView {
    struct HeroCard: View {

        let app: SampleApp

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(heroCardTags.randomElement()!.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                Text(app.name)
                    .font(.title2)
                    .lineLimit(1)

                Text(app.firstMotto)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.bottom, 5)

                ZStack(alignment: .bottom) {
                    Color.secondary
                        .opacity(0.3)
                        .aspectRatio(1.77, contentMode: .fill)
                        .cornerRadius(5)

                    HStack {
                        app.color
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .cornerRadius(5)

                        VStack(alignment: .leading, spacing: 2) {

                            Text(app.name)
                                .font(.callout)

                            Text(app.secondMotto)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        GetButton()
                    }
                    .padding(15)
                }
            }
        }
    }
}
