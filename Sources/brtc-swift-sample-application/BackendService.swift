import Foundation

struct Endpoint: Codable {
    let endpointId: String
    let endpointToken: String
}

enum BackendError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(String)
}

class BackendService {
    // REPLACE THESE WITH YOUR VALUES OR USE A SETTINGS VIEW
    private let accountId = "YOUR_ACCOUNT_ID"
    private let username = "YOUR_USERNAME"
    private let password = "YOUR_PASSWORD"
    private let callbackBaseUrl = "YOUR_CALLBACK_URL"
    private let httpUrl = "https://api.bandwidth.com"
    private let bwIdHostname = "id.bandwidth.com"

    func createEndpoint() async throws -> Endpoint {
        let authToken = try await getAuthToken()
        
        guard let url = URL(string: "https://api.bandwidth.com/v2/accounts/\(accountId)/endpoints") else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "type": "WEBRTC",
            "direction": "BIDIRECTIONAL",
            "eventCallbackUrl": "\(callbackBaseUrl)/api/callbacks/endpoints/status",
            "eventFallbackUrl": "\(callbackBaseUrl)/api/callbacks/endpoints/status",
            "tag": "{\"myTag\": \"myTagValue\"}"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BackendError.serverError("Failed to create endpoint")
        }
        
        struct EndpointResponse: Codable {
            struct Data: Codable {
                let token: String
                let endpointId: String
            }
            let data: Data
        }
        
        let endpointResponse = try JSONDecoder().decode(EndpointResponse.self, from: data)
        return Endpoint(endpointId: endpointResponse.data.endpointId, endpointToken: endpointResponse.data.token)
    }

    func deleteEndpoint(endpointId: String) async throws {
        let authToken = try await getAuthToken()
        
        guard let url = URL(string: "https://api.bandwidth.com/v2/accounts/\(accountId)/endpoints/\(endpointId)") else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BackendError.serverError("Failed to delete endpoint")
        }
    }
    
    private func getAuthToken() async throws -> String {
        guard let url = URL(string: "https://id.bandwidth.com/api/v1/oauth2/token") else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct TokenResponse: Codable {
            let access_token: String
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.access_token
    }
}
