import SwiftUI

struct ReaderSettingsSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("字号与行距") {
                    HStack {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.appearance.fontSize, in: ReaderAppearance.fontSizeRange, step: 1)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "arrow.up.and.down")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.appearance.lineHeight, in: ReaderAppearance.lineHeightRange, step: 0.05)
                    }
                    HStack {
                        Text("左右留白")
                        Slider(value: $settings.appearance.horizontalPadding, in: 12...44, step: 2)
                    }
                    Text("当前字号 \(Int(settings.appearance.fontSize)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("主题") {
                    Picker("主题", selection: $settings.appearance.theme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("字体") {
                    Picker("字体", selection: $settings.appearance.font) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.title).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("首行缩进两格", isOn: $settings.appearance.firstLineIndent)
                }

                Section("翻译交互") {
                    Toggle("点按段落直接翻译", isOn: $settings.tapToTranslate)
                    Toggle("选中文字后显示翻译按钮", isOn: $settings.selectToTranslate)
                    Toggle("翻译完成后自动插入正文", isOn: $settings.autoInsertTranslation)
                    Picker("默认风格", selection: $settings.defaultStyle) {
                        ForEach(TranslationStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
