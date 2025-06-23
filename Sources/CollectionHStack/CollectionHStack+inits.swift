import Foundation
import SwiftUI

// TODO: on tvOS, focus updates cause reconstructions of the non-binding init sets
// TODO: inits with (Element, Index) -> any View

// MARK: - Collection

public extension CollectionHStack {

    // columns
    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        columns: Int,
        rows: Int = 1,
        columnTrailingInset: CGFloat = 0,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            layout: .grid(columns: CGFloat(columns), rows: rows, columnTrailingInset: columnTrailingInset),
            viewProvider: content
        )
    }

    // fractional columns
    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        columns: CGFloat,
        rows: Int = 1,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            layout: .grid(columns: columns, rows: rows, columnTrailingInset: 0),
            viewProvider: content
        )
    }

    // minWidth
    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        minWidth: CGFloat,
        rows: Int = 1,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            layout: .minimumWidth(columnWidth: minWidth, rows: rows),
            viewProvider: content
        )
    }

    // self/variadic sizing
    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        rows: Int = 1,
        variadicWidths: Bool = false,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            layout: variadicWidths ? .selfSizingVariadicWidth(rows: rows) : .selfSizingSameSize(rows: rows),
            viewProvider: content
        )
    }

    init(
        uniqueElements: Data,
        id: KeyPath<Element, ID>,
        layout: CollectionHStackLayout,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: id,
            data: uniqueElements,
            layout: layout,
            viewProvider: content
        )
    }
}

public extension CollectionHStack where Element: Identifiable, ID == Element.ID {

    // columns
    init(
        uniqueElements: Data,
        columns: Int,
        rows: Int = 1,
        columnTrailingInset: CGFloat = 0,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            layout: .grid(columns: CGFloat(columns), rows: rows, columnTrailingInset: columnTrailingInset),
            viewProvider: content
        )
    }

    // fractional columns
    init(
        uniqueElements: Data,
        columns: CGFloat,
        rows: Int = 1,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            layout: .grid(columns: columns, rows: rows, columnTrailingInset: 0),
            viewProvider: content
        )
    }

    // minWidth
    init(
        uniqueElements: Data,
        minWidth: CGFloat,
        rows: Int = 1,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            layout: .minimumWidth(columnWidth: minWidth, rows: rows),
            viewProvider: content
        )
    }

    // self/variadic sizing
    init(
        uniqueElements: Data,
        rows: Int = 1,
        variadicWidths: Bool = false,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            layout: variadicWidths ? .selfSizingVariadicWidth(rows: rows) : .selfSizingSameSize(rows: rows),
            viewProvider: content
        )
    }

    init(
        uniqueElements: Data,
        layout: CollectionHStackLayout,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.id,
            data: uniqueElements,
            layout: layout,
            viewProvider: content
        )
    }
}

// MARK: Count

public extension CollectionHStack where Data == [Element], Element == Int, ID == Int {

    // columns
    init(
        count: Int,
        columns: Int,
        rows: Int = 1,
        columnTrailingInset: CGFloat = 0,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.self,
            data: Array(0 ..< count),
            layout: .grid(
                columns: CGFloat(columns),
                rows: rows,
                columnTrailingInset: columnTrailingInset
            ),
            viewProvider: content
        )
    }

    // fractional columns
    init(
        count: Int,
        columns: CGFloat,
        rows: Int = 1,
        columnTrailingInset: CGFloat = 0,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.self,
            data: Array(0 ..< count),
            layout: .grid(
                columns: columns,
                rows: rows,
                columnTrailingInset: columnTrailingInset
            ),
            viewProvider: content
        )
    }

    // minWidth
    init(
        count: Int,
        minWidth: CGFloat,
        rows: Int = 1,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.self,
            data: Array(0 ..< count),
            layout: .minimumWidth(columnWidth: minWidth, rows: rows),
            viewProvider: content
        )
    }

    // self/variadic sizing
    init(
        count: Int,
        rows: Int = 1,
        variadicWidths: Bool = false,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.self,
            data: Array(0 ..< count),
            layout: variadicWidths ? .selfSizingVariadicWidth(rows: rows) : .selfSizingSameSize(rows: rows),
            viewProvider: content
        )
    }

    init(
        uniqueElements: Data,
        layout: CollectionHStackLayout,
        @ViewBuilder content: @escaping (Element) -> any View
    ) {
        self.init(
            id: \.self,
            data: uniqueElements,
            layout: layout,
            viewProvider: content
        )
    }
}
