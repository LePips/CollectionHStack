import SwiftUI

extension AppStoreAppsView {
    struct AppItem: View {

        let app: SampleApp

        var body: some View {
            HStack {

                app.color
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 60)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 3) {

                    Text(app.name)

                    Text(app.firstMotto)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                GetButton()
                    .padding(.horizontal, 5)
            }
        }
    }
}
