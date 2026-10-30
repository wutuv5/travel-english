import SwiftUI
import Translation

/// G1/G2 真机验证版本。没有网络翻译回退或预存译文。
@MainActor
struct TranslationView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case chineseToEnglish = "中文 → 英文"
        case englishToChinese = "英文 → 中文"

        var id: String { rawValue }
        var source: Locale.Language {
            .init(identifier: self == .chineseToEnglish ? "zh-Hans" : "en")
        }
        var target: Locale.Language {
            .init(identifier: self == .chineseToEnglish ? "en" : "zh-Hans")
        }
    }

    private enum Operation: Equatable { case prepare, translate }
    private struct Request {
        let operation: Operation
        let text: String
        let direction: Direction
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var direction: Direction = .chineseToEnglish
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var status = "正在检查翻译资源…"
    @State private var message: String?
    @State private var resourceInstalled = false
    @State private var checking = false
    @State private var busy = false
    @State private var request: Request?
    @State private var configuration: TranslationSession.Configuration?
    @State private var configuredDirection: Direction?
    @State private var elapsed: Double?
    @State private var completedDirection: String?
    private let characterLimit = 2_000

    var body: some View {
        Form {
            Section {
                Label("旅前准备，从听懂和表达开始", systemImage: "airplane")
                    .font(.headline)
                Text("此版本先验证手机内的中英离线翻译。课程和口语练习将在验证通过后加入。")
                    .foregroundStyle(.secondary)
            }

            Section("翻译资源") {
                Text(status)
                    .accessibilityIdentifier("translation.resourceStatus")
                Button("检查资源状态", systemImage: "arrow.clockwise") {
                    Task { await refreshAvailability() }
                }
                .disabled(busy || checking)
                Button("准备当前方向的翻译资源", systemImage: "arrow.down.circle") {
                    begin(.prepare)
                }
                .disabled(busy || checking)
                Text("首次准备需联网，并按系统提示确认下载。准备后请开启飞行模式，重新打开应用验证；另一方向也需检查。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("输入内容") {
                Picker("翻译方向", selection: $direction) {
                    ForEach(Direction.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .disabled(busy || checking)
                TextEditor(text: $sourceText)
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .accessibilityLabel("待翻译文本")
                    .accessibilityIdentifier("translation.input")
                    .disabled(busy)
                Text("\(sourceText.count) / \(characterLimit) 字符")
                    .font(.caption)
                    .foregroundStyle(sourceText.count > characterLimit ? Color.red : Color.secondary)
                Button("翻译", systemImage: "character.bubble") {
                    begin(.translate)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || checking || trimmedText.isEmpty || sourceText.count > characterLimit || !resourceInstalled)
                .accessibilityIdentifier("translation.submit")
                if busy {
                    ProgressView("正在处理，请稍候…")
                }
            }

            if let message {
                Section("提示") {
                    Text(message).foregroundStyle(.red)
                }
            }

            if !translatedText.isEmpty {
                Section("译文") {
                    if let completedDirection {
                        Text(completedDirection).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(translatedText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("translation.output")
                    ShareLink(item: translatedText) {
                        Label("分享译文", systemImage: "square.and.arrow.up")
                    }
                    if let elapsed {
                        Text("本次处理耗时 \(elapsed, specifier: "%.2f") 秒")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("离线使用检查") {
                Text("1. 准备中英资源并分别检查两个方向。\n2. 开启飞行模式，关闭 Wi-Fi。\n3. 强制退出后重开，输入未使用过的新句子。\n4. 分别完成中译英、英译中。")
                Text("免费签名到期后，整个应用（包括离线翻译）都无法打开。出发前请在电脑上刷新签名并核对剩余有效期。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("旅前英语")
        .task { await refreshAvailability() }
        .onChange(of: sourceText) { _, _ in
            translatedText = ""
            elapsed = nil
            message = nil
        }
        .onChange(of: direction) { _, _ in
            translatedText = ""
            message = nil
            elapsed = nil
            resourceInstalled = false
            Task { await refreshAvailability() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !busy {
                Task { await refreshAvailability() }
            }
        }
        .translationTask(configuration) { session in
            guard let request else { return }
            await perform(request, session: session)
        }
    }

    private var trimmedText: String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func begin(_ operation: Operation) {
        guard !busy, !checking else { return }
        guard operation == .prepare || (!trimmedText.isEmpty && sourceText.count <= characterLimit) else { return }
        busy = true
        message = nil
        translatedText = ""
        elapsed = nil
        request = Request(operation: operation, text: trimmedText, direction: direction)
        if configuration != nil && configuredDirection == direction {
            configuration?.invalidate()
        } else {
            configuration = .init(source: direction.source, target: direction.target)
            configuredDirection = direction
        }
    }

    private func perform(_ request: Request, session: TranslationSession) async {
        let started = Date()
        defer { busy = false }
        do {
            if request.operation == .prepare {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                await refreshAvailability()
            } else {
                // 即使 UI 上一次检查为就绪，仍在调用前重新核实资源。
                let availability = await LanguageAvailability().status(
                    from: request.direction.source, to: request.direction.target
                )
                guard availability == .installed else {
                    resourceInstalled = false
                    message = "当前资源未准备好，请联网准备后再翻译。"
                    await refreshAvailability()
                    return
                }
                let response = try await session.translate(request.text)
                try Task.checkCancellation()
                translatedText = response.targetText
                completedDirection = request.direction.rawValue
                elapsed = Date().timeIntervalSince(started)
            }
        } catch is CancellationError {
            message = "操作已中断，可重新尝试。"
        } catch {
            message = "操作未完成，请检查翻译资源后重试。系统信息：\(error.localizedDescription)"
            await refreshAvailability()
        }
    }

    private func refreshAvailability() async {
        guard !checking else { return }
        checking = true
        let checkedDirection = direction
        let availability = await LanguageAvailability().status(from: checkedDirection.source, to: checkedDirection.target)
        defer { checking = false }
        guard checkedDirection == direction else { return }
        resourceInstalled = availability == .installed
        switch availability {
        case .installed:
            status = "\(checkedDirection.rawValue)：资源已安装，请进行飞行模式验证。"
        case .supported:
            status = "\(checkedDirection.rawValue)：需要先准备翻译资源。"
        case .unsupported:
            status = "此设备或系统暂不支持当前语言组合。"
        @unknown default:
            status = "无法确认资源状态，请重试。"
        }
    }
}
