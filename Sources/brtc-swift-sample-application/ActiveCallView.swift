import SwiftUI

struct ActiveCallView: View {
    @ObservedObject var callManager: CallManager
    
    var body: some View {
        VStack {
            Spacer()
            
            Text("In Call")
                .font(.title)
                .padding()
            
            // "Boxes to show sound"
            VStack {
                Text("Remote Audio")
                    .font(.headline)
                AudioVisualizerView(isEffective: .constant(!callManager.remoteStreams.isEmpty))
                
                Text("Local Audio")
                    .font(.headline)
                    .padding(.top)
                AudioVisualizerView(isEffective: .constant(true))
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(radius: 5)
            .padding()
            
            Spacer()
            
            HStack(spacing: 40) {
                // Placeholder for Mute (Functionality would need to be added to CallManager)
                Button(action: {
                    // Mute logic
                }) {
                    VStack {
                        Image(systemName: "mic.slash.fill")
                            .font(.title)
                        Text("Mute")
                            .font(.caption)
                    }
                    .foregroundColor(.gray)
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
            }
            .padding(.bottom, 50)
        }
    }
}
