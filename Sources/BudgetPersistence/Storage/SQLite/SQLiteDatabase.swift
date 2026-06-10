import Foundation
import SQLite3

public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            throw SQLiteError.open(message: SQLiteDatabase.message(for: handle))
        }

        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(handle)
    }

    public func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? SQLiteDatabase.message(for: handle)
            sqlite3_free(error)
            throw SQLiteError.execute(message: message)
        }
    }

    public func run(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: SQLiteDatabase.message(for: handle))
        }
    }

    public func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }

        var rows: [[String: SQLiteValue]] = []

        while true {
            let result = sqlite3_step(statement)

            if result == SQLITE_DONE {
                return rows
            }

            guard result == SQLITE_ROW else {
                throw SQLiteError.step(message: SQLiteDatabase.message(for: handle))
            }

            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = SQLiteValue(statement: statement, index: index)
            }
            rows.append(row)
        }
    }

    private func prepare(_ sql: String, bindings: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(message: SQLiteDatabase.message(for: handle))
        }

        for (index, value) in bindings.enumerated() {
            try bind(value, to: Int32(index + 1), in: statement)
        }

        return statement
    }

    private func bind(_ value: SQLiteValue, to index: Int32, in statement: OpaquePointer?) throws {
        let result: Int32

        switch value {
        case .null:
            result = sqlite3_bind_null(statement, index)
        case let .integer(value):
            result = sqlite3_bind_int64(statement, index, value)
        case let .text(value):
            result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case let .bool(value):
            result = sqlite3_bind_int64(statement, index, value ? 1 : 0)
        }

        guard result == SQLITE_OK else {
            throw SQLiteError.bind(message: SQLiteDatabase.message(for: handle))
        }
    }

    private static func message(for handle: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(handle) else {
            return "Unknown SQLite error"
        }

        return String(cString: message)
    }
}

public enum SQLiteValue: Hashable {
    case null
    case integer(Int64)
    case text(String)
    case bool(Bool)

    init(statement: OpaquePointer?, index: Int32) {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            self = .integer(sqlite3_column_int64(statement, index))
        case SQLITE_TEXT:
            self = .text(String(cString: sqlite3_column_text(statement, index)))
        case SQLITE_NULL:
            self = .null
        default:
            self = .text(String(cString: sqlite3_column_text(statement, index)))
        }
    }

    var string: String? {
        if case let .text(value) = self {
            return value
        }

        return nil
    }

    var int64: Int64? {
        if case let .integer(value) = self {
            return value
        }

        return nil
    }

    var bool: Bool? {
        if case let .integer(value) = self {
            return value != 0
        }

        if case let .bool(value) = self {
            return value
        }

        return nil
    }
}

public enum SQLiteError: Error, LocalizedError {
    case open(message: String)
    case prepare(message: String)
    case bind(message: String)
    case step(message: String)
    case execute(message: String)
    case missingColumn(String)

    public var errorDescription: String? {
        switch self {
        case let .open(message), let .prepare(message), let .bind(message), let .step(message), let .execute(message):
            return message
        case let .missingColumn(name):
            return "Missing SQLite column: \(name)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
