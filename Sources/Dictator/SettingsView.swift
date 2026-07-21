import AppKit
import DictatorLLM
import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            modelsSection
            Section("General") {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
                Toggle("Remove filler words (um, uh…)", isOn: $store.removeFillers)
                Toggle("Spoken commands (\u{201C}new line\u{201D}, \u{201C}new paragraph\u{201D})", isOn: $store.spokenCommands)
            }
            Section {
                Toggle("Use a local AI model for polish (experimental, off by default)", isOn: $store.llmEnabled)
                HStack(spacing: 8) {
                    TextField("Model file or folder (blank = App Support/Dictator/llm)", text: $store.llmModelPath)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.message = "Pick a GGUF model file, or a folder containing one"
                        if panel.runModal() == .OK, let url = panel.url {
                            store.llmModelPath = url.path
                        }
                    }
                }
                TextField("Ollama model (fallback engine)", text: $store.llmModel)
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
                Text("Runs entirely on this Mac — dictations of 8+ words only. Point it at any GGUF chat model you already have (a file, or a folder of models — LM Studio's folder works as-is); a running Ollama server is the fallback engine. Tone example: \u{201C}Slack\u{201D} → Casual.")
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

    @ViewBuilder
    private var modelsSection: some View {
        let speech = ModelInventory.speechStatus()
        let llmItems = ModelInventory.llmItems()
        Section {
            HStack(spacing: 8) {
                Image(systemName: speech.found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(speech.found ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech recognition")
                    Text(speech.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                TextField("Speech models folder (blank = standard location)", text: $store.speechModelDir)
                Button("Choose…") {
                    choosePath(directoriesOnly: true) { store.speechModelDir = $0 }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: llmItems.contains(where: \.active) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(llmItems.contains(where: \.active) ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI polish")
                    if llmItems.isEmpty {
                        Text("No GGUF models found — drop one in \(ModelInventory.abbreviate(LlamaEngine.modelsDirectory)) or point below")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Click a model to make it active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(llmItems) { item in
                Button {
                    store.llmModelPath = item.url.path
                } label: {
                    HStack {
                        Image(systemName: item.active ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(item.active ? .green : .secondary)
                        Text(item.name)
                        Spacer()
                        Text(item.sizeText)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                TextField("Polish model: GGUF file or folder (blank = standard location)", text: $store.llmModelPath)
                Button("Choose…") {
                    choosePath(directoriesOnly: false) { store.llmModelPath = $0 }
                }
            }
            Toggle("Allow downloading missing speech models (Hugging Face)", isOn: $store.allowModelDownload)
        } header: {
            Text("Models")
        } footer: {
            Text("With downloads off (the default), Dictator only loads models from these paths and never touches the network — a missing model is an error, not a download.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func choosePath(directoriesOnly: Bool, assign: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = !directoriesOnly
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            assign(url.path)
        }
    }
}

struct HistoryView: View {
    let store: HistoryStore
    /// Called with the chosen entry's text; the host dismisses the window,
    /// returns focus to the previous app, and pastes.
    var onPaste: (String) -> Void
    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var filtered: [HistoryStore.Entry] {
        let all = Array(store.entries.reversed())
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.text.localizedCaseInsensitiveContains(needle)
                || $0.app.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Spotlight semantics: the top result is implicitly selected until the
    /// arrows move the highlight.
    private var selectedEntry: HistoryStore.Entry? {
        if let selectedID, let match = filtered.first(where: { $0.id == selectedID }) {
            return match
        }
        return filtered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search dictations", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { pasteSelection() }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
            }
            .padding(8)
            Divider()
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "mic.slash",
                    description: Text("Everything you dictate is stored only on this Mac.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollViewReader { proxy in
                    List(filtered) { entry in
                        row(entry)
                            .id(entry.id)
                            .listRowBackground(
                                entry.id == selectedEntry?.id
                                    ? Color.accentColor.opacity(0.16)
                                    : nil
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onPaste(entry.text) }
                            .onTapGesture { selectedID = entry.id }
                    }
                    .onChange(of: selectedID) { _, newValue in
                        if let newValue { proxy.scrollTo(newValue) }
                    }
                }
            }
            Divider()
            HStack {
                Text("\(store.entries.count) dictations · ↑↓ select · ⏎ paste · double-click paste")
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
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selectedID = nil }
    }

    @ViewBuilder
    private func row(_ entry: HistoryStore.Entry) -> some View {
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

    private func move(_ delta: Int) {
        let ids = filtered.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selectedEntry.flatMap { entry in ids.firstIndex(of: entry.id) } ?? 0
        selectedID = ids[min(max(0, current + delta), ids.count - 1)]
    }

    private func pasteSelection() {
        guard let entry = selectedEntry else { return }
        onPaste(entry.text)
    }
}
