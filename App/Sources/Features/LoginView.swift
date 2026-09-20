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
                    Text("Soulseek has no password reset. Keep your credentials somewhere safe — if you lose them the account is gone.")
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
                guard let stored = Credentials.load() else { return }
                username = stored.username
                password = stored.password
                await session.connect(username: stored.username, password: stored.password)
            }
        }
    }

    private func submit() async {
        if remember {
            Credentials.save(username: username, password: password)
        } else {
            Credentials.clear()
        }
        await session.connect(username: username, password: password)
    }
}
