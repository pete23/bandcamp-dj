import AppKit
import BandcampKit
import SwiftUI
import SyncKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showAll") private var showAll = false
    @State private var selection: Set<Row.ID> = []

    var body: some View {
        let rows = showAll ? model.rows : model.notInMusic
        content(rows)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $showAll) {
                        Text("Not in Music").tag(false)
                        Text("All Recent").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem {
                    Button { Task { await model.check() } } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .help("Check Bandcamp and your Music library again")
                    .disabled(model.phase != .idle)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.sync() } } label: {
                        Label("Sync", systemImage: "arrow.down.circle")
                    }
                    .help("Download purchases that aren't in Music and add them to it")
                    .disabled(!model.canSync)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
            .sheet(isPresented: Binding(
                get: { model.identityRequest != nil },
                set: { if !$0 { model.answerIdentity(nil) } }
            )) {
                IdentitySheet(reason: model.identityRequest ?? .missing, submit: model.answerIdentity)
            }
            .task { await model.check() }
    }

    @ViewBuilder
    private func content(_ rows: [Row]) -> some View {
        if rows.isEmpty {
            if model.phase == .checking {
                ProgressView("Checking Bandcamp and your Music library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error {
                ContentUnavailableView {
                    Label("Couldn't Check", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.check() } }
                }
            } else if model.checkedAt == nil {
                ContentUnavailableView {
                    Label("Not Connected", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Connect to Bandcamp to see your recent purchases.")
                } actions: {
                    Button("Connect…") { Task { await model.check() } }
                }
            } else {
                ContentUnavailableView(
                    "Everything's in Music", systemImage: "checkmark.circle",
                    description: Text("All of your last \(model.rows.count) purchases are in your library."))
            }
        } else {
            table(rows)
        }
    }

    private func table(_ rows: [Row]) -> some View {
        Table(rows, selection: $selection) {
            TableColumn("Artist") { Text($0.item.purchase.artist) }
            TableColumn("Title") { Text($0.item.purchase.title) }
            TableColumn("Purchased") { Text($0.item.purchase.purchasedAt, format: .dateTime.day().month().year()) }
                .width(min: 80, ideal: 100, max: 120)
            TableColumn("Status") { StatusCell(row: $0) }
                .width(min: 150, ideal: 220)
        }
        .contextMenu(forSelectionType: Row.ID.self) { ids in
            let chosen = model.rows.filter { ids.contains($0.id) }
            let folders = chosen.compactMap(model.folder(for:))
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(folders) }
                .disabled(folders.isEmpty)
            let links = chosen.compactMap(\.item.purchase.itemURL)
            Button("Open on Bandcamp") { links.forEach { NSWorkspace.shared.open($0) } }
                .disabled(links.isEmpty)
        } primaryAction: { ids in
            for url in model.rows.filter({ ids.contains($0.id) }).compactMap(\.item.purchase.itemURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct StatusCell: View {
    let row: Row

    var body: some View {
        switch row.activity {
        case .queued:
            Text("Waiting").foregroundStyle(.secondary)
        case .downloading(.preparing):
            Text("Preparing…").foregroundStyle(.secondary)
        case .downloading(.downloading(let received, let expected)):
            if let expected, expected > 0 {
                ProgressView(value: Double(min(received, expected)), total: Double(expected))
                    .help("\(received.formatted(.byteCount(style: .file))) of \(expected.formatted(.byteCount(style: .file)))")
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        case .downloading(.unzipping):
            Text("Unzipping…").foregroundStyle(.secondary)
        case .importing:
            Text("Adding to Music…").foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(message)
        case nil:
            stage
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch row.item.stage {
        case .missing:
            Label("Not downloaded", systemImage: "circle.dashed").foregroundStyle(.secondary)
        case .downloaded:
            Label("Downloaded", systemImage: "arrow.down.circle")
        case .imported:
            Label("Imported", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .inMusic:
            Label("In Music", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help(row.item.stage.description)
        }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.phase != .idle { ProgressView().controlSize(.small) }
            if let error = model.error, !model.rows.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(summary).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var summary: String {
        switch model.phase {
        case .checking: return "Checking…"
        case .syncing:
            let busy = model.rows.filter { $0.activity != nil && $0.activity != .queued }
            if busy.contains(where: { $0.activity == .importing }) { return "Adding to Music…" }
            return busy.isEmpty ? "Syncing…" : "Downloading \(busy.count)…"
        case .idle:
            guard let checkedAt = model.checkedAt else { return "" }
            let missing = model.notInMusic.count
            let count = missing == 0
                ? "All of the last \(model.rows.count) purchases are in Music"
                : "\(missing) of the last \(model.rows.count) purchases aren't in Music"
            return count + " · checked \(checkedAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}
