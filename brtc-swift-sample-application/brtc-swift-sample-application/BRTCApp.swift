import SwiftUI

@main
struct BRTCApp: App {
    @StateObject private var settingsManager = SettingsManager()
    
    init() {
        debugPrint("Hey I am here")
        if let bundleID = Bundle.main.bundleIdentifier {
            debugPrint("Bundle ID: \(bundleID)")
        } else {
            debugPrint("Bundle ID: Not found")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(settings: settingsManager).environmentObject(settingsManager)

        }
    }
}
