import SwiftUI

struct ContentView: View {
    @StateObject private var callManager = CallManager()
    
    var body: some View {
        ZStack {
            if callManager.isInCall {
                ActiveCallView(callManager: callManager)
                    .transition(.move(edge: .bottom))
            } else {
                DialerView(callManager: callManager)
                    .onAppear {
                        // Auto-connect to backend when app opens or returns to dialer
                        if callManager.connectionState == "Disconnected" {
                            Task {
                                await callManager.connect()
                            }
                        }
                    }
            }
        }
        .animation(.default, value: callManager.isInCall)
    }
}
