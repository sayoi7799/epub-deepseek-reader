import SwiftUI
import Foundation
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static var epubDocument: UTType {
        UTType(filenameExtension: "epub") ?? UTType("org.idpf.epub-container") ?? .data
    }
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var router

    @State private var isImporting = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 18)]

    var body: some View {
        ScrollView {
            if library.books.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(library.books) { book in
                        NavigationLink(value: book) {
                            bookCard(book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task { await openBook(book) }
                            } label: {
                                Label("开始阅读", systemImage: "book")
                            }
                            Button(role: .destructive) {
                                library.delete(book)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("书架")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImporting = true
                } label: {
                    Label("导入 EPUB", systemImage: "plus")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if case .importing(let name) = library.importState {
                importingBanner(name: name)
            }
        }
        .refreshable {
            await library.importInboxIfNeeded()
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.epubDocument],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await importFiles(urls) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: library.lastErrorMessage) { _, newValue in
            guard let newValue else { return }
            errorMessage = newValue
            library.lastErrorMessage = nil
        }
        .alert("提示", isPresented: alertBinding) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in if !newValue { errorMessage = nil } }
        )
    }

    // MARK: - 子视图

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("还没有书")
                .font(.title3.weight(.semibold))
            Text("点右上角 + 导入 EPUB 文件；\n也可以把 EPUB 放进 Files 里的「译读」文件夹，回到 App 会自动导入。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !settings.isConfigured {
                Button {
                    router.selectedTab = .settings
                } label: {
                    Label("先去填写 DeepSeek API Key", systemImage: "key")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 110)
        .padding(.bottom, 60)
    }

    private func bookCard(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(book: book, imageURL: library.coverImageURL(for: book))
            Text(book.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(book.authorDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: book.totalProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
            Text("\(Int(book.totalProgress * 100))% · \(book.chapters.count) 章")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func importingBanner(name: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在解析 \(name)")
                .font(.footnote)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.06)))
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 动作

    private func importFiles(_ urls: [URL]) async {
        for url in urls {
            do {
                let book = try await library.importBook(from: url)
                await openBook(book)
            } catch {
                errorMessage = "导入「\(url.lastPathComponent)」失败：\(error.localizedDescription)"
            }
        }
    }

    private func openBook(_ book: Book) async {
        if !settings.isConfigured {
            router.selectedTab = .library
        }
        library.markOpened(book)
        router.open(book)
    }
}
