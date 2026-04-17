import Foundation

struct TokenResponse: Decodable {
    let token: String
    let endpointId: String?
}

struct CallStatus: Decodable {
    let status: String
    let callId: String?
    let cause: String?
}

/// Fetches JWT endpoint tokens from the local Express server.
final class TokenService {
    func fetchToken(serverURL: String) async throws -> (token: String, endpointId: String?) {
        guard let url = URL(string: "\(serverURL)/token") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "TokenService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned \(statusCode): \(body)"]
            )
        }

        // Try to decode as JSON first
        if let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data) {
            return (tokenResponse.token, tokenResponse.endpointId)
        }

        // Fall back to raw string
        if let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return (token, nil)
        }

        throw NSError(
            domain: "TokenService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid token response from server"]
        )
    }

    /// Poll the PSTN call status for an endpoint.
    func getCallStatus(serverURL: String, endpointId: String) async throws -> CallStatus {
        guard let url = URL(string: "\(serverURL)/api/endpoint/\(endpointId)/call-status") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(CallStatus.self, from: data)
    }

    /// Tell the server to hang up the PSTN leg for an endpoint.
    func hangupCall(serverURL: String, endpointId: String) async throws {
        guard let url = URL(string: "\(serverURL)/api/endpoint/\(endpointId)/hangup") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "TokenService", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Hangup failed with status \(http.statusCode)"])
        }
    }
}
