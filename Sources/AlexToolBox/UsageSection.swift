import SwiftUI
import UsageControl

struct UsageSection: View {
    @ObservedObject var model: UsageModel
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.hasStoredKey && !model.isEditingKey {
                if let snapshot = model.snapshot {
                    UsageQuotaCard(snapshot: snapshot)
                } else if model.isLoading {
                    loadingCard
                } else {
                    emptyCard
                }
            } else {
                keyForm
            }

            if let errorText = model.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            footer
            Spacer(minLength: 0)
        }
        .onAppear { model.setPageVisible(true) }
        .onDisappear { model.setPageVisible(false) }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: model.hasStoredKey)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: model.isEditingKey)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenCode Go")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.hasStoredKey ? "每 60 秒自动刷新" : "添加 API Key 查看额度")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if model.hasStoredKey {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            model.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .help("立即刷新")
                }
            }
        }
    }

    // MARK: - API Key

    private var keyForm: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 10))
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Link("打开 Console", destination: Self.consoleURL)
                    .font(.system(size: 10))
            }

            SecureField("oc_sk_…", text: $model.keyDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06),
                            in: .rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .focused($keyFieldFocused)
                .privacySensitive()
                .onSubmit { saveKey() }

            HStack(spacing: 8) {
                Button("保存并刷新") { saveKey() }
                    .buttonStyle(.glassProminent)
                    .font(.system(size: 11, weight: .medium))
                    .disabled(model.keyDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)

                if model.hasStoredKey {
                    Button("取消") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            model.cancelEditingKey()
                        }
                    }
                    .buttonStyle(.glass)
                    .font(.system(size: 11))

                    Spacer(minLength: 0)

                    Button("清除") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            model.clearKey()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                } else {
                    Spacer(minLength: 0)
                }
            }

            Text("Key 只保存在本机钥匙串，并只发送到 opencode.ai。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onAppear { keyFieldFocused = true }
    }

    private func saveKey() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            model.saveDraftKey()
        }
    }

    // MARK: - 额度卡片

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("读取额度…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var emptyCard: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                model.refresh()
            }
        } label: {
            Label("读取额度", systemImage: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.snapshot == nil
                      ? Color.secondary.opacity(0.5)
                      : Color.green)
                .frame(width: 6, height: 6)

            if let lastUpdated = model.lastUpdated {
                Text("更新于 \(lastUpdated.formatted(.dateTime.hour().minute().second()))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("尚未刷新")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if model.hasStoredKey && !model.isEditingKey {
                Button("更换 Key") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.beginEditingKey()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private static let consoleURL = URL(string: "https://opencode.ai/console")!
}

// MARK: - 额度行

struct UsageQuotaCard: View {
    let snapshot: GoUsageSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                ForEach(Array(snapshot.windows.enumerated()),
                        id: \.element.id) { index, window in
                    UsageQuotaRow(window: window, now: context.date)
                    if index < snapshot.windows.count - 1 {
                        Divider()
                            .opacity(0.45)
                    }
                }
            }
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }
}

private struct UsageQuotaRow: View {
    let window: GoUsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.kind.title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Text(window.percent >= 99.5
                     ? "已用尽"
                     : "\(Int(window.percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: window.percent))
            }

            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(LinearGradient(colors: [tint, tint.opacity(0.62)],
                                                 startPoint: .leading,
                                                 endPoint: .trailing))
                            .frame(width: fillWidth(in: proxy.size.width))
                            .shadow(color: tint.opacity(0.35), radius: 4)
                    }
                }
                .frame(height: 6)

                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8),
                       value: window.percent)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard window.percent > 0 else { return 0 }
        return max(width * window.percent / 100, 4)
    }

    private var tint: Color {
        switch window.percent {
        case 85...: return .red
        case 60..<85: return .orange
        default: return .green
        }
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else { return "重置时间未知" }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "等待重置" }
        if interval < 3600 {
            return "\(max(1, Int(interval / 60))) 分钟后重置"
        }
        if interval < 86_400 {
            let hours = Int(interval / 3600)
            let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
            return minutes == 0
                ? "\(hours) 小时后重置"
                : "\(hours) 小时 \(minutes) 分后重置"
        }
        if interval < 7 * 86_400 {
            let days = Int(interval / 86_400)
            let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3600)
            return hours == 0
                ? "\(days) 天后重置"
                : "\(days) 天 \(hours) 小时后重置"
        }
        return resetsAt.formatted(.dateTime.month().day().hour().minute()) + " 重置"
    }
}
