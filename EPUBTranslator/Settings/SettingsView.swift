import SwiftUI
import Foundation

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(TranslationCache.self) private var cache
    @Environment(HistoryStore.self) private var history
    @Environment(TranslationEngine.self) private var engine

    @State private var apiKeyDraft = ""
    @State private var keySaved = false
    @State private var connectionState = ConnectionState.idle
    @State private var showClearAlert = false

    private enum ConnectionState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            apiSection
            translationSection
            liveActivitySection
            readingSection
            dataSection
            aboutSection
        }
        .navigationTitle("设置")
        .onAppear {
            if apiKeyDraft.isEmpty {
                apiKeyDraft = settings.apiKey
            }
        }
        .alert("清空数据", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                cache.clear()
                history.deleteAll()
            }
        } message: {
            Text("会清空翻译缓存和全部译文记录，书架里的书不会删除。")
        }
    }

    // MARK: - 各分区

    private var apiSection: some View {
        @Bindable var settings = settings

        return Section {
            VStack(alignment: .leading, spacing: 10) {
                SecureField("sk-...", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .privacySensitive()
                    .onSubmit(saveKey)

                HStack {
                    Button("保存 API Key", action: saveKey)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    Button("测试连接") {
                        Task { await testConnection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(connectionState == .testing)

                    if keySaved {
                        Text("已保存")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                connectionBadge
            }
            .padding(.vertical, 4)

            TextField("接口地址", text: $settings.baseURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))

            Picker("模型", selection: $settings.model) {
                ForEach(DeepSeekModel.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            Text(settings.model.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("DeepSeek API")
        } footer: {
            Text("API Key 只保存在这台设备的钥匙串里。到 platform.deepseek.com 生成 Key；如果走中转服务，把接口地址改成你自己的地址即可，例如 https://your-proxy.com/v1。")
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch connectionState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("正在测试…").font(.caption).foregroundStyle(.secondary)
            }
        case .success(let message):
            Text("连接正常：\(message)")
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(2)
        case .failure(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    private var translationSection: some View {
        @Bindable var settings = settings

        return Section {
            Picker("默认风格", selection: $settings.defaultStyle) {
                ForEach(TranslationStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            Text(settings.defaultStyle.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("译为", selection: $settings.targetLanguage) {
                ForEach(TargetLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }

            HStack {
                Text("温度")
                Slider(value: $settings.temperature, in: 0...2, step: 0.1)
                Text(String(format: "%.1f", settings.temperature))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            Text("DeepSeek 官方建议翻译任务用 1.3，语气会更自然。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("最大输出", selection: $settings.maxTokens) {
                Text("不限制").tag(0)
                Text("1024").tag(1024)
                Text("2048").tag(2048)
                Text("4096").tag(4096)
            }

            Toggle("高质量模式（初稿 + 润色两遍）", isOn: $settings.highQuality)
            Toggle("流式输出（边翻边显示）", isOn: $settings.streaming)
            Toggle("把上下文一起发给模型", isOn: $settings.useBookContext)

            VStack(alignment: .leading, spacing: 6) {
                Text("额外要求（可选）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $settings.customInstruction)
                    .frame(minHeight: 72)
                    .font(.footnote)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                Text("例如：人名一律保留英文原名；对话不要用「」以外的引号。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("术语表（每行一条：原文=译文）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $settings.glossaryText)
                    .frame(minHeight: 90)
                    .font(.system(.footnote, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    )
            }
        } header: {
            Text("翻译偏好")
        }
    }

    private var readingSection: some View {
        @Bindable var settings = settings

        return Section("阅读交互") {
            Toggle("点按段落直接翻译", isOn: $settings.tapToTranslate)
            Toggle("选中文字后显示翻译按钮", isOn: $settings.selectToTranslate)
            Toggle("翻译完成后自动插入正文", isOn: $settings.autoInsertTranslation)
        }
    }

    private var liveActivitySection: some View {
        @Bindable var settings = settings

        return Section {
            Toggle("在灵动岛 / 锁屏显示实时译文", isOn: $settings.liveActivityEnabled)
            Text("翻译时把进度和译文推到灵动岛：紧凑状态显示最新几个字，长按展开可以看到原文和完整译文；点一下能跳回正在读的那本书。没有灵动岛的机型会在锁屏上显示同一张卡片。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("需要系统设置里允许「实时活动」；关掉这个开关就不会再创建 Live Activity。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } header: {
            Text("灵动岛 / 锁屏")
        }
    }

    private var dataSection: some View {
        Section {
            HStack {
                Text("翻译缓存")
                Spacer()
                Text("\(cache.count) 条")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("译文记录")
                Spacer()
                Text("\(history.records.count) 条")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("书架")
                Spacer()
                Text("\(library.books.count) 本")
                    .foregroundStyle(.secondary)
            }
            Button("清空缓存与译文记录") {
                showClearAlert = true
            }
            .foregroundStyle(.red)
        } header: {
            Text("数据")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: "1.0")
            Text("快捷指令：在「快捷指令」App 里搜索「译读」，可以把翻译能力接到 Siri、Spotlight 或自动化流程里。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("阅读时：点按段落 = 整段翻译；长按选中句子 = 只翻译选中的部分；译文卡片里的「插入正文」会把译文放到原文下面，形成对照阅读。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("关于")
        }
    }

    // MARK: - 动作

    private func saveKey() {
        settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        keySaved = true
        connectionState = .idle
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            keySaved = false
        }
    }

    private func testConnection() async {
        saveKey()
        connectionState = .testing
        do {
            let result = try await engine.testConnection()
            connectionState = .success(result)
        } catch {
            connectionState = .failure(error.localizedDescription)
        }
    }
}
