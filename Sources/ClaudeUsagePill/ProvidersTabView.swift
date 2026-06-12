import SwiftUI
import UsageCore

/// "Providers" settings tab. Stub for the Task 14 window shell — the row
/// list and detail sheets land in Task 15.
struct ProvidersTabView: View {
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var providersModel: ProvidersModel
    let specStore: ProviderSpecStore
    let keyStore: ProviderKeyStore

    var body: some View {
        Form {
            Section {
                Text("Providers")
            } footer: {
                Text("Rows appear in the pill in this order.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 380)
    }
}
