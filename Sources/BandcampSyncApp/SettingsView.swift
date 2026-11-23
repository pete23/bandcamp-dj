import AppKit
import BandcampKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Picker("Format", selection: $preferences.format) {
                ForEach(DownloadFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            LabeledContent("Download folder") {
                HStack {
                    Text(preferences.folder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(preferences.folder.path(percentEncoded: false))
                    Button("Choose…", action: chooseFolder)
                }
            }
            Stepper("Check the last \(preferences.limit) purchases", value: $preferences.limit, in: 10...500, step: 10)
            Stepper("Download \(preferences.parallel) at a time", value: $preferences.parallel, in: 1...12)
            Text("Unless Music's \"Copy files to Music Media folder\" setting is on, Music plays imported files from the download folder, so keep it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
        .onChange(of: preferences.folder) { try? model.restage() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.preferences.folder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { model.preferences.folder = url }
    }
}

extension DownloadFormat {
    var displayName: String {
        switch self {
        case .mp3320: "MP3 320"
        case .mp3V0: "MP3 V0"
        case .aacHi: "AAC"
        case .alac: "Apple Lossless"
        case .aiff: "AIFF"
        case .wav: "WAV"
        }
    }
}
