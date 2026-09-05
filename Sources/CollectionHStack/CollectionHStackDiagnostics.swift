import Foundation

#if canImport(Broadcast)
import Broadcast
#else
import OSLog
#endif

#if canImport(Broadcast)
/// Broadcast destinations used by `CollectionHStack` when no custom trace is supplied.
public enum CollectionHStackDiagnostics {

    /// In-memory records captured during the current process.
    ///
    /// Use `records()` for semantic records or `logs()` for a support-friendly export.
    public static let sessionLogger = SessionLogger()

    /// The default trace, which writes structured records to OSLog and ``sessionLogger``.
    public static let log = Log(
        destinations: [
            ConsoleLogger(subsystem: "com.CollectionHStack", category: "Diagnostics"),
            sessionLogger,
        ]
    )
}
#endif

struct CollectionHStackTrace {

    enum Level {
        case debug
        case info
        case warn
    }

    enum Signal {
        case action
        case state
        case event
        case metric
        case diagnostic
    }

    struct Category {
        let identifier: String

        static let collectionHStack = Self(identifier: "CollectionHStack")
        static let collectionHStackData = Self(identifier: "CollectionHStack Data")
        static let collectionHStackLayout = Self(identifier: "CollectionHStack Layout")
        static let collectionHStackPrefetch = Self(identifier: "CollectionHStack Prefetch")
        static let collectionHStackScrolling = Self(identifier: "CollectionHStack Scrolling")
    }

    enum Payload {
        case string(String, String?)
        case bool(String, Bool)
        case int(String, Int)

        static func count(_ count: Int) -> Self {
            .int("count", count)
        }

        static func collectionItemCount(_ count: Int) -> Self {
            .int("itemCount", count)
        }

        static func collectionLayout(_ layout: CollectionHStackLayout) -> Self {
            .string("layout", layout.logIdentifier)
        }

        static func collectionScrollBehavior(_ behavior: CollectionHStackScrollBehavior) -> Self {
            .string("scrollBehavior", behavior.logIdentifier)
        }

        static func collectionDimension(_ key: String, _ value: CGFloat) -> Self {
            .string(key, String(describing: value))
        }
    }

    #if canImport(Broadcast)
    let log: Log

    static let `default` = Self(log: CollectionHStackDiagnostics.log)
    static let disabled = Self(log: Log(destinations: []))

    init(log: Log) {
        self.log = log
    }
    #else
    private let logger: Logger

    static let `default` = Self()
    static let disabled = Self(logger: Logger(.disabled))

    private init(logger: Logger = Logger(subsystem: "com.CollectionHStack", category: "Diagnostics")) {
        self.logger = logger
    }
    #endif

    func debug(
        _ signal: Signal,
        _ message: String,
        category: Category,
        payload: [Payload] = []
    ) {
        record(.debug, signal, message, category: category, payload: payload)
    }

    func info(
        _ signal: Signal,
        _ message: String,
        category: Category,
        payload: [Payload] = []
    ) {
        record(.info, signal, message, category: category, payload: payload)
    }

    func warn(
        _ signal: Signal,
        _ message: String,
        category: Category,
        payload: [Payload] = []
    ) {
        record(.warn, signal, message, category: category, payload: payload)
    }

    private func record(
        _ level: Level,
        _ signal: Signal,
        _ message: String,
        category: Category,
        payload: [Payload]
    ) {
        #if canImport(Broadcast)
        let broadcastPayload = payload.map(\.broadcastPayload)
        let broadcastCategory = Log.Category(identifier: category.identifier)

        switch level {
        case .debug:
            log.debug(signal.broadcastSignal, message, category: broadcastCategory, payload: broadcastPayload)
        case .info:
            log.info(signal.broadcastSignal, message, category: broadcastCategory, payload: broadcastPayload)
        case .warn:
            log.warn(signal.broadcastSignal, message, category: broadcastCategory, payload: broadcastPayload)
        }
        #else
        let payloadText = payload.map(\.fallbackDescription).joined(separator: ", ")
        let text = payloadText.isEmpty
            ? "[\(signal.description) | \(category.identifier)] \(message)"
            : "[\(signal.description) | \(category.identifier)] \(message) | payload=[\(payloadText)]"

        switch level {
        case .debug:
            logger.debug("\(text, privacy: .public)")
        case .info:
            logger.info("\(text, privacy: .public)")
        case .warn:
            logger.warning("\(text, privacy: .public)")
        }
        #endif
    }
}

#if canImport(Broadcast)
private extension CollectionHStackTrace.Signal {
    var broadcastSignal: Log.Signal {
        switch self {
        case .action: .action
        case .state: .state
        case .event: .event
        case .metric: .metric
        case .diagnostic: .diagnostic
        }
    }
}

private extension CollectionHStackTrace.Payload {
    var broadcastPayload: Log.Payload {
        switch self {
        case let .string(key, value): .string(key, value)
        case let .bool(key, value): .bool(key, value)
        case let .int(key, value): .int(key, value)
        }
    }
}
#else
private extension CollectionHStackTrace.Signal {
    var description: String {
        switch self {
        case .action: "Action"
        case .state: "State"
        case .event: "Event"
        case .metric: "Metric"
        case .diagnostic: "Diagnostic"
        }
    }
}

private extension CollectionHStackTrace.Payload {
    var fallbackDescription: String {
        switch self {
        case let .string(key, value): "\(key)=\(value ?? "nil")"
        case let .bool(key, value): "\(key)=\(value)"
        case let .int(key, value): "\(key)=\(value)"
        }
    }
}
#endif

extension CollectionHStackLayout {
    var logIdentifier: String {
        switch self {
        case let .grid(columns, rows, trailingInset):
            "Grid(columns: \(columns), rows: \(rows), trailingInset: \(trailingInset))"
        case let .minimumWidth(columnWidth, rows):
            "MinimumWidth(width: \(columnWidth), rows: \(rows))"
        case let .selfSizingSameSize(rows):
            "SelfSizingSameSize(rows: \(rows))"
        case let .selfSizingVariadicWidth(rows):
            "SelfSizingVariadicWidth(rows: \(rows))"
        }
    }
}

extension CollectionHStackScrollBehavior {
    var logIdentifier: String {
        switch self {
        case .columnPaging:
            "ColumnPaging"
        case .continuous:
            "Continuous"
        case .continuousLeadingEdge:
            "ContinuousLeadingEdge"
        case .fullPaging:
            "FullPaging"
        }
    }
}
