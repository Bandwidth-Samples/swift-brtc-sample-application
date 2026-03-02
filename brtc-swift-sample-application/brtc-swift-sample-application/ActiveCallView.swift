import SwiftUI

struct ActiveCallView: View {
    @ObservedObject var callManager: CallManager
    @State private var showingDtmfInput = false
    
    var formattedCallDuration: String {
        let hours = Int(callManager.callDuration) / 3600
        let minutes = Int(callManager.callDuration) / 60 % 60
        let seconds = Int(callManager.callDuration) % 60
        return String(format: "%02i:%02i:%02i", hours, minutes, seconds)
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            Text(callManager.connectionState) // Display connection status
                .font(.headline)
                .padding(.bottom, 5)
            
            Text(formattedCallDuration) // Display call duration
                .font(.title2)
                .padding(.bottom)
            
            // "Boxes to show sound"
            VStack {
                Text("Remote Audio")
                    .font(.headline)
                AudioVisualizerView(isEffective: .constant(!callManager.remoteStreams.isEmpty))
                
                Text("Local Audio")
                    .font(.headline)
                    .padding(.top)
                AudioVisualizerView(isEffective: $callManager.isMuted.not) // Reflect mute state
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(radius: 5)
            .padding()
            
            Spacer()
            
            HStack(spacing: 20) { // Reduced spacing for more buttons
                // Mute/Unmute Button
                Button(action: {
                    callManager.toggleMute()
                }) {
                    VStack {
                        Image(systemName: callManager.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.title)
                        Text(callManager.isMuted ? "Unmute" : "Mute")
                            .font(.caption)
                    }
                    .foregroundColor(callManager.isMuted ? .red : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Send DTMF Button
                Button(action: {
                    showingDtmfInput = true
                }) {
                    VStack {
                        Image(systemName: "number.square.fill")
                            .font(.title)
                        Text("DTMF")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .sheet(isPresented: $showingDtmfInput) {
                    DtmfInputView(callManager: callManager, isShowingSheet: $showingDtmfInput)
                }
                
                Button(action: {
                    callManager.endCall()
                }) {
                    Image(systemName: "phone.down.fill")
                        .font(.largeTitle)
                        .frame(width: 80, height: 80)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 50)
        }
    }
}

struct DtmfInputView: View {
    @ObservedObject var callManager: CallManager
    @Binding var isShowingSheet: Bool
    @State private var dtmfDigit: String = ""
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Enter DTMF Digit")
                    .font(.headline)
                    .padding()
                
                TextField("Digit (0-9, *, #)", text: $dtmfDigit)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button("Send") {
                    if dtmfDigit.count == 1 && "0123456789*#".contains(dtmfDigit) {
                        callManager.sendDTMF(key: dtmfDigit)
                        isShowingSheet = false
                    }
                }
                .padding()
                .disabled(!(dtmfDigit.count == 1 && "0123456789*#".contains(dtmfDigit)))
            }
            .navigationTitle("DTMF Input")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingSheet = false
                    }
                }
            }
        }
    }
}

extension Binding where Value == Bool {
    var not: Binding<Value> {
        Binding<Value>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}
