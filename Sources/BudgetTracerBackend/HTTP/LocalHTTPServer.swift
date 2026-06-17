import Darwin
import Foundation

final class LocalHTTPServer {
    typealias Handler = @Sendable (HTTPRequest) async throws -> HTTPResponse

    private let host: String
    private let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: "BudgetTracerBackend.Socket")
    private var serverSocket: Int32 = -1

    init(host: String = "127.0.0.1", port: UInt16, handler: @escaping Handler) {
        self.host = host
        self.port = port
        self.handler = handler
    }

    deinit {
        if serverSocket >= 0 {
            close(serverSocket)
        }
    }

    func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw HTTPServerError.socket(errno)
        }

        var reuse = Int32(1)
        guard setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw HTTPServerError.setsockopt(errno)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw HTTPServerError.invalidBindAddress(host)
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(serverSocket, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            throw HTTPServerError.bind(errno)
        }

        guard listen(serverSocket, SOMAXCONN) == 0 else {
            throw HTTPServerError.listen(errno)
        }

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while serverSocket >= 0 {
            var address = sockaddr()
            var addressLength = socklen_t(MemoryLayout<sockaddr>.size)
            let clientSocket = accept(serverSocket, &address, &addressLength)

            guard clientSocket >= 0 else {
                continue
            }

            Task { [handler] in
                await handle(clientSocket: clientSocket, handler: handler)
            }
        }
    }
}

private func handle(clientSocket: Int32, handler: @escaping LocalHTTPServer.Handler) async {
    defer { close(clientSocket) }

    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    let received = recv(clientSocket, &buffer, buffer.count, 0)
    guard received > 0 else {
        return
    }

    let requestData = Data(buffer.prefix(Int(received)))
    let response: HTTPResponse

    do {
        let request = try HTTPRequest(data: requestData)
        response = try await handler(request)
    } catch {
        response = HTTPResponse.json(
            status: .internalServerError,
            body: ErrorResponse(error: error.localizedDescription)
        )
    }

    let responseData = response.serialized()
    responseData.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            return
        }
        _ = send(clientSocket, baseAddress, responseData.count, 0)
    }
}

struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    init(data: Data) throws {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw HTTPError.badRequest("Missing HTTP header separator.")
        }

        let headerData = data[..<separator.lowerBound]
        body = Data(data[separator.upperBound...])

        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw HTTPError.badRequest("Headers are not UTF-8.")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPError.badRequest("Missing request line.")
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw HTTPError.badRequest("Malformed request line.")
        }

        method = requestParts[0].uppercased()
        let target = requestParts[1]
        let targetParts = target.split(separator: "?", maxSplits: 1).map(String.init)
        path = targetParts[0]
        query = targetParts.count > 1 ? HTTPRequest.parseQuery(targetParts[1]) : [:]

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }
            parsedHeaders[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        headers = parsedHeaders
    }

    func jsonBody<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: body.isEmpty ? Data("{}".utf8) : body)
    }

    private static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first?.removingPercentEncoding else {
                continue
            }
            result[key] = parts.count > 1 ? parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding : ""
        }
        return result
    }
}

struct HTTPResponse {
    var status: HTTPStatus
    var headers: [String: String]
    var body: Data

    static func json<T: Encodable>(status: HTTPStatus = .ok, body: T) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(body)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: status,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Cache-Control": "no-store"
            ],
            body: data
        )
    }

    func serialized() -> Data {
        var response = "HTTP/1.1 \(status.rawValue) \(status.reason)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        for (key, value) in headers {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }
}

enum HTTPStatus: Int {
    case ok = 200
    case accepted = 202
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case methodNotAllowed = 405
    case internalServerError = 500

    var reason: String {
        switch self {
        case .ok:
            return "OK"
        case .accepted:
            return "Accepted"
        case .badRequest:
            return "Bad Request"
        case .unauthorized:
            return "Unauthorized"
        case .notFound:
            return "Not Found"
        case .methodNotAllowed:
            return "Method Not Allowed"
        case .internalServerError:
            return "Internal Server Error"
        }
    }
}

enum HTTPError: Error, LocalizedError {
    case badRequest(String)
    case unauthorized(String)
    case notFound(String)
    case methodNotAllowed(String)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .unauthorized(message), let .notFound(message), let .methodNotAllowed(message):
            return message
        }
    }

    var status: HTTPStatus {
        switch self {
        case .badRequest:
            return .badRequest
        case .unauthorized:
            return .unauthorized
        case .notFound:
            return .notFound
        case .methodNotAllowed:
            return .methodNotAllowed
        }
    }
}

enum HTTPServerError: Error, LocalizedError {
    case invalidBindAddress(String)
    case socket(Int32)
    case setsockopt(Int32)
    case bind(Int32)
    case listen(Int32)

    var errorDescription: String? {
        switch self {
        case let .invalidBindAddress(host):
            return "Invalid bind address \(host). Use an IPv4 address such as 127.0.0.1 or 0.0.0.0."
        case let .socket(code):
            return "socket failed with errno \(code)."
        case let .setsockopt(code):
            return "setsockopt failed with errno \(code)."
        case let .bind(code):
            return "bind failed with errno \(code)."
        case let .listen(code):
            return "listen failed with errno \(code)."
        }
    }
}

struct ErrorResponse: Encodable {
    var error: String
}
