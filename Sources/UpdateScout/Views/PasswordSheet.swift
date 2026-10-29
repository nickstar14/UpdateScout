import SwiftUI

/// Asks for the admin password once, shortly after a batch starts, when
/// something in it needs admin. Everything else keeps running behind it.
struct PasswordSheet: View {
    @EnvironmentObject var controller: UpdateController
    let request: UpdateController.PasswordRequest

    @State private var password = ""
    @State private var checking = false
    @State private var wrong = false
    @FocusState private var focused: Bool

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "UpdateScout"
    }
    private var updates: String { request.count == 1 ? "1 update needs" : "\(request.count) updates need" }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: AskpassDialog.circularKeyIcon())
                .resizable().frame(width: 52, height: 52)
            Text("\(appName) needs your password").font(.headline)
            Text("\(updates) administrator access. Enter it once and \(appName) uses it for this batch only. Nothing is saved.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(authorize)
                .disabled(checking)
            if wrong {
                Text("That password didn't work. Try again.")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Skip \(request.count == 1 ? "it" : "those \(request.count)")") {
                    controller.skipAdminItems()
                }
                .glass()
                Spacer()
                if checking { ProgressView().controlSize(.small) }
                Button("Authorize", action: authorize)
                    .glassProminent(.accentColor)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || checking)
            }
        }
        .padding(22)
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func authorize() {
        guard !password.isEmpty, !checking else { return }
        checking = true
        wrong = false
        Task {
            let ok = await controller.authorize(password: password)
            password = ""
            checking = false
            wrong = !ok
            if !ok { focused = true }
        }
    }
}
