import SwiftUI

struct ExampleWidthControl: View {
    @Binding var value: CGFloat
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        #if os(tvOS)
        Picker("Minimum item width", selection: $value) {
            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { width in
                Text("\(width) pt").tag(CGFloat(width))
            }
        }
        #else
        Slider(value: $value, in: CGFloat(range.lowerBound) ... CGFloat(range.upperBound), step: CGFloat(step))
            .accessibilityLabel("Minimum item width")
        #endif
    }
}
