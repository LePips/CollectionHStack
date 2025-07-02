import CollectionHStack
import SwiftUI

extension AppStoreAppsView {

    struct AppCategoryRow: View {

        var body: some View {
            VStack(alignment: .leading) {

                Text("Top Categories")
                    .font(.title3)
                    .fontWeight(.bold)

                CollectionHStack(
                    count: 4,
                    columns: 1,
                    rows: 4
                ) { i in
                    VStack(alignment: .leading, spacing: 0) {
                        switch i {
                        case 0:
                            HStack(spacing: 20) {
                                Image(systemName: "graduationcap.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30)

                                Text("Education")
                                    .font(.title3)
                            }
                            .frame(height: 40)
                        case 1:
                            HStack(spacing: 20) {
                                Image(systemName: "figure.run")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                    .frame(width: 30)

                                Text("Health & Fitness")
                                    .font(.title3)
                            }
                            .frame(height: 40)
                        case 2:
                            HStack(spacing: 20) {
                                Image(systemName: "balloon.2.fill")
                                    .font(.title2)
                                    .foregroundStyle(.pink, .purple)
                                    .frame(width: 30)

                                Text("Kids")
                                    .font(.title3)
                            }
                            .frame(height: 40)
                        case 3:
                            HStack(spacing: 20) {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30)

                                Text("Photo & Video")
                                    .font(.title3)
                            }
                            .frame(height: 40)
                        default:
                            EmptyView()
                        }

                        LineDivider()
                            .padding(.leading, 48)
                    }
                }
                .scrollDisabled(true)
            }
        }
    }
}
