import Foundation
import Combine

class SettingsManager: ObservableObject {
    @Published var accountId: String {
        didSet {
            UserDefaults.standard.set(accountId, forKey: "accountId")
        }
    }
    @Published var username: String {
        didSet {
            UserDefaults.standard.set(username, forKey: "username")
        }
    }
    @Published var password: String {
        didSet {
            UserDefaults.standard.set(password, forKey: "password")
        }
    }
    @Published var callbackBaseUrl: String {
        didSet {
            UserDefaults.standard.set(callbackBaseUrl, forKey: "callbackBaseUrl")
        }
    }
    @Published var fromNumber: String {
        didSet {
            UserDefaults.standard.set(fromNumber, forKey: "fromNumber")
        }
    }
    @Published var httpUrl: String {
        didSet {
            UserDefaults.standard.set(httpUrl, forKey: "httpUrl")
        }
    }
    @Published var bwIdHostname: String {
        didSet {
            UserDefaults.standard.set(bwIdHostname, forKey: "bwIdHostname")
        }
    }
    @Published var clientId: String {
        didSet {
            UserDefaults.standard.set(clientId, forKey: "clientId")
        }
    }
    @Published var clientSecret: String {
        didSet {
            UserDefaults.standard.set(clientSecret, forKey: "clientSecret")
        }
    }
    @Published var applicationId: String {
        didSet {
            UserDefaults.standard.set(applicationId, forKey: "applicationId")
        }
    }

    init() {
        print("SettingsManager initializing")
        self.accountId = UserDefaults.standard.string(forKey: "accountId") ?? "YOUR_ACCOUNT_ID"
        self.username = UserDefaults.standard.string(forKey: "username") ?? "YOUR_USERNAME"
        self.password = UserDefaults.standard.string(forKey: "password") ?? "YOUR_PASSWORD"
        self.callbackBaseUrl = UserDefaults.standard.string(forKey: "callbackBaseUrl") ?? "YOUR_CALLBACK_URL"
        self.fromNumber = UserDefaults.standard.string(forKey: "fromNumber") ?? "YOUR_FROM_NUMBER"
        self.httpUrl = UserDefaults.standard.string(forKey: "httpUrl") ?? "https://api.bandwidth.com"
        self.bwIdHostname = UserDefaults.standard.string(forKey: "bwIdHostname") ?? "id.bandwidth.com"
        self.clientId = UserDefaults.standard.string(forKey: "clientId") ?? ""
        self.clientSecret = UserDefaults.standard.string(forKey: "clientSecret") ?? ""
        self.applicationId = UserDefaults.standard.string(forKey: "applicationId") ?? "YOUR_APPLICATION_ID"
    }

    var areAllSettingsProvided: Bool {
        let hasUserPass = username != "YOUR_USERNAME" && 
                         password != "YOUR_PASSWORD" && 
                         !username.isEmpty && 
                         !password.isEmpty
        let hasClientCreds = !clientId.isEmpty && !clientSecret.isEmpty
        
        let accountIdValid = accountId != "YOUR_ACCOUNT_ID" && !accountId.isEmpty
        let callbackUrlValid = callbackBaseUrl != "YOUR_CALLBACK_URL" && !callbackBaseUrl.isEmpty
        let fromNumberValid = fromNumber != "YOUR_FROM_NUMBER" && !fromNumber.isEmpty
        let applicationIdValid = applicationId != "YOUR_APPLICATION_ID" && !applicationId.isEmpty
        let httpUrlValid = !httpUrl.isEmpty
        let bwIdHostnameValid = !bwIdHostname.isEmpty
        let credsValid = hasUserPass || hasClientCreds
        
        let result = accountIdValid &&
               callbackUrlValid &&
               fromNumberValid &&
               applicationIdValid &&
               httpUrlValid &&
               bwIdHostnameValid &&
               credsValid
        
        print("SettingsManager.areAllSettingsProvided check:")
        print("  accountIdValid: \(accountIdValid) [\(accountId)]")
        print("  callbackUrlValid: \(callbackUrlValid) [\(callbackBaseUrl)]")
        print("  fromNumberValid: \(fromNumberValid) [\(fromNumber)]")
        print("  applicationIdValid: \(applicationIdValid) [\(applicationId)]")
        print("  httpUrlValid: \(httpUrlValid) [\(httpUrl)]")
        print("  bwIdHostnameValid: \(bwIdHostnameValid) [\(bwIdHostname)]")
        print("  hasUserPass: \(hasUserPass)")
        print("  hasClientCreds: \(hasClientCreds)")
        print("  credsValid: \(credsValid)")
        print("  FINAL RESULT: \(result)")
        
        return result
    }
}
