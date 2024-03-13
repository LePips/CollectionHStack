import Foundation
import SwiftUI

let colors: [Color] = [
    .pink,
    .orange,
    .yellow,
    .green,
    .blue,
    .indigo,
    .purple,
]

func colorWheel(radius: Int) -> Color {
    Color(hue: Double(radius) / 360, saturation: 1, brightness: 1)
}

extension Array {

    subscript(mod i: Int) -> Element {
        self[i % count]
    }

    func random(in range: Range<Int>) -> [Element] {
        shuffled()
            .prefix(Int.random(in: range))
            .shuffled()
    }

    mutating func rotate(by step: Int = 1) {
        append(removeFirst())
    }
}

extension EdgeInsets {

    init(horizontal: CGFloat = 0, vertical: CGFloat = 0) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}

extension View {

    @ViewBuilder
    @inlinable
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func scrollDisabledBackport(_ disabled: Bool) -> some View {
        if #available(iOS 16, *) {
            self.scrollDisabled(disabled)
        } else {
            self
        }
    }
}
