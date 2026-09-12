import SwiftUI
import Foundation
import UIKit

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history

    @State private var searchText = ""
    @State private var favoritesOnly = false

    private var filtered: [TranslationRecord] {
        history.records.filter { record in
            if favoritesOnly && !record.isFavorite { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return record.sourceText.localizedCaseInsensitiveContains(query)
                || record.translatedText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if history.records.isEmpty {
                ContentUnavailableView(
                    "还没有译文",
                    systemImage: "text.book.closed",
                    description: Text("在阅读时点按段落或选中句子，翻译过的内容会自动收在这里。")
                )
            } else {
                list
            }
        }
        .navigationTitle("译文")
        .searchable(text: $searchText, prompt: "搜索原文或译文")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .accessibilityLabel(favoritesOnly ? "显示全部" : "只看收藏")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: history.exportMarkdown()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(history.records.isEmpty)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { record in
                recordRow(record)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            history.delete(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            history.toggleFavorite(record)
                        } label: {
                            Label(record.isFavorite ? "取消收藏" : "收藏",
                                  systemImage: record.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = record.translatedText
                        } label: {
                            Label("复制译文", systemImage: "doc.on.doc")
                        }
                        Button {
                            UIPasteboard.general.string = record.sourceText
                        } label: {
                            Label("复制原文", systemImage: "doc.on.clipboard")
                        }
                        Button(role: .destructive) {
                            history.delete(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private func recordRow(_ record: TranslationRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if record.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(record.contextLine.isEmpty ? record.style.title : record.contextLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(record.sourceText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Text(record.translatedText)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(12)
        }
        .padding(.vertical, 4)
    }
}
