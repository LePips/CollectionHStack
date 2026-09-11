import CollectionHStack
import SwiftUI

struct PlaygroundView: View {
    @State private var showsControls = false
    @State private var columns = usesCompactExampleLayout ? 3 : 5
    @State private var rows = 1
    @State private var itemCount = 100
    @State private var behavior: CollectionHStackScrollBehavior = .continuousLeadingEdge
    @State private var carousel = false
    @State private var minimumWidth: CGFloat = 140
    @StateObject private var proxy = CollectionHStackProxy()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ExampleSection("Columns and rows") {
                        mainCollection
                            .padding(.vertical, 8)
                    }

                    ExampleSection("Minimum width") {
                        VStack {
                            CollectionHStack(count: 100, minWidth: minimumWidth) { index in
                                card(index)
                                    .aspectRatio(1.6, contentMode: .fill)
                            }

                            HStack {
                                ExampleWidthControl(value: $minimumWidth, range: 80 ... 240, step: 10)
                                Text("\(Int(minimumWidth)) pt")
                                    .monospacedDigit()
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                        }
                        .padding(.vertical, 8)
                    }

                    ExampleSection("Variable widths") {
                        CollectionHStack(count: 100, variadicWidths: true) { index in
                            card(index)
                                .frame(width: CGFloat(index % 4 + 1) * 60, height: 100)
                        }
                        .scrollBehavior(.continuousLeadingEdge)
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Playground")
        .toolbar {
            ToolbarItemGroup {
                Button("Controls", systemImage: "slider.horizontal.3") {
                    showsControls = true
                }
                Button("First item", systemImage: "backward.end") {
                    proxy.scrollTo(index: 0)
                }
                Button("Last item", systemImage: "forward.end") {
                    proxy.scrollTo(index: itemCount - 1)
                }
            }
        }
        .sheet(isPresented: $showsControls) {
            NavigationStack {
                controls
                    .navigationTitle("Collection controls")
                    .toolbar {
                        Button("Done") { showsControls = false }
                    }
            }
        }
    }

    @ViewBuilder
    private var mainCollection: some View {
        let collection = CollectionHStack(count: itemCount, columns: columns, rows: rows) { index in
            card(index)
                .aspectRatio(1.6, contentMode: .fill)
        }
        .scrollBehavior(behavior)
        .proxy(proxy)

        if carousel {
            collection.asCarousel()
        } else {
            collection
        }
    }

    private var controls: some View {
        Form {
            Section("Layout") {
                Picker("Columns", selection: $columns) {
                    ForEach(1 ... 8, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Rows", selection: $rows) {
                    ForEach(1 ... 4, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Items", selection: $itemCount) {
                    Text("100").tag(100)
                    Text("1,000").tag(1000)
                    Text("10,000").tag(10000)
                }
            }
            Section("Scrolling") {
                Picker("Behavior", selection: $behavior) {
                    Text("Continuous").tag(CollectionHStackScrollBehavior.continuous)
                    Text("Leading edge").tag(CollectionHStackScrollBehavior.continuousLeadingEdge)
                    Text("Column paging").tag(CollectionHStackScrollBehavior.columnPaging)
                    Text("Full paging").tag(CollectionHStackScrollBehavior.fullPaging)
                }
                Toggle("Carousel", isOn: $carousel)
            }
        }
    }

    private func card(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(hue: Double(index % 72) / 72, saturation: 0.7, brightness: 0.75))
            .overlay {
                Text("Item \(index + 1)")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .exampleFocusable()
    }
}

#Preview {
    PlaygroundView()
        .frame(width: 960, height: 720)
}
