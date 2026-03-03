import Foundation
import Combine

class SettingsManager: ObservableObject {
    @Published var backendUrl: String {
        didSet {
            UserDefaults.standard.set(backendUrl, forKey: "backendUrl")
        }
    }

    init() {
        print("SettingsManager initializing")
        self.backendUrl = UserDefaults.standard.string(forKey: "backendUrl") ?? "http://localhost:5000"
    }
}
