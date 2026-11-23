import BandcampKit
import SwiftUI

/// Asks for the Bandcamp identity cookie, as the command line does on the terminal.
struct IdentitySheet: View {
    let reason: PromptReason
    let submit: (String?) -> Void
    @State private var cookie = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(reason == .rejected ? "Bandcamp Rejected the Saved Cookie" : "Connect to Bandcamp")
                .font(.title2.bold())
            Text(reason == .rejected
                ? "It has probably expired. Bandcamp Sync uses your browser's Bandcamp session cookie; paste a fresh one."
                : "Bandcamp Sync uses your browser's Bandcamp session cookie. To find it:")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(Credentials.steps.enumerated()), id: \.offset) { number, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(number + 1).").monospacedDigit()
                        Text(.init(step))
                    }
                }
            }
            .foregroundStyle(.secondary)
            SecureField("identity cookie", text: $cookie)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !cookie.isEmpty { submit(cookie) } }
            Text("It's saved to \((Credentials().fileURL.path as NSString).abbreviatingWithTildeInPath), where the command line finds it too.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { submit(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") { submit(cookie) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
