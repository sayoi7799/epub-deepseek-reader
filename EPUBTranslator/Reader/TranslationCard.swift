import SwiftUI

struct TranslationCard: View {
    let session: TranslationSession
    let onClose: () -> Void
    let onRetry: () -> Void
    let onRefine: () -> Void
    let onStop: () -> Void
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onStyleChange: (TranslationStyle) -> Void

    @State private var isSourceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sourceSection
            Divider()
            translationSection
            if let message = session.errorMessage {
                errorSection(message)
            }
            actionRow
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height > 70 {
                        onClose()
                    }
                }
        )
    }

    // MARK: - 组件

    private var header: some View {
        HStack(spacing: 10) {
            Text("译")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Menu {
                ForEach(TranslationStyle.allCases) { style in
                    Button {
                        onStyleChange(style)
                    } label: {
                        Label(style.title, systemImage: style.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(session.style.title)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
            }

            Spacer()

            statusBadge

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("关闭译文")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if session.usedCache {
            Text("缓存")
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        } else if session.isBusy {
            ProgressView()
                .controlSize(.mini)
        } else if !session.modelName.isEmpty {
            Text(session.modelName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isSourceExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.source)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isSourceExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isSourceExpanded ? "收起原文" : "展开原文")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var translationSection: some View {
        if session.hasContent {
            ScrollView {
                Text(session.text)
                    .font(.system(size: 17))
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            .scrollBounceBehavior(.basedOnSize)
        } else if session.errorMessage == nil {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(session.phase == .refining ? "正在润色…" : "正在翻译…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
            if message.contains("API Key") {
                Text("到「设置」标签页填入 DeepSeek API Key 之后就能用了。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if session.isBusy {
                Button(action: onStop) {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: onCopy) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.hasContent)

                Button(action: onRefine) {
                    Label("润色", systemImage: "wand.and.sparkles")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.hasContent)
            }

            Spacer()

            if session.errorMessage != nil {
                Button(action: onRetry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button(action: onInsert) {
                    Label(session.insertedInReader ? "已插入" : "插入正文", systemImage: "text.insert")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!session.hasContent)
            }
        }
    }
}
