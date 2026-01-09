import SwiftUI

struct DialerView: View {
    @ObservedObject var callManager: CallManager
    @State private var phoneNumber: String = ""
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    let keys = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", "")
    ]
    
    var body: some View {
        VStack {
            Spacer()
            
            Text(phoneNumber)
                .font(.largeTitle)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
            
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(keys, id: \.0) { key in
                    Button(action: {
                        phoneNumber.append(key.0)
                    }) {
                        VStack {
                            Text(key.0)
                                .font(.title)
                                .fontWeight(.bold)
                            if !key.1.isEmpty {
                                Text(key.1)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 80, height: 80)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Circle())
                    }
                }
            }
            .padding()
            
            Button(action: {
                if !phoneNumber.isEmpty {
                    callManager.startCall(phoneNumber: phoneNumber)
                }
            }) {
                Image(systemName: "phone.fill")
                    .font(.largeTitle)
                    .frame(width: 80, height: 80)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .padding(.top, 20)
            .disabled(phoneNumber.isEmpty || callManager.connectionState != "Connected")
            
            Text(callManager.connectionState)
                .font(.caption)
                .foregroundColor(.gray)
                .padding()
            
            Spacer()
        }
    }
}
