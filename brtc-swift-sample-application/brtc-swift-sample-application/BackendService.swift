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
    case missingCredentials
}

class BackendService {
    private let settings: SettingsManager
    private var cachedToken: String?
    private var tokenExpiration: Date?
    
    init(settings: SettingsManager) {
        self.settings = settings
    }

    func placeCall(fromEndpointId endpointId: String, toNumber: String) async throws {
        print("BackendService.placeCall called for endpoint: \(endpointId), toNumber: \(toNumber)")
        guard settings.areAllSettingsProvided else {
            throw BackendError.missingCredentials
        }

        guard let url = URL(string: "\(settings.callbackBaseUrl)/api/testCall") else {
            throw BackendError.invalidURL
        }
        
        print("BackendService.placeCall URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "applicationId": settings.applicationId,
            "to": toNumber,
            "from": settings.fromNumber,
            "answerUrl": "\(settings.callbackBaseUrl)/api/callbacks/calls/status"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("BackendService.placeCall failed with status \(httpResponse.statusCode): \(responseString)")
                throw BackendError.serverError("Place Call failed: Status \(httpResponse.statusCode) - \(responseString)")
            }
        } catch let urlError as URLError {
            print("BackendService.placeCall network error: \(urlError.localizedDescription)")
            throw BackendError.networkError(urlError)
        } catch {
            print("BackendService.placeCall generic error: \(error.localizedDescription)")
            throw BackendError.networkError(error)
        }
    }

    func createEndpoint() async throws -> Endpoint {
        print("BackendService.createEndpoint called")
        print("Settings check:")
        print("  accountId: '\(settings.accountId)'")
        print("  username: '\(settings.username)'")
        print("  password: '\(settings.password.isEmpty ? "(empty)" : "(provided)")'")
        print("  clientId: '\(settings.clientId)'")
        print("  clientSecret: '\(settings.clientSecret.isEmpty ? "(empty)" : "(provided)")'")
        print("  callbackBaseUrl: '\(settings.callbackBaseUrl)'")
        print("  fromNumber: '\(settings.fromNumber)'")
        print("  applicationId: '\(settings.applicationId)'")
        print("  httpUrl: '\(settings.httpUrl)'")
        print("  bwIdHostname: '\(settings.bwIdHostname)'")
        print("  areAllSettingsProvided: \(settings.areAllSettingsProvided)")
        
        guard settings.areAllSettingsProvided else {
            print("BackendService.createEndpoint: FAILED - settings not provided")
            throw BackendError.missingCredentials
        }
        let authToken = try await getAuthToken()
        
        guard let url = URL(string: "\(settings.httpUrl)/v2/accounts/\(settings.accountId)/endpoints") else {
            throw BackendError.invalidURL
        }
        
        print("BackendService.createEndpoint URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "type": "WEBRTC",
            "direction": "BIDIRECTIONAL",
            "eventCallbackUrl": "\(settings.callbackBaseUrl)/api/callbacks/endpoints/status",
            "eventFallbackUrl": "\(settings.callbackBaseUrl)/api/callbacks/endpoints/status",
            "tag": "{\"myTag\": \"myTagValue\"}"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log the raw response for debugging
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("BackendService.createEndpoint raw response: \(responseString)")
            
            if let httpResponse = response as? HTTPURLResponse {
                print("BackendService.createEndpoint status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 201 {
                    print("BackendService.createEndpoint failed with status \(httpResponse.statusCode): \(responseString)")
                    throw BackendError.serverError("Create Endpoint failed: Status \(httpResponse.statusCode) - \(responseString)")
                }
            }
            
            // Try to decode with flexible structure
            struct EndpointResponse: Codable {
                struct DataWrapper: Codable {
                    let token: String
                    let endpointId: String
                }
                let data: DataWrapper?
                let token: String?
                let endpointId: String?
            }
            
            let decoder = JSONDecoder()
            let endpointResponse = try decoder.decode(EndpointResponse.self, from: data)
            
            // Handle both nested and flat response structures
            let token: String
            let endpointId: String
            
            if let dataWrapper = endpointResponse.data {
                token = dataWrapper.token
                endpointId = dataWrapper.endpointId
            } else if let flatToken = endpointResponse.token, let flatEndpointId = endpointResponse.endpointId {
                token = flatToken
                endpointId = flatEndpointId
            } else {
                print("BackendService.createEndpoint: Could not extract token and endpointId from response")
                throw BackendError.decodingError(NSError(domain: "BackendService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response structure"]))
            }
            
            print("BackendService.createEndpoint successfully decoded - endpointId: \(endpointId)")
            return Endpoint(endpointId: endpointId, endpointToken: token)
        } catch let decodingError as DecodingError {
            print("BackendService.createEndpoint decoding error: \(decodingError.localizedDescription)")
            throw BackendError.decodingError(decodingError)
        } catch let urlError as URLError {
            print("BackendService.createEndpoint network error: \(urlError.localizedDescription)")
            throw BackendError.networkError(urlError)
        } catch {
            print("BackendService.createEndpoint generic error: \(error.localizedDescription)")
            throw BackendError.networkError(error)
        }
    }

    func deleteEndpoint(endpointId: String) async throws {
        print("BackendService.deleteEndpoint called for endpoint: \(endpointId)")
        guard settings.areAllSettingsProvided else {
            throw BackendError.missingCredentials
        }
        let authToken = try await getAuthToken()
        
        guard let url = URL(string: "\(settings.httpUrl)/v2/accounts/\(settings.accountId)/endpoints/\(endpointId)") else {
            throw BackendError.invalidURL
        }
        
        print("BackendService.deleteEndpoint URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // 200 (OK) and 204 (No Content) are both valid success responses for DELETE
                if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
                    let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                    print("BackendService.deleteEndpoint failed with status \(httpResponse.statusCode): \(responseString)")
                    throw BackendError.serverError("Delete Endpoint failed: Status \(httpResponse.statusCode) - \(responseString)")
                }
                print("BackendService.deleteEndpoint succeeded with status \(httpResponse.statusCode)")
            }
        } catch let urlError as URLError {
            print("BackendService.deleteEndpoint network error: \(urlError.localizedDescription)")
            throw BackendError.networkError(urlError)
        } catch {
            print("BackendService.deleteEndpoint generic error: \(error.localizedDescription)")
            throw BackendError.networkError(error)
        }
    }
    
    private func getAuthToken() async throws -> String {
        guard settings.areAllSettingsProvided else {
            throw BackendError.missingCredentials
        }
        
        // Check if we have a valid token that's not expired
        if let token = cachedToken, let expiration = tokenExpiration, Date() < expiration {
            return token
        }
        
        // Determine which credentials to use
        let (username, password): (String, String)
        if !settings.clientId.isEmpty && !settings.clientSecret.isEmpty {
            username = settings.clientId
            password = settings.clientSecret
        } else {
            username = settings.username
            password = settings.password
        }
        
        guard let url = URL(string: "https://\(settings.bwIdHostname)/api/v1/oauth2/token") else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("BackendService.getAuthToken failed with status \(httpResponse.statusCode): \(responseString)")
                throw BackendError.serverError("Auth Token failed: Status \(httpResponse.statusCode) - \(responseString)")
            }
            
            struct TokenResponse: Codable {
                let access_token: String
                let expires_in: Int?
            }
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            // Cache the token with expiration (subtract 10 seconds for safety margin)
            self.cachedToken = tokenResponse.access_token
            let expiresIn = tokenResponse.expires_in ?? 3600 // Default to 1 hour if not provided
            self.tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn - 10))
            
            return tokenResponse.access_token
        } catch let decodingError as DecodingError {
            print("BackendService.getAuthToken decoding error: \(decodingError.localizedDescription)")
            throw BackendError.decodingError(decodingError)
        } catch let urlError as URLError {
            print("BackendService.getAuthToken network error: \(urlError.localizedDescription)")
            throw BackendError.networkError(urlError)
        } catch {
            print("BackendService.getAuthToken generic error: \(error.localizedDescription)")
            throw BackendError.networkError(error)
        }
    }
}
