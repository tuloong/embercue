import EmbercueCore
import SwiftUI

public struct ItemEditorView: View {
    let item: EmbercueCore.LibraryItem
    let save: (String) -> Bool
    let close: () -> Void
    @State private var draft: String
    @State private var message: String?

    public init(item: EmbercueCore.LibraryItem, save: @escaping (String) -> Bool, close: @escaping () -> Void) {
        self.item = item
        self.save = save
        self.close = close
        _draft = State(initialValue: item.text)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit note").font(.headline)
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", action: close)
                Button("Save") {
                    if save(draft) { close() } else { message = "Embercue could not save this edit. Your draft is still here." }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 280)
    }
}
