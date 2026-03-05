import Foundation

struct TokenResponse: Decodable {
    let token: String
    let endpointId: String?
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
            throw NSError(
                domain: "TokenService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned status \(statusCode)"]
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
}
