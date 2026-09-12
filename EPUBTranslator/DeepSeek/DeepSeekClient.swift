import Foundation

struct ChatMessage: Codable, Hashable {
    var role: String
    var content: String

    static func system(_ content: String) -> ChatMessage { ChatMessage(role: "system", content: content) }
    static func user(_ content: String) -> ChatMessage { ChatMessage(role: "user", content: content) }
    static func assistant(_ content: String) -> ChatMessage { ChatMessage(role: "assistant", content: content) }
}

struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool
    var temperature: Double?
    var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let message: Message?
        let delta: Message?
    }

    let choices: [Choice]
}

enum DeepSeekError: Error, LocalizedError {
    case missingAPIKey
    case invalidEndpoint(String)
    case http(status: Int, message: String)
    case emptyResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "还没有填写 DeepSeek API Key，请到「设置」里添加。"
        case .invalidEndpoint(let value):
            return "API 地址无效：\(value)"
        case .http(let status, let message):
            return DeepSeekError.friendlyMessage(status: status, serverMessage: message)
        case .emptyResponse:
            return "模型没有返回内容，请稍后重试。"
        case .cancelled:
            return "已取消"
        }
    }

    static func friendlyMessage(status: Int, serverMessage: String) -> String {
        let detail = serverMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = detail.isEmpty ? "" : "（\(detail)）"
        switch status {
        case 400:
            return "请求格式有问题\(suffix)"
        case 401:
            return "API Key 无效或已过期，请到「设置」里重新填写。\(suffix)"
        case 402:
            return "DeepSeek 账户余额不足，请先充值。\(suffix)"
        case 403:
            return "没有访问权限\(suffix)"
        case 404:
            return "API 地址不正确，检查「设置」里的接口地址。\(suffix)"
        case 422:
            return "请求参数不被接受\(suffix)"
        case 429:
            return "请求太频繁或额度用完了，稍后再试。\(suffix)"
        case 500...599:
            return "DeepSeek 服务暂时不可用，稍后再试。\(suffix)"
        default:
            return "请求失败（HTTP \(status)）\(suffix)"
        }
    }
}

/// DeepSeek Chat Completions 客户端。
/// 无状态、可跨线程使用：所有配置都在初始化时注入，方便在后台任务里直接调用。
struct DeepSeekClient {
    let apiKey: String
    let endpoint: URL
    let session: URLSession

    init(apiKey: String, endpoint: URL, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
    }

    /// 从设置里读取 Key 和地址；设置对象是 MainActor 隔离的，所以这个初始化器也在主线程。
    @MainActor
    init(settings: SettingsStore) throws {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }
        guard let url = settings.completionsURL else {
            throw DeepSeekError.invalidEndpoint(settings.baseURLString)
        }
        self.init(apiKey: key, endpoint: url)
    }

    // MARK: - 一次性返回

    func complete(_ request: ChatRequest) async throws -> String {
        let urlRequest = try makeURLRequest(request, streaming: false)
        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard
            let content = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty
        else {
            throw DeepSeekError.emptyResponse
        }
        return content
    }

    // MARK: - 流式返回

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request, streaming: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw DeepSeekError.emptyResponse
                    }
                    if !(200...299).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 2000 { break }
                        }
                        throw DeepSeekError.http(status: http.statusCode, message: DeepSeekClient.serverMessage(from: body))
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard
                            let chunk = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
                            let delta = chunk.choices.first?.delta?.content,
                            !delta.isEmpty
                        else { continue }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: DeepSeekClient.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 内部

    private func makeURLRequest(_ request: ChatRequest, streaming: Bool) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }

        var payload = request
        payload.stream = streaming

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 180
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.emptyResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DeepSeekError.http(status: http.statusCode, message: DeepSeekClient.serverMessage(from: body))
        }
    }

    private static func serverMessage(from body: String) -> String {
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(body.prefix(300))
    }

    private static func mapError(_ error: Error) -> Error {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return DeepSeekError.cancelled
        }
        return error
    }
}
