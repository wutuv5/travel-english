import SwiftUI
import Translation

/// A fresh presentation owns an immutable request and its session.
@MainActor
struct TranslationTaskView: View {
    let request: TranslationRequest
    let onTranslation: (String, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: TranslationSession.Configuration
    @State private var started = false
    @State private var finished = false
    @State private var succeeded = false
    @State private var detail = "正在启动系统翻译…"
    @State private var diagnostic: String?

    init(request: TranslationRequest, onTranslation: @escaping (String, Double) -> Void) {
        self.request = request
        self.onTranslation = onTranslation
        _configuration = State(initialValue: .init(source: request.direction.source, target: request.direction.target))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: succeeded ? "checkmark.circle.fill" : "character.bubble.fill")
                    .font(.system(size: 64)).foregroundStyle(succeeded ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                Text(request.operation == .prepare ? "准备离线翻译" : "正在翻译")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(request.direction.rawValue).foregroundStyle(.secondary)
                if !finished { ProgressView() }
                Text(detail).multilineTextAlignment(.center).accessibilityIdentifier("translation.operationStatus")
                if let diagnostic {
                    Text(diagnostic).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if finished && !succeeded {
                    Button("重试") {
                        finished = false; started = false; diagnostic = nil
                        detail = "正在重新启动系统翻译…"
                        configuration.invalidate()
                    }.buttonStyle(.borderedProminent)
                }
                Button(finished ? "返回翻译页" : "取消并返回") { dismiss() }
                    .buttonStyle(.bordered).accessibilityIdentifier("translation.closeOperation")
            }
            .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("中英翻译").navigationBarTitleDisplayMode(.inline)
            .translationTask(configuration) { @MainActor session in
                #if targetEnvironment(simulator)
                finished = true
                detail = "模拟器仅检查界面交互。系统翻译需在真实 iPhone 上验证。"
                return
                #else
                started = true
                detail = request.operation == .prepare
                    ? "正在准备语言资源。如系统弹出下载提示，请确认并等待完成。"
                    : "正在处理文本。若资源尚未下载，请按系统提示准备。"
                let start = Date()
                do {
                    if request.operation == .prepare {
                        try await session.prepareTranslation()
                        try Task.checkCancellation()
                        succeeded = true
                        detail = "系统已完成资源准备请求。返回后会重新检查状态；请继续做一次飞行模式翻译测试。"
                    } else {
                        let response = try await session.translate(request.text)
                        try Task.checkCancellation()
                        onTranslation(response.targetText, Date().timeIntervalSince(start))
                        succeeded = true
                        dismiss()
                    }
                } catch is CancellationError {
                    detail = "操作已取消，可返回后重新尝试。"
                } catch {
                    detail = "系统未能完成操作。请确认首次准备时已联网，或重试。"
                    let error = error as NSError
                    diagnostic = "\(error.domain) · \(error.code)\n\(error.localizedDescription)"
                }
                finished = true
                #endif
            }
            .task {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, !finished else { return }
                detail = !started
                    ? "系统翻译尚未启动。请返回重试；若持续出现，请记录系统版本并反馈。"
                    : "仍在等待系统处理或下载。请检查是否有系统确认弹窗，也可取消后重试。"
            }
        }
    }
}
