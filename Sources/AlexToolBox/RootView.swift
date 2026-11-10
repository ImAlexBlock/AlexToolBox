import AppKit
import HeadsetControl
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var section: Section = .mouse
    @State private var hasAppeared = false
    @Namespace private var tabNamespace

    private enum Section: String, CaseIterable, Identifiable {
        case mouse
        case headset

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mouse: return "鼠标"
            case .headset: return "耳机"
            }
        }

        var symbol: String {
            switch self {
            case .mouse: return "computermouse.fill"
            case .headset: return "headphones"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switcher

            ZStack(alignment: .top) {
                if section == .mouse {
                    MouseSection(model: model.mouse)
                        .transition(.blurReplace)
                } else {
                    HeadsetSection(link: model.headset)
                        .transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
            .animation(.snappy(duration: 0.34, extraBounce: 0.06), value: section)

            Divider()
                .opacity(0.6)

            footer
        }
        .padding(16)
        .frame(width: 356)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.97, anchor: .top)
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.62)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 10)
                )
                .shadow(color: .accentColor.opacity(0.32), radius: 7, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("AlexToolBox")
                    .font(.system(size: 15, weight: .semibold))
                Text("指针提速 · 耳机降噪")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HeadsetStatusPill(link: model.headset)
        }
    }

    // MARK: - 分段切换

    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(Section.allCases) { item in
                Button {
                    guard section != item else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        section = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
                    .background {
                        if section == item {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.22))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.accentColor.opacity(0.32),
                                                      lineWidth: 0.5)
                                )
                                .matchedGeometryEffect(id: "section-pill", in: tabNamespace)
                        }
                    }
                    .foregroundStyle(section == item ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                    model.mouse.restoreSystemDefault()
                }
            } label: {
                Label("恢复鼠标默认", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.glass)

            Spacer(minLength: 0)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - 耳机状态胶囊

private struct HeadsetStatusPill: View {
    @ObservedObject var link: HeadsetLink

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(link.state.isConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(link.state.isConnected ? "耳机在线" : "耳机离线")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
