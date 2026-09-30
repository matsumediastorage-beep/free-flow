import Foundation
import os

/// Cleans up a raw transcript with Claude Haiku — the pass that turns
/// "um so like send me the uh the file tomorrow ok" into "Send me the file tomorrow."
///
/// Two hard rules, because this sits directly in the paste path:
///
///  1. **It can never block you.** A short, length-scaled timeout, and any failure — no key, no
///     network, bad response, refusal — falls back to the raw transcript. You
///     always get your text.
///  2. **It only reformats.** The prompt forbids answering, continuing, or
///     embellishing. Dictating "what's the capital of France" types that
///     question; it doesn't answer it.
///
/// Swift has no official Anthropic SDK, so this calls the Messages API over
/// HTTPS directly, which is the documented path for unsupported languages.
struct ClaudeFormatter: TextFormatter {

    /// Haiku 4.5: the right pick here because this is a short, latency-critical
    /// reformatting task, not a reasoning one.
    private static let model = "claude-haiku-4-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    private static let warmupEndpoint = URL(string: "https://api.anthropic.com/v1/models")!

    /// The longest we'd ever wait before pasting raw text instead.
    private static let ceiling: TimeInterval = 5.0
    /// The shortest budget, covering the network round trip on a short phrase.
    private static let floor: TimeInterval = 1.5

    /// How long to wait on a transcript of this length.
    ///
    /// A flat budget quietly punished long dictations. The model has more text
    /// to rewrite, so a paragraph legitimately takes longer than a one-liner —
    /// and with a fixed 1.5s the paragraph was the case that always timed out
    /// and fell back to the raw transcript, which is precisely the case where
    /// cleanup is worth the most. Fixed round-trip cost, plus time proportional
    /// to length.
    static func timeout(forCharacterCount count: Int) -> TimeInterval {
        let perCharacter: TimeInterval = 0.0025  // ~15ms per six-character word
        return min(ceiling, floor + Double(count) * perCharacter)
    }

    private let apiKey: String
    private let fallback: any TextFormatter
    private let session: URLSession
    private let logger = Logger(subsystem: "com.matsumedia.flow", category: "formatter")

    /// Falls back to Apple's on-device model when Claude can't be reached —
    /// offline, timed out, bad key — so a flaky connection still gets you a
    /// cleaned-up sentence rather than the raw transcript.
    init(apiKey: String, fallback: any TextFormatter = AppleFormatter()) {
        self.apiKey = apiKey
        self.fallback = fallback

        let config = URLSessionConfiguration.ephemeral
        // The session caps at the ceiling; each request narrows it to the
        // budget its own length earns, via `URLRequest.timeoutInterval`.
        config.timeoutIntervalForRequest = Self.ceiling
        config.timeoutIntervalForResource = Self.ceiling
        config.waitsForConnectivity = false  // fail fast when offline
        self.session = URLSession(configuration: config)
    }

    var usesAI: Bool { true }

    /// Opens the HTTPS connection while the user is still talking.
    ///
    /// The TLS handshake to api.anthropic.com is a couple of round trips —
    /// often 100–300ms — and it would otherwise land after you release the key,
    /// in the one moment you're actually waiting. `URLSession` keeps the
    /// connection alive, so the real request reuses it. The request carries no
    /// key and no text; it exists only to be rejected quickly.
    func prepare() async {
        var request = URLRequest(url: Self.warmupEndpoint)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        _ = try? await session.data(for: request)
    }

    func format(_ raw: String, context: FormattingContext) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !apiKey.isEmpty else { return trimmed }

        let started = Date()
        do {
            let cleaned = try await requestCleanup(trimmed, context: context)
            let result = CleanupPrompt.sanitize(cleaned, raw: trimmed)
            // An empty or absurdly inflated response means something went wrong
            // with the model's instruction-following — don't trust it.
            guard CleanupPrompt.isPlausible(result, raw: trimmed) else {
                CleanupStatus(
                    at: Date(), succeeded: false,
                    detail: "Model returned an unusable response",
                    seconds: Date().timeIntervalSince(started)
                ).write()
                return await fallback.format(trimmed, context: context)
            }
            CleanupStatus(
                at: Date(), succeeded: true,
                detail: result == trimmed ? "Nothing needed changing (Claude)" : "Cleaned by Claude",
                seconds: Date().timeIntervalSince(started)
            ).write()
            return result
        } catch {
            logger.error("Cleanup failed, falling back: \(error.localizedDescription)")
            CleanupStatus(
                at: Date(), succeeded: false,
                detail: error.localizedDescription,
                seconds: Date().timeIntervalSince(started)
            ).write()
            // A timeout has already spent the user's patience; don't spend
            // more of it on a second model. Anything else (offline, bad key)
            // failed fast, so the on-device pass still fits.
            if (error as? URLError)?.code == .timedOut {
                return await LocalFormatter().format(trimmed, context: context)
            }
            return await fallback.format(trimmed, context: context)
        }
    }

    // MARK: - Request

    private func requestCleanup(_ raw: String, context: FormattingContext) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = Self.timeout(forCharacterCount: raw.count)

        // Cleaned text is never much longer than the input; this cap is
        // generous enough to never truncate a real dictation.
        let maxTokens = min(4096, max(256, raw.count / 2 + 256))

        let payload = MessagesRequest(
            model: Self.model,
            maxTokens: maxTokens,
            // Deterministic: the same dictation should clean up the same way.
            temperature: 0,
            system: CleanupPrompt.system(for: context),
            messages: [
                .init(role: "user", content: CleanupPrompt.user(transcript: raw, context: context))
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw FormatterError.badResponse
        }
        guard http.statusCode == 200 else {
            // The body carries the actual reason (bad key, no credit, bad
            // model id). Surfacing just the status code would waste everyone's
            // time guessing which.
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FormatterError.httpError(status: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)

        // Safety classifiers can decline; there's no usable text in that case.
        guard decoded.stopReason != "refusal" else {
            throw FormatterError.refused
        }

        // `content` is an array of typed blocks — take the first text one.
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw FormatterError.noTextBlock
        }
        return text
    }
}

// MARK: - Wire types

private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

private struct MessagesResponse: Decodable {
    let content: [ContentBlock]
    let stopReason: String?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

enum FormatterError: LocalizedError {
    /// Pulls `error.message` out of the API's JSON error envelope.
    fileprivate static func apiMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return nil }
        return message
    }

    case badResponse
    case httpError(status: Int, body: String)
    case refused
    case noTextBlock

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from the cleanup service."
        case .httpError(let status, let body):
            let reason = Self.apiMessage(from: body) ?? body.prefix(200).description
            return "HTTP \(status) — \(reason)"
        case .refused: return "Cleanup request was declined."
        case .noTextBlock: return "Cleanup response contained no text."
        }
    }
}
