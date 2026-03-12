//
//  GleanClient.swift
//  FounderPrework
//
//  Created by Crystal Xiuzhu Tang on 2/17/26.
//

import Foundation

// MARK: - Errors

enum GleanClientError: Error, LocalizedError {
    case missingConfiguration
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Missing Glean configuration. Set GLEAN_API_TOKEN and GLEAN_INSTANCE."
        case .invalidURL:
            return "Invalid Glean API URL."
        case .httpError(let status, let body):
            return "Glean API HTTP error \(status): \(body)"
        case .decodingError(let underlying):
            return "Failed to decode Glean response: \(underlying.localizedDescription)"
        case .emptyResponse:
            return "Glean returned an empty response."
        }
    }
}

// MARK: - Glean Client

/// Minimal Swift client for Glean's Client API (Chat endpoint) to generate
/// a structured "prework memo" for a meeting.
///
/// This assumes:
/// - GLEAN_API_TOKEN: Client API token with CHAT scope (and ideally SEARCH/DOCUMENTS/SUMMARIZE).
/// - GLEAN_INSTANCE: instance prefix, e.g. "mongodb" → https://mongodb-be.glean.com
final class GleanClient {
    static let shared = GleanClient()

    private let apiToken: String
    private let instance: String
    private let urlSession: URLSession

    // Networking configuration
    private let requestTimeout: TimeInterval = 120 // seconds per request
    private let resourceTimeout: TimeInterval = 120 // total resource timeout
    private let maxRetries: Int = 2

    /// Initialize from environment variables by default.
    init(urlSession: URLSession? = nil) {
        let config = GleanConfig.shared
        self.apiToken = config.apiToken ?? ""
        self.instance = config.instance

        // Build a dedicated URLSession with explicit timeouts and waitsForConnectivity
        if let provided = urlSession {
            self.urlSession = provided
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = requestTimeout
            config.timeoutIntervalForResource = resourceTimeout
            config.waitsForConnectivity = true
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.urlSession = URLSession(configuration: config)
        }

        let tokenPresent = !apiToken.isEmpty
        let instancePresent = !instance.isEmpty
        print("GleanClient config – instance set? \(instancePresent), token set? \(tokenPresent)")
        if instancePresent { print("GleanClient instance=\(instance)") }
    }

    // MARK: - Public API

    /// Generate a structured prework memo for the given meeting using Glean Chat.
    ///
    /// The returned string is formatted Markdown ready to display in your UI.
    func generateMemo(for meeting: Meeting) async throws -> String {
        guard !apiToken.isEmpty, !instance.isEmpty else {
            throw GleanClientError.missingConfiguration
        }

        let prompt = buildPrompt(for: meeting)
        let requestBody = ChatRequest(
            messages: [
                ChatMessage(
                    fragments: [
                        ChatFragment(text: prompt)
                    ]
                )
            ]
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        guard let url = URL(string: "https://\(instance)-be.glean.com/rest/api/v1/chat") else {
            throw GleanClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        return try await sendWithRetries(request: request)
    }

    // MARK: - Networking core with retries and logging

    private func sendWithRetries(request: URLRequest) async throws -> String {
        var attempt = 0
        var lastError: Error?

        while attempt <= maxRetries {
            let start = Date()
            let attemptInfo = "#\(attempt + 1)/\(maxRetries + 1)"
            logRequestStart(request, attemptInfo: attemptInfo)
            do {
                let (data, response) = try await urlSession.data(for: request)
                let duration = Date().timeIntervalSince(start)
                try logResponse(response: response, data: data, duration: duration)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GleanClientError.httpError(statusCode: -1, body: "Non-HTTP response")
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                    throw GleanClientError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
                }

                let decoder = JSONDecoder()
                do {
                    if let preview = String(data: data, encoding: .utf8) {
                        print("[GleanClient] Body preview: \(preview)")
                    } else {
                        print("[GleanClient] Body preview: <non-UTF8>")
                    }
                    
                    let chatResponse = try decoder.decode(ChatResponse.self, from: data)

                    // Prefer top-level `text` if present (supported by official clients).
                    if let rawText = chatResponse.text,
                       !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return rawText
                    }

                    // Fallback: combine all text fragments from the last assistant message
                    if let messages = chatResponse.messages,
                       let lastMessage = messages.last,
                       let fragments = lastMessage.fragments {

                        let combined = fragments
                            .compactMap { $0.text }
                            .joined()

                        if !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return combined
                        }
                    }
                    
                    // Secondary fallback: try lenient extraction from JSON envelope
                    if let extracted = extractText(from: data) {
                        return extracted
                    }
                    
                    // Targeted extraction: last messages[].fragments[].text joined
                    if let strict = extractLastMessageFragmentsText(from: data) {
                        return strict
                    }

                    throw GleanClientError.emptyResponse
                } catch {
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[GleanClient] Decode failed. Raw body:\n\(raw)")
                    } else {
                        print("[GleanClient] Decode failed. Raw body is non-UTF8, \(data.count) bytes.")
                    }

                    // Lenient fallback: try to extract text before throwing
                    if let extracted = extractText(from: data) {
                        print("[GleanClient] Fallback extracted text from JSON envelope.")
                        return extracted
                    }
                    
                    // Last-resort targeted extraction
                    if let strict = extractLastMessageFragmentsText(from: data) {
                        print("[GleanClient] Targeted fallback extracted last message fragments text.")
                        return strict
                    }
                    
                    throw GleanClientError.decodingError(error)
                }
            } catch {
                lastError = error
                let nsError = error as NSError
                let duration = Date().timeIntervalSince(start)
                logRequestError(error: nsError, duration: duration)

                if shouldRetry(for: nsError), attempt < maxRetries {
                    let backoff = pow(2.0, Double(attempt))
                    let sleepTime = min(4.0, backoff) // cap backoff
                    print("Retrying in \(sleepTime)s (attempt \(attempt + 1) of \(maxRetries))...")
                    try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
                    attempt += 1
                    continue
                } else {
                    throw error
                }
            }
        }

        throw lastError ?? GleanClientError.emptyResponse
    }
    
    /// Extracts the concatenated text from the last element of `messages[].fragments[].text`.
    /// Returns nil if the shape is not present.
    private func extractLastMessageFragmentsText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any],
              let messages = dict["messages"] as? [[String: Any]],
              let last = messages.last,
              let fragments = last["fragments"] as? [[String: Any]]
        else {
            return nil
        }

        let joined = fragments.compactMap { $0["text"] as? String }.joined()
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Leniently extract assistant text from various possible JSON envelopes.
    /// Tries several common shapes used by chat-like APIs.
    private func extractText(from data: Data) -> String? {
        // Try decoding as UTF-8 string first: if the body is plain text/markdown, just return it.
        if let utf8 = String(data: data, encoding: .utf8) {
            // If it looks like raw markdown/text and not an object/array, return directly.
            let trimmed = utf8.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !(trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) {
                return trimmed
            }
        }

        // Parse as JSON dictionary/array and probe common locations.
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        // Helper closures
        func string(from any: Any?) -> String? {
            return any as? String
        }
        func extractFromMessageDict(_ dict: [String: Any]) -> String? {
            // Common fields: text, content
            if let t = dict["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
            if let c = dict["content"] as? String, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }
            // fragments: [{ text: ... }]
            if let frags = dict["fragments"] as? [[String: Any]] {
                let joined = frags.compactMap { $0["text"] as? String }.joined()
                if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return joined }
            }
            return nil
        }

        // Top-level dictionary handling
        if let dict = json as? [String: Any] {
            // Direct fields
            if let t = string(from: dict["text"]), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
            if let c = string(from: dict["content"]), !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }

            // message: { ... }
            if let message = dict["message"] as? [String: Any], let extracted = extractFromMessageDict(message) { return extracted }

            // messages: [ { ... } ] → usually last or first assistant message
            if let messages = dict["messages"] as? [[String: Any]] {
                // Try last then first
                if let last = messages.last, let extracted = extractFromMessageDict(last) { return extracted }
                if let first = messages.first, let extracted = extractFromMessageDict(first) { return extracted }
            }

            // choices: [ { message: { content: "..." } } ] (OpenAI-like)
            if let choices = dict["choices"] as? [[String: Any]] {
                for choice in choices {
                    if let msg = choice["message"] as? [String: Any], let extracted = extractFromMessageDict(msg) { return extracted }
                    if let t = choice["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
                }
            }

            // data: { ... } wrapper
            if let dataWrap = dict["data"] as? [String: Any] {
                if let extracted = extractFromMessageDict(dataWrap) { return extracted }
                if let nestedMessages = dataWrap["messages"] as? [[String: Any]] {
                    if let last = nestedMessages.last, let extracted = extractFromMessageDict(last) { return extracted }
                }
            }
        }

        // Top-level array handling: sometimes an array of events with {text: ...}
        if let array = json as? [[String: Any]] {
            for item in array {
                if let extracted = extractFromMessageDict(item) { return extracted }
            }
        }

        // If all else fails, return nil so caller can continue normal error handling.
        return nil
    }

    private func shouldRetry(for error: NSError) -> Bool {
        // Retry on common transient errors
        let retryableCodes: Set<Int> = [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorNotConnectedToInternet]
        return error.domain == NSURLErrorDomain && retryableCodes.contains(error.code)
    }

    private func logRequestStart(_ request: URLRequest, attemptInfo: String) {
        let urlString = request.url?.absoluteString ?? "<nil URL>"
        let method = request.httpMethod ?? "GET"
        let headers = request.allHTTPHeaderFields ?? [:]
        var redactedHeaders = headers
        if redactedHeaders["Authorization"] != nil {
            redactedHeaders["Authorization"] = "Bearer <redacted>"
        }
        let bodySize = request.httpBody?.count ?? 0
        let timeout = request.timeoutInterval

        print("[GleanClient] Request \(attemptInfo) START → \(method) \(urlString)")
        print("[GleanClient] Headers: \(redactedHeaders)")
        print("[GleanClient] Body size: \(bodySize) bytes | timeout: \(timeout)s | waitsForConnectivity: \((urlSession.configuration.waitsForConnectivity) ? "true" : "false")")
    }

    private func logResponse(response: URLResponse, data: Data, duration: TimeInterval) throws {
        if let http = response as? HTTPURLResponse {
            let headerDump = http.allHeaderFields
            print("[GleanClient] Response ← status=\(http.statusCode) in \(String(format: "%.3f", duration))s")
            print("[GleanClient] Response headers: \(headerDump)")
            if !(200..<300).contains(http.statusCode) {
                let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-UTF8>"
                print("[GleanClient] Error body (first 512B): \(snippet)")
            }
        } else {
            print("[GleanClient] Non-HTTP response in \(String(format: "%.3f", duration))s")
        }
    }

    private func logRequestError(error: NSError, duration: TimeInterval) {
        print("[GleanClient] ERROR after \(String(format: "%.3f", duration))s → domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
        if let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            print("[GleanClient] Failing URL: \(failingURL.absoluteString)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("[GleanClient] Underlying error: domain=\(underlying.domain) code=\(underlying.code) desc=\(underlying.localizedDescription)")
        }
    }

    // MARK: - Prompt construction

    /// Build the prompt that tells Glean exactly what to return and how to format it.
    private func buildPrompt(for meeting: Meeting) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startString = isoFormatter.string(from: meeting.startDate)
        let endString = meeting.endDate.map { isoFormatter.string(from: $0) } ?? "Unknown"

        // NOTE: If you later add attendees/emails to Meeting, append them here, e.g.:
        // - Attendees: alice@mongodb.com; bob@sequoiacap.com; carol@startup.com
        let metadataBlock = """
        - Title: \(meeting.title)
        - Start time: \(startString)
        - End time: \(endString)
        """

        return """
        You are preparing a concise meeting prework memo for the person you are currently acting as in Glean.
        Assume that this user is the primary host or owner of the meeting described below.

        Meeting metadata:
        \(metadataBlock)

        Use all information indexed in Glean (calendar events, email threads, internal docs, CRM/Attio data, notes, prior decks, etc.) to understand:
        - Who the counterparty is
        - What prior interactions exist
        - What the purpose of this specific meeting is
        - Any relevant technical or strategic background

        Assume Attio is available as a datasource if you see Attio records in search. Use Attio company/contact/opportunity data when classifying meeting type. Do NOT call any external APIs directly; only use what is available through Glean.
        
        ABSOLUTE RULES:
        - Do NOT ask the user any questions.
        - Do NOT offer options such as “Would you like a one-page investor note or a full diligence pack before the meeting?”.
        - Do NOT mention that you are an AI model.
        - ALWAYS output exactly the fields and headings in the template below.
        - If you do not know some detail, write “N/A” for that field instead of omitting it.
        - The only output should be the memo; no explanations, no extra text.

        ------------------------------------------------------------
        TASK 1 — Classify the meeting type
        ------------------------------------------------------------

        Choose exactly ONE of the following meeting types, using attendees, email domains, calendar descriptions, and Attio/CRM context:

        - Internal  → internal MongoDB-only discussion
        - Ventures  → external company that is an investment opportunity
        - CorpDev   → external company that is an M&A opportunity
        - Investor  → a current or prospective investor in MongoDB
        - PortCo    → a MongoDB Ventures portfolio company

        Always pick the single best-fit type.

        ------------------------------------------------------------
        TASK 2 — Determine whether this is a first meeting or a follow-up
        ------------------------------------------------------------

        Look at calendar + email + Attio history:
        - If there has been at least one clearly related previous meeting with this company or with the same core participants on this topic → treat this as a FOLLOW-UP meeting.
        - Otherwise → treat this as a FIRST meeting.

        ------------------------------------------------------------
        TASK 3 — Build the memo content
        ------------------------------------------------------------

        CASE A: FOLLOW-UP meeting (any meeting type)

        Use previous meetings + email threads + notes.

        Produce:

        1) Last Meeting Summary
           - ONE short sentence summarizing the most recent relevant meeting.

        2) Outstanding Items
           - ONE short sentence capturing key items owed by the person/MongoDB and by the counterparty after that last meeting (only the most important items).

        3) This Meeting Context
           - ONE short sentence on why this specific meeting is happening now (e.g., "IC prep before term sheet", "deep dive on pricing", "negotiating key terms").

        4) Discussion Goals
           - EXACTLY three bullet points describing what needs to be discussed or accomplished in this specific meeting.

        CASE B: FIRST meeting AND meeting type is Ventures or CorpDev

        Use company website, Attio data, prior email, internal docs, and any indexed LinkedIn pages for the founder.

        Produce:

        1) Company TL;DR
           - ONE short sentence describing what the company does, at the right level for MongoDB Ventures/CorpDev (product, users, stage).

        2) Founder Background
           - ONE short sentence summarizing the founder you are meeting with:
             role, key past roles or companies, and anything notable from their LinkedIn or online profile that is relevant.
           - Use LinkedIn or similar profiles only if they appear in the indexed content through Glean; do NOT assume access to the live web.

        3) Technical / Domain Background Needed
           - ONE short sentence on what the person should know going into the meeting (technical background, market context, or product details that matter).

        4) Evaluation Questions
           - EXACTLY three bullet points phrased as questions the person should get answered so she can leave the meeting with a clear idea of whether MongoDB should invest or acquire.
           - Make these specific, concrete questions (not vague like "understand the product").

        CASE C: FIRST meeting AND meeting type is Investor

        Use email threads, LinkedIn-style profiles, and any indexed online profiles for the investor.

        Produce:

        1) Investor Background
           - ONE short sentence summarizing who the investor is (firm, role, focus areas, stage, geography).

        2) Notable Points
           - ONE short sentence describing anything notable from their LinkedIn/online presence (track record, previous roles, reputation, recent moves).

        3) Common Ground
           - ONE short sentence describing key commonalities between the person's background and the investor’s (schools, prior employers, geography, shared portfolio, prior interactions) that might help build rapport.

        4) Discussion Goals
           - EXACTLY three bullet points for what should be accomplished in this meeting (e.g., understand their thesis on MongoDB/AI infra, fundraising context, partnership potential).

        CASE D: FIRST meeting AND meeting type is Internal or PortCo

        Use internal docs, emails, notes, and prior internal context.

        Produce:

        1) Background
           - ONE short sentence describing the internal or PortCo context for this meeting.

        2) This Meeting Context
           - ONE short sentence clarifying the purpose of this specific meeting.

        3) Discussion Goals
           - EXACTLY three bullet points of what needs to be discussed or decided.

        ------------------------------------------------------------
        OUTPUT FORMAT (Markdown, strictly)
        ------------------------------------------------------------

        You MUST follow this exact template. Do NOT add extra sections, explanations, or commentary.

        Meeting Type: <Internal|Ventures|CorpDev|Investor|PortCo>

        <For FOLLOW-UP meetings (any type) output EXACTLY these fields:>
        \nLast Meeting Summary: <one sentence>
        \nOutstanding Items: <one sentence>
        \nThis Meeting Context: <one sentence>
        \nDiscussion Goals:
        \n- <goal 1>
        \n- <goal 2>
        \n- <goal 3>

        <For FIRST meetings with type = Ventures or CorpDev output EXACTLY these fields instead:>
        \nTL;DR: <one sentence>
        \nFounder Background: <one sentence>
        \nTechnical / Domain Background: <one sentence>
        \nEvaluation Questions:
        \n- <question 1>
        \n- <question 2>
        \n- <question 3>

        <For FIRST meetings with type = Investor output EXACTLY these fields instead:>
        \nInvestor Background: <one sentence>
        \nNotable Points: <one sentence>
        \nCommon Ground: <one sentence>
        \nDiscussion Goals:
        \n- <goal 1>
        \n- <goal 2>
        \n- <goal 3>

        <For FIRST meetings with type = Internal or PortCo output EXACTLY these fields instead:>
        \nBackground: <one sentence>
        \nThis Meeting Context: <one sentence>
        \nDiscussion Goals:
        \n- <goal 1>
        \n- <goal 2>
        \n- <goal 3>
        """
    }
}

// MARK: - Internal request/response models

private struct ChatRequest: Codable {
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let fragments: [ChatFragment]
}

private struct ChatFragment: Codable {
    let text: String
}

private struct ChatResponse: Codable {
    let text: String?
    let messages: [ChatResponseMessage]?
}

private struct ChatResponseMessage: Codable {
    let fragments: [ChatResponseFragment]?
}

private struct ChatResponseFragment: Codable {
    let text: String?
}
