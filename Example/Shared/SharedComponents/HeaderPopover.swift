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
        #if os(tvOS)
        .sheet(isPresented: $isPopoverPresented) {
            VStack(spacing: 30) {
                Text(title).font(.title)
                Text(description)
                Button("Done") { isPopoverPresented = false }
            }
            .padding()
        }
        #else
        .popover(isPresented: $isPopoverPresented) {
            Text(description)
                .padding()
                .frame(maxWidth: 300)
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
        }
        #endif
    }
}
