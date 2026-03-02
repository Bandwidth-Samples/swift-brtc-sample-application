import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) var dismiss // For dismissing the sheet

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Bandwidth API Credentials")) {
                    TextField("Account ID", text: $settings.accountId)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                    TextField("Username", text: $settings.username)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                    SecureField("Password", text: $settings.password)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                }
                
                Section(header: Text("Alternative: Client Credentials")) {
                    TextField("Client ID", text: $settings.clientId)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                    SecureField("Client Secret", text: $settings.clientSecret)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                }
                
                Section(header: Text("Callback & Numbers")) {
                    TextField("Callback Base URL", text: $settings.callbackBaseUrl)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        #endif
                    TextField("From Number", text: $settings.fromNumber)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Application ID", text: $settings.applicationId)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                }
                
                Section(header: Text("API Endpoints")) {
                    TextField("HTTP URL", text: $settings.httpUrl)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        #endif
                    TextField("BW ID Hostname", text: $settings.bwIdHostname)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        #endif
                }
                
                Section {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
