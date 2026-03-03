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

    init(settings: SettingsManager) {
        self.settings = settings
    }

    // MARK: - Endpoint Management

    func createEndpoint() async throws -> Endpoint {
        print("BackendService.createEndpoint called")

        guard let url = URL(string: "\(settings.backendUrl)/api/endpoint") else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                    print("BackendService.createEndpoint failed with status \(httpResponse.statusCode): \(responseString)")
                    throw BackendError.serverError("Create Endpoint failed: Status \(httpResponse.statusCode)")
                }
            }

            let endpoint = try JSONDecoder().decode(Endpoint.self, from: data)
            print("BackendService.createEndpoint successfully decoded - endpointId: \(endpoint.endpointId)")
            return endpoint
        } catch let decodingError as DecodingError {
            print("BackendService.createEndpoint decoding error: \(decodingError.localizedDescription)")
            throw BackendError.decodingError(decodingError)
        } catch let urlError as URLError {
            print("BackendService.createEndpoint network error: \(urlError.localizedDescription)")
            throw BackendError.networkError(urlError)
        } catch {
            throw error
        }
    }

    func placeCall(fromEndpointId endpointId: String, toNumber: String) async throws {
        print("BackendService.placeCall called for endpoint: \(endpointId), toNumber: \(toNumber)")

        guard let url = URL(string: "\(settings.backendUrl)/api/testCall") else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "endpointId": endpointId,
            "toNumber": toNumber
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("BackendService.placeCall failed with status \(httpResponse.statusCode): \(responseString)")
                throw BackendError.serverError("Place Call failed: Status \(httpResponse.statusCode)")
            }

            print("BackendService.placeCall succeeded")
        } catch let urlError as URLError {
            print("BackendService.placeCall network error: \(urlError.localizedDescription)")
            throw BackendError.networkError(urlError)
        } catch {
            throw error
        }
    }

    func deleteEndpoint(endpointId: String) async throws {
        print("BackendService.deleteEndpoint called for endpoint: \(endpointId)")

        guard let url = URL(string: "\(settings.backendUrl)/api/endpoint/\(endpointId)") else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    print("BackendService.deleteEndpoint failed with status \(httpResponse.statusCode)")
                    throw BackendError.serverError("Delete Endpoint failed: Status \(httpResponse.statusCode)")
                }
                print("BackendService.deleteEndpoint succeeded")
            }
        } catch let urlError as URLError {
            print("BackendService.deleteEndpoint network error: \(urlError.localizedDescription)")
            throw BackendError.networkError(urlError)
        } catch {
            throw error
        }
    }
}
