import SwiftUI

struct HeaderPopover: View {

    @State
    private var isPopoverPresented = false

    let title: String
    let description: String

    var body: some View {
        Button {
            isPopoverPresented = true
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented) {
            Text(description)
                .padding()
                .frame(maxWidth: 300)
                .presentationCompactAdaptation(.popover)
        }
    }
}
