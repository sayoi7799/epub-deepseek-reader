import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderViewModel

    init(book: Book, library: LibraryStore, settings: SettingsStore, engine: TranslationEngine) {
        _model = State(
            initialValue: ReaderViewModel(book: book, library: library, settings: settings, engine: engine)
        )
    }

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .bottom) {
            model.appearance.theme.backgroundColor
                .ignoresSafeArea()

            GeometryReader { proxy in
                ReaderWebView(
                    html: model.html,
                    reloadToken: model.reloadToken,
                    fontSize: model.appearance.fontSize,
                    lineHeight: model.appearance.lineHeight,
                    controller: model.webController,
                    onMessage: { message in model.handle(message) }
                )
                .overlay(alignment: .topLeading) {
                    selectionPill(proxy: proxy)
                }
                .overlay {
                    statusOverlay
                }
            }

            if let session = model.session {
                TranslationCard(
                    session: session,
                    onClose: { model.closeSession() },
                    onRetry: { model.retryCurrent() },
                    onRefine: { model.refineCurrent() },
                    onStop: { model.stopCurrent() },
                    onInsert: { model.insertCurrentTranslation() },
                    onCopy: { model.copyCurrentTranslation() },
                    onStyleChange: { style in model.changeStyle(style) }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.session?.id)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(model.chapterTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.progressText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    model.showChapterList = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                Button {
                    model.showReaderSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            chapterBar
        }
        .sheet(isPresented: $model.showChapterList) {
            ChapterListSheet(book: model.book, currentIndex: model.chapterIndex) { index in
                model.goToChapter(index)
            }
        }
        .sheet(isPresented: $model.showReaderSettings) {
            ReaderSettingsSheet()
        }
        .task {
            await model.loadInitialChapter()
        }
        .onDisappear {
            model.persistProgress()
        }
    }

    // MARK: - 子视图

    private var chapterBar: some View {
        HStack {
            Button {
                model.goPrevious()
            } label: {
                Label("上一章", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
            }
            .disabled(!model.hasPreviousChapter)

            Spacer()

            Text(model.progressText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.goNext()
            } label: {
                Label("下一章", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
            }
            .disabled(!model.hasNextChapter)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func selectionPill(proxy: GeometryProxy) -> some View {
        if let selection = model.selection, model.session == nil {
            let availableWidth = max(80, proxy.size.width - 170)
            let x = min(max(selection.rect.minX, 10), availableWidth + 10)
            let y = max(8, selection.rect.minY - 46)

            Button {
                model.startTranslation(for: selection)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "character.book.closed")
                    Text("翻译选中的 \(selection.text.count) 字")
                }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            .offset(x: x, y: y)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let message = model.loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                Button("重新加载") {
                    Task { await model.loadChapter() }
                }
                .buttonStyle(.bordered)
            }
            .padding(28)
        } else if model.isLoading && model.html.isEmpty {
            ProgressView()
                .controlSize(.large)
        }
    }
}
