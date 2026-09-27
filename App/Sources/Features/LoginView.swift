import SeeleseekCore
import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var username = ""
    @State private var password = ""
    @State private var remember = true

    private var isBusy: Bool {
        session.status == .connecting || session.status == .reconnecting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Toggle("Remember me", isOn: $remember)
                } footer: {
                    Text("Your account is created on first login — there is no separate sign-up, and no password reset. If the name is already taken you will be asked to pick another, so choose something distinctive and keep the details somewhere safe.")
                }

                if let error = session.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(isBusy ? "Connecting…" : "Connect") {
                        Task { await submit() }
                    }
                    .disabled(isBusy || username.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Soulseek")
            .task {
                // Anything in the Keychain has already logged in successfully
                // at least once, so reconnecting with it is safe.
                guard let stored = Credentials.load() else { return }
                username = stored.username
                password = stored.password
                remember = true
                await session.connect(username: stored.username, password: stored.password)
            }
        }
    }

    private func submit() async {
        await session.connect(username: username, password: password)

        // Persist only what the server accepted. Saving before the attempt
        // meant a rejected password was stored and then auto-retried on every
        // launch, with the bad value pre-filled into the field.
        if session.isConnected {
            if remember {
                Credentials.save(username: username, password: password)
            } else {
                Credentials.clear()
            }
        } else if session.credentialsRejected {
            // Only discard on an explicit credential rejection. A timeout or
            // socket error must not throw away a password that works.
            Credentials.clear()
        }
    }
}
