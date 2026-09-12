import ActivityKit
import Foundation

/// 驱动灵动岛 / 锁屏上的实时译文。
///
/// 系统对 Live Activity 的刷新有频率限制，所以这里做了一层节流：
/// 流式输出期间最多约 0.9 秒推一次，收尾时再强制推一次最终结果。
@MainActor
final class LiveActivityController {
    private(set) var activity: Activity<TranslationActivityAttributes>?
    private var current: TranslationActivityAttributes.ContentState?
    private var lastPush = Date.distantPast
    private var flushTask: Task<Void, Never>?
    private let minimumInterval: TimeInterval = 0.9

    var isEnabledBySystem: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool { activity != nil }

    // MARK: - 生命周期

    func begin(sourceText: String, bookTitle: String, chapterTitle: String, bookID: String, styleTitle: String) {
        guard isEnabledBySystem else { return }

        flushTask?.cancel()
        flushTask = nil

        let attributes = TranslationActivityAttributes(
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            bookID: bookID
        )
        let state = TranslationActivityAttributes.ContentState(
            sourceText: sourceText,
            translatedText: "",
            phase: .preparing,
            styleTitle: styleTitle,
            message: nil,
            updatedAt: Date()
        )

        let previous = activity
        activity = nil
        current = state
        lastPush = Date()

        Task { [weak self] in
            if let previous {
                await previous.end(nil, dismissalPolicy: .immediate)
            }
            for stale in Activity<TranslationActivityAttributes>.activities where stale.id != previous?.id {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
            do {
                let requested = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                self?.activity = requested
                if let latest = self?.current {
                    self?.push(latest)
                }
            } catch {
                self?.activity = nil
            }
        }
    }

    func update(
        translated: String? = nil,
        phase: TranslationActivityAttributes.ContentState.Phase? = nil,
        message: String? = nil,
        force: Bool = false
    ) {
        guard var state = current else { return }
        if let translated { state.translatedText = translated }
        if let phase { state.phase = phase }
        if let message { state.message = message }
        state.updatedAt = Date()
        current = state

        guard force || Date().timeIntervalSince(lastPush) >= minimumInterval else {
            scheduleFlush()
            return
        }
        push(state)
    }

    /// 翻译完成：推最终结果，然后让卡片在锁屏上多留一会儿。
    func finish(translated: String) {
        guard var state = current else { return }
        state.translatedText = translated
        state.phase = .finished
        state.message = nil
        state.updatedAt = Date()

        flushTask?.cancel()
        flushTask = nil
        let activity = self.activity
        self.activity = nil
        current = nil
        guard let activity else { return }
        lastPush = Date()

        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15)))
        }
    }

    func fail(message: String) {
        guard var state = current else { return }
        state.phase = .failed
        state.message = message
        state.updatedAt = Date()

        flushTask?.cancel()
        flushTask = nil
        let activity = self.activity
        self.activity = nil
        current = nil
        guard let activity else { return }
        lastPush = Date()

        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(20)))
        }
    }

    func stop() {
        flushTask?.cancel()
        flushTask = nil
        let activity = self.activity
        self.activity = nil
        current = nil
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// App 启动时清理上一次运行遗留下来的活动。
    func endAllStale() {
        Task {
            for activity in Activity<TranslationActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - 内部

    private func push(_ state: TranslationActivityAttributes.ContentState) {
        guard let activity else { return }
        lastPush = Date()
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            guard let state = self.current else { return }
            if Date().timeIntervalSince(self.lastPush) >= self.minimumInterval {
                self.push(state)
            } else {
                self.scheduleFlush()
            }
        }
    }
}
