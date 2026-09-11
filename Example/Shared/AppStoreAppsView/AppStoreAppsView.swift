import CollectionHStack
import SwiftUI

struct AppStoreAppsView: View {

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {

                CollectionHStack(
                    uniqueElements: sampleApps.shuffled().prefix(20).shuffled(),
                    columns: 1
                ) { app in
                    Group {
                        HeroCard(app: app)
                    }
                    .exampleFocusable()
                }
                .scrollBehavior(.fullPaging)
                .insets(horizontal: 18)
                .itemSpacing(8)

                ThreeAppRowView(
                    title: "Popular Apps",
                    apps: sampleApps.random(in: 21 ..< 31)
                )

                ThreeAppRowView(
                    title: "Must-Have Apps",
                    apps: sampleApps.random(in: 21 ..< 31)
                )

                ThreeAppRowView(
                    title: "Incredible iPhone Apps",
                    apps: sampleApps.random(in: 21 ..< 31)
                )

                ThreeAppRowView(
                    title: "Top Free Apps",
                    apps: sampleApps.random(in: 21 ..< 31)
                )

                ThreeAppRowView(
                    title: "The Best Nature Apps",
                    apps: sampleApps.random(in: 21 ..< 31)
                )

                AppStoreEventRow(apps: sampleApps.random(in: 21 ..< 31))

                ThreeAppRowView(
                    title: "Apps You Might've Missed",
                    apps: sampleApps.random(in: 21 ..< 31)
                )

                ThreeAppRowView(
                    title: "Achieve Your Fitness Goals",
                    apps: sampleApps.random(in: 21 ..< 31)
                )

                AppCategoryRow()
                    .padding(.horizontal, 18)
            }
        }
        .navigationTitle("Apps")
    }
}
