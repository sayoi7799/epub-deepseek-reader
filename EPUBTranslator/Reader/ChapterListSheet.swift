import SwiftUI

struct ChapterListSheet: View {
    let book: Book
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(book.chapters) { chapter in
                Button {
                    onSelect(chapter.order)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                            .foregroundStyle(chapter.order == currentIndex ? Color.accentColor : Color.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if chapter.order == currentIndex {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
