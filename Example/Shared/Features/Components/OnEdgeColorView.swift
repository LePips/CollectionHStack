import SwiftUI

struct OnEdgeColorView: View {

    @Binding
    var color: Color

    var body: some View {
        color
            .aspectRatio(2 / 3, contentMode: .fill)
            .cornerRadius(5)
    }
}
