import SwiftUI

private let eventTags: [String] = [
    "happening now",
    "now available",
]

extension AppStoreAppsView {

    struct AppStoreEventRowCard: View {

        let app: SampleApp

        var body: some View {
            VStack(alignment: .leading) {

                Text(eventTags.randomElement()!.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                VStack(spacing: 0) {

                    app.color
                        .aspectRatio(1.77, contentMode: .fill)

                    HStack {
                        app.color
                            .aspectRatio(1, contentMode: .fill)
                            .cornerRadius(5)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 3) {

                            Text(app.name)

                            Text(app.firstMotto)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        GetButton()
                    }
                    .padding()
                    .background {
                        Color.secondary.opacity(0.15)
                    }
                }
                .cornerRadius(5)
            }
        }
    }
}
