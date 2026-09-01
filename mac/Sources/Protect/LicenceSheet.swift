import SwiftUI
import ProtectCore

/// Entering a key bought from the store.
///
/// ⚠️ A KEY IS PASTED, NOT TYPED. It arrives in an email as a long opaque
/// string, so the field is wide, accepts a paste of the whole thing including
/// stray whitespace, and never validates by shape beyond "long enough" — a
/// store can change its key format and this must not start rejecting customers.
struct LicenceSheet: View {
    @ObservedObject var model: Model
    @State private var key = ""
    @State private var email = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Activate Protect+")
                .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
            Text("Paste the licence key from your purchase email. It is stored on this Mac only, readable by your account alone.")
                .font(.system(size: FontSize.small))
                .foregroundStyle(Ink.secondary())
                .fixedSize(horizontal: false, vertical: true)

            TextField("Licence key", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: FontSize.small, design: .monospaced))
            TextField("Email on the purchase (optional)", text: $email)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: FontSize.small))

            if let error = model.licenceError {
                Text(error)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(Ink.critical)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.md) {
                Button {
                    if let url = URL(string: Store.checkout) { NSWorkspace.shared.open(url) }
                } label: {
                    Text("Buy a subscription")
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(Ink.accent.opacity(Dim.strong))
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Cancel") { model.showingLicenceSheet = false; model.licenceError = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.secondary())
                Button {
                    model.activate(key: key, email: email.isEmpty ? nil : email)
                } label: {
                    Text("Activate")
                        .font(.system(size: FontSize.small, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.navy)
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                        .primaryAction()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.xxl)
        .frame(width: 460)
        .background(Palette.deep)
    }
}
