#if os(tvOS)
import CollectionHStack
import SwiftUI

struct FocusBehaviorView: View {
    @State private var presentation = UUID()
    @State private var selection = "Select any card"
    @StateObject private var focusProbe = FocusExampleProbe()

    var body: some View {
        CollectionHStackFocusScope {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("Move down from different columns, move sideways in a row, then leave and return.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 40) {
                        ForEach(1 ... 4, id: \.self) { column in
                            Button("Start above column \(column)") {}
                                .accessibilityIdentifier("anchor-\(column)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 50)

                    VStack(spacing: 36) {
                        focusRow("Leading first · Remember on return", row: 0, initial: .leading, returning: .lastFocused)
                        focusRow("Best aligned first · Remember on return", row: 1, initial: .automatic, returning: .lastFocused)
                        focusRow("Leading on every entry", row: 2, initial: .leading, returning: .leading)
                    }
                    .id(presentation)

                    HStack {
                        Button("Reset focus history") {
                            presentation = UUID()
                            selection = "Focus history reset"
                        }
                        Text(selection)
                            .accessibilityIdentifier("selection-status")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if focusProbe.enabled {
                        Text("Focus events")
                            .accessibilityIdentifier("focus-events")
                            .accessibilityValue(focusProbe.events.joined(separator: ","))
                            .font(.caption)
                    }
                }
                .padding(.vertical, 36)
            }
        }
        .navigationTitle("Focus Behavior")
    }

    private func focusRow(
        _ title: String,
        row: Int,
        initial: CollectionHStackFocusBehavior.Initial,
        returning: CollectionHStackFocusBehavior.Returning
    ) -> some View {
        ExampleSection(title) {
            CollectionHStack(count: 20, columns: 4) { index in
                Button {
                    selection = "\(title): item \(index + 1)"
                } label: {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colors[index % colors.count].gradient)
                        .frame(height: 110)
                        .overlay {
                            Text("Item \(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.card)
                .accessibilityIdentifier("row\(row)-item\(index)")
            }
            .scrollBehavior(.continuousLeadingEdge)
            .focusBehavior(initial: initial, returning: returning)
            .padding(.vertical, 12)
        }
    }
}
#endif
