import SwiftUI
import Translation

enum TranslationDirection: String, CaseIterable, Identifiable {
    case chineseToEnglish = "中译英", englishToChinese = "英译中"
    var id: String { rawValue }
    var source: Locale.Language { .init(identifier: self == .chineseToEnglish ? "zh-Hans" : "en") }
    var target: Locale.Language { .init(identifier: self == .chineseToEnglish ? "en" : "zh-Hans") }
}

struct TranslationRequest: Identifiable {
    enum Operation { case prepare, translate }
    let id = UUID()
    let operation: Operation
    let direction: TranslationDirection
    let text: String
}

@MainActor
struct TranslationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var inputFocused: Bool
    @State private var direction: TranslationDirection = .chineseToEnglish
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var resultDirection = ""
    @State private var status = "首次使用，先准备中英翻译资源"
    @State private var checkedAt: Date?
    @State private var checking = false
    @State private var installed = false
    @State private var checkTask: Task<Void, Never>?
    @State private var checkID = UUID()
    @State private var request: TranslationRequest?
    @State private var elapsed: Double?
    private let green = Color(red: 0.27, green: 0.64, blue: 0.06)
    private let ink = Color(red: 0.15, green: 0.20, blue: 0.24)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                resourceCard
                inputCard
                if !translatedText.isEmpty { resultCard }
                VStack(alignment: .leading, spacing: 10) {
                    Label("出发前，试试真正离线", systemImage: "airplane").font(.headline)
                    Text("准备资源 → 开启飞行模式并关闭 Wi-Fi → 重开应用，翻译一句新句子。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("免费签名需定期刷新。资源下载后，翻译无需调用在线模型。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.horizontal, 4)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("旅前英语")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if inputFocused {
                    Button("完成") { inputFocused = false }
                        .accessibilityIdentifier("translation.dismissKeyboard")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘", systemImage: "keyboard.chevron.compact.down") { inputFocused = false }
            }
        }
        .tint(green)
        .onAppear { checkResources() }
        .onDisappear { checkTask?.cancel() }
        .onChange(of: sourceText) { _, _ in translatedText = ""; elapsed = nil }
        .onChange(of: direction) { _, _ in
            translatedText = ""; elapsed = nil; installed = false; checkedAt = nil
            checkResources()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && request == nil { checkResources() }
        }
        .sheet(item: $request, onDismiss: { checkResources() }) { operation in
            TranslationTaskView(request: operation) { result, duration in
                translatedText = result
                resultDirection = operation.direction.rawValue
                elapsed = duration
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 30, weight: .bold)).foregroundStyle(green)
                .frame(width: 70, height: 70)
                .background(green.opacity(0.12), in: RoundedRectangle(cornerRadius: 23))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("把想说的话，变成英语")
                    .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(ink)
                Text("离线翻译 · 中英双向").font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 10).onTapGesture { inputFocused = false }
    }

    private var resourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(installed ? "资源已准备" : "准备离线包", systemImage: installed ? "checkmark.seal.fill" : "arrow.down.circle.fill")
                    .font(.headline).foregroundStyle(green)
                Spacer()
                if checking { ProgressView() }
            }
            Text(status).font(.subheadline).accessibilityIdentifier("translation.resourceStatus")
            if let checkedAt {
                Text("已检查 · \(checkedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { inputFocused = false; checkResources() } label: {
                    Label(checking ? "重新检查" : "检查状态", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("translation.checkResources")
                Button { start(.prepare) } label: {
                    Text("准备资源").fontWeight(.bold).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("translation.prepareResources")
            }
            Text("首次下载需联网。已下载时不会重复弹出下载确认。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("翻译方向", selection: $direction) {
                ForEach(TranslationDirection.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            ZStack(alignment: .topLeading) {
                if sourceText.isEmpty {
                    Text(direction == .chineseToEnglish ? "输入你想表达的中文…" : "输入想理解的英文…")
                        .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $sourceText).scrollContentBackground(.hidden).frame(height: 140)
                    .focused($inputFocused).autocorrectionDisabled()
                    .accessibilityLabel("待翻译文本").accessibilityIdentifier("translation.input")
            }
            HStack {
                Button("清空") { sourceText = ""; inputFocused = false }.disabled(sourceText.isEmpty)
                Spacer()
                Text("\(sourceText.count) / 2,000").font(.caption)
                    .foregroundStyle(sourceText.count > 2_000 ? Color.red : Color.secondary)
            }
            Button { start(.translate) } label: {
                Label("翻译", systemImage: "character.bubble.fill")
                    .font(.system(.headline, design: .rounded)).frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceText.count > 2_000)
            .accessibilityIdentifier("translation.submit")
            Text(sourceText.count > 2_000 ? "内容较长，请分段翻译。" : "缺少离线包时，会先引导你准备资源。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("译文 · \(resultDirection)", systemImage: "checkmark.bubble.fill").font(.headline).foregroundStyle(green)
            Text(translatedText).font(.title3).textSelection(.enabled).accessibilityIdentifier("translation.output")
            ShareLink(item: translatedText) { Label("分享译文", systemImage: "square.and.arrow.up") }
            if let elapsed {
                Text("处理用时 \(elapsed, specifier: "%.2f") 秒").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }

    private func start(_ operation: TranslationRequest.Operation) {
        inputFocused = false
        request = TranslationRequest(operation: operation, direction: direction,
                                     text: sourceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func checkResources() {
        checkTask?.cancel()
        let id = UUID()
        checkID = id
        let selected = direction
        checking = true
        status = "正在检查 \(selected.rawValue) 资源…"
        checkTask = Task { @MainActor in
            let state = await LanguageAvailability().status(from: selected.source, to: selected.target)
            guard !Task.isCancelled, id == checkID else { return }
            checking = false
            installed = state == .installed
            checkedAt = Date()
            switch state {
            case .installed: status = "\(selected.rawValue)：资源已安装，可以尝试离线翻译。"
            case .supported: status = "\(selected.rawValue)：尚未下载资源，点击「准备资源」开始。"
            case .unsupported: status = "此设备暂不支持该语言组合，请核对系统版本。"
            @unknown default: status = "暂时无法确认。你仍可点击「准备资源」查看系统提示。"
            }
        }
    }
}
