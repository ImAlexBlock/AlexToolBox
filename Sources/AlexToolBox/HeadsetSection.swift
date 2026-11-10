import HeadsetControl
import SwiftUI

struct HeadsetSection: View {
    @ObservedObject var link: HeadsetLink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            connectionHeader
            modeGrid

            if let error = link.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if case .disconnected = link.state {
                connectButton
            }

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: link.lastError)
    }

    // MARK: - 连接状态

    private var connectionHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(link.state.isConnected
                          ? Color.accentColor.opacity(0.16)
                          : Color.primary.opacity(0.06))
                    .frame(width: 36, height: 36)

                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(link.state.isConnected ? Color.accentColor : Color.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: isConnecting)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(link.state.text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(link.state.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let mode = link.mode {
                Text(mode.title)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.18)), in: .capsule)
                    .contentTransition(.numericText())
            }
        }
    }

    private var iconName: String {
        if let mode = link.mode { return mode.symbol }
        return link.state.isConnected ? "headphones" : "headphones.slash"
    }

    private var isConnecting: Bool {
        if case .connecting = link.state { return true }
        return false
    }

    // MARK: - 降噪档位

    private var modeGrid: some View {
        GlassEffectContainer(spacing: 8) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                ForEach(NoiseMode.allCases) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: link.mode == mode,
                        isPending: link.pendingMode == mode && link.mode != mode,
                        isEnabled: link.state.isConnected
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                            link.select(mode)
                        }
                    }
                }
            }
        }
    }

    private var connectButton: some View {
        Button {
            link.connectHeadset()
        } label: {
            Label("连接耳机", systemImage: "link")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
    }
}

// MARK: - 档位按钮

private struct ModeButton: View {
    let mode: NoiseMode
    let isSelected: Bool
    let isPending: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Group {
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .symbolEffect(.bounce, value: isSelected)
                    }
                }
                .frame(width: 17)

                Text(mode.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        .glassEffect(
            .regular
                .tint(glassTint)
                .interactive(isEnabled),
            in: .rect(cornerRadius: 13)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 1 : 0.5
                )
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.28) : .clear, radius: 7, y: 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var glassTint: Color? {
        if isSelected { return Color.accentColor.opacity(0.22) }
        if isHovering && isEnabled { return Color.primary.opacity(0.06) }
        return nil
    }
}
