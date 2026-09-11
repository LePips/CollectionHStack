import CollectionHStack
import SwiftUI

extension AppStoreAppsView {
    struct ThreeAppRowView: View {

        let title: String
        let apps: [SampleApp]

        var body: some View {
            VStack(alignment: .leading) {

                LineDivider()
                    .padding(.horizontal, 18)

                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.leading, 18)

                CollectionHStack(
                    uniqueElements: apps,
                    columns: 1,
                    rows: 3
                ) { app in
                    Group {
                        AppItem(app: app)
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
