import SwiftUI
import UniformTypeIdentifiers

/// Plain-text editor for one of the five project files.
///
/// The keyboard is the iPhone keyboard — for long pastes, Import from the
/// Files app is usually faster than typing. Every keystroke saves to
/// Documents/YewBuilder/ immediately, so nothing is lost if the app closes.
struct FileEditorView: View {
    let file: ProjectFile
    @EnvironmentObject private var store: ProjectStore
    @State private var text: String = ""
    @State private var showImporter = false
    @State private var showResetConfirm = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(size: 14, design: .monospaced))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(8)
                .onChange(of: text) { _, newValue in
                    store.setContent(newValue, for: file)
                }

            HStack {
                Text("\(text.count) characters · \(text.components(separatedBy: "\n").count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let importError {
                    Text(importError).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(file.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Import") { showImporter = true }
                Menu("More") {
                    Button("Load starter template") {
                        text = Templates.content(for: file.rawValue)
                    }
                    Button("Reset to starter", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .sourceCode],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let imported = try? String(contentsOf: url, encoding: .utf8) {
                    text = imported
                    importError = nil
                } else {
                    importError = "Could not read that file as text."
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Reset \(file.rawValue)?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                store.resetFile(file)
                text = store.content(for: file)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces what you typed with the starter template.")
        }
        .onAppear { text = store.content(for: file) }
    }
}
