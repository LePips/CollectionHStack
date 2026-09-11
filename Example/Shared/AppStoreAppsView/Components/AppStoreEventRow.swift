import CollectionHStack
import SwiftUI

extension AppStoreAppsView {

    struct AppStoreEventRow: View {

        let apps: [SampleApp]

        var body: some View {
            VStack(alignment: .leading) {

                Text("Events You Might Like")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.leading, 18)

                CollectionHStack(
                    uniqueElements: apps,
                    columns: 1
                ) { app in
                    Group {
                        AppStoreEventRowCard(app: app)
                    }
                    .exampleFocusable()
                }
                .scrollBehavior(.fullPaging)
                .insets(horizontal: 18)
                .itemSpacing(8)
            }
        }
    }
}
