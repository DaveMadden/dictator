import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
                Toggle("Remove filler words (um, uh…)", isOn: $store.removeFillers)
                Toggle("Spoken commands (\u{201C}new line\u{201D}, \u{201C}new paragraph\u{201D})", isOn: $store.spokenCommands)
            }
            Section {
                Toggle("Polish with local AI (requires Ollama)", isOn: $store.llmEnabled)
                TextField("Ollama model", text: $store.llmModel)
                Picker("Default tone", selection: $store.defaultTone) {
                    ForEach(SettingsStore.tones, id: \.self) { Text($0.capitalized) }
                }
                ForEach($store.appTones) { $appTone in
                    HStack(spacing: 8) {
                        TextField("App name contains…", text: $appTone.appContains)
                        Picker("", selection: $appTone.tone) {
                            ForEach(SettingsStore.tones, id: \.self) { Text($0.capitalized) }
                        }
                        .frame(width: 110)
                        Button {
                            store.appTones.removeAll { $0.id == appTone.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    store.appTones.append(.init(appContains: "", tone: store.defaultTone))
                } label: {
                    Label("Add per-app tone", systemImage: "plus")
                }
            } header: {
                Text("AI polish")
            } footer: {
                Text("Runs entirely on this Mac via Ollama on 127.0.0.1 — used only for dictations of 8+ words, and only when the Ollama server is running. Tone example: \u{201C}Slack\u{201D} → Casual.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Section {
                ForEach($store.replacements) { $replacement in
                    HStack(spacing: 8) {
                        TextField("Heard as…", text: $replacement.from)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Write as…", text: $replacement.to)
                        Button {
                            store.replacements.removeAll { $0.id == replacement.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    store.replacements.append(.init(from: "", to: ""))
                } label: {
                    Label("Add replacement", systemImage: "plus")
                }
            } header: {
                Text("Personal dictionary")
            } footer: {
                Text("Phrases the model mishears, mapped to how they should be written — e.g. \u{201C}git hub\u{201D} → \u{201C}GitHub\u{201D}. Case-insensitive, whole words only.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 400)
    }
}

struct HistoryView: View {
    let store: HistoryStore

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "mic.slash",
                    description: Text("Everything you dictate is stored only on this Mac.")
                )
            } else {
                List(store.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(Self.timeFormat.string(from: entry.date))
                            Text("·")
                            Text(entry.app)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Copy")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(entry.text)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
            Divider()
            HStack {
                Text("\(store.entries.count) dictations, stored locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History", role: .destructive) {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 460, minHeight: 380)
    }
}
