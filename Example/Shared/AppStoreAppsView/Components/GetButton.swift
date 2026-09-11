import SwiftUI

extension AppStoreAppsView {

    struct GetButton: View {
        var body: some View {
            Button {
                #if os(iOS)
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
                #endif
            } label: {
                Text("Get")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .foregroundStyle(Color.secondary)
                            .opacity(0.2)
                    }
            }
        }
    }
}
