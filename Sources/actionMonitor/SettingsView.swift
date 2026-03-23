#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: StatusStore
    @State private var tokenInput: String

    init(store: StatusStore) {
        self.store = store
        _tokenInput = State(initialValue: store.token)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("GitHub Access")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text("Store a personal access token in Keychain so the menu bar app can read GitHub Actions workflow runs for your sites.")
                .foregroundStyle(.secondary)

            SecureField("GitHub personal access token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)

            Text("For private repositories, use a token that can read Actions data. Public repos can work without one, but a token avoids stricter rate limits.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Save Token") {
                    store.saveToken(tokenInput)
                }
                .keyboardShortcut(.defaultAction)

                Button("Remove Token") {
                    tokenInput = ""
                    store.clearToken()
                }

                Spacer()
            }

            if let credentialMessage = store.credentialMessage {
                Text(credentialMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onChange(of: store.token) { _, newValue in
            tokenInput = newValue
        }
    }
}
#endif
