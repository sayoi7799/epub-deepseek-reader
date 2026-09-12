import ActivityKit
import SwiftUI
import WidgetKit

/// 把实时译文显示在灵动岛和锁屏上。
struct TranslationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranslationActivityAttributes.self) { context in
            LockScreenTranslationView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.62))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "character.book.closed.fill")
                            .font(.caption2)
                        Text("译读")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.tint)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 5) {
                        if context.state.isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(context.state.phaseTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.sourceText.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.state.displayText)
                            .font(.footnote)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)

                        if let message = context.state.message {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        } else if !context.attributes.chapterTitle.isEmpty {
                            Text(context.attributes.chapterTitle)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "character.book.closed.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(TranslationLiveActivity.compactText(for: context.state))
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 56)
                    .foregroundStyle(context.state.isBusy ? Color.secondary : Color.primary)
            } minimal: {
                Image(systemName: context.state.phase == .finished ? "checkmark" : "character.book.closed.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
            .keylineTint(.accentColor)
            .widgetURL(TranslationLiveActivity.deepLink(for: context.attributes))
        }
    }

    /// 紧凑区域很窄：翻译中显示最新几个字（有"在动"的感觉），完成后显示开头。
    static func compactText(for state: TranslationActivityAttributes.ContentState) -> String {
        let text = state.displayText.replacingOccurrences(of: "\n", with: " ")
        guard text != "…" else { return "…" }
        if state.isBusy {
            return "…" + String(text.suffix(5))
        }
        return String(text.prefix(7))
    }

    static func deepLink(for attributes: TranslationActivityAttributes) -> URL? {
        guard !attributes.bookID.isEmpty else { return URL(string: "epubtranslator://open") }
        return URL(string: "epubtranslator://book/\(attributes.bookID)")
    }
}

private struct LockScreenTranslationView: View {
    let context: ActivityViewContext<TranslationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "character.book.closed.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(context.attributes.bookTitle.isEmpty ? "译读" : context.attributes.bookTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if context.state.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(context.state.phaseTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(context.state.sourceText.replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(context.state.displayText)
                .font(.subheadline)
                .lineLimit(4)
                .multilineTextAlignment(.leading)

            if let message = context.state.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if !context.attributes.chapterTitle.isEmpty {
                Text(context.state.styleTitle + " · " + context.attributes.chapterTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
