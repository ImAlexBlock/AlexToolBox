import MouseControl
import SwiftUI

struct MouseSection: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { model.accelerationEnabled },
                set: { newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.accelerationEnabled = newValue
                    }
                    model.update()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Windows 指针加速")
                        .font(.system(size: 13, weight: .medium))
                    Text("提高指针精确度 · 关闭后为线性")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(.accentColor)

            speedCard
            statusRow
            Spacer(minLength: 0)
        }
    }

    // MARK: - 速度档位

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("速度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("\(model.speedPosition)/11")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.speedPosition)))

                Text("×\(model.formattedMultiplier)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .contentTransition(.numericText(value: model.multiplier))
            }

            SpeedLadder(position: model.speedPosition) { notch in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                    model.setSpeed(notch)
                }
            }
        }
        .padding(13)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - 状态

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(model.statusLevel.color)
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusText)
                    .font(.system(size: 11, weight: .medium))
                if !model.detailText.isEmpty {
                    Text(model.detailText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.needsInputMonitoringPermission {
                    Button("打开输入监控设置") {
                        model.openInputMonitoringSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 速度阶梯

private struct SpeedLadder: View {
    let position: Int
    let onChange: (Int) -> Void

    @State private var hovered: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(WindowsPointerModel.positions, id: \.self) { notch in
                Button {
                    onChange(notch)
                } label: {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(fill(for: notch))
                            .frame(height: 10 + CGFloat(notch) * 2.1)
                            .overlay(
                                Capsule()
                                    .strokeBorder(stroke(for: notch),
                                                  lineWidth: notch == position ? 1 : 0.5)
                            )
                            .shadow(color: notch == position
                                        ? Color.accentColor.opacity(0.35)
                                        : .clear,
                                    radius: 5)

                        Text("\(notch)")
                            .font(.system(size: 9,
                                          weight: notch == position ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(notch == position ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    withAnimation(.easeOut(duration: 0.15)) {
                        if inside {
                            hovered = notch
                        } else if hovered == notch {
                            hovered = nil
                        }
                    }
                }
                .help(helpText(for: notch))
                .accessibilityLabel("速度 \(notch)")
                .accessibilityAddTraits(notch == position ? .isSelected : [])
            }
        }
        .frame(height: 58, alignment: .bottom)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: position)
    }

    private func fill(for notch: Int) -> LinearGradient {
        let base: Color
        if notch == position {
            base = .accentColor
        } else if notch < position {
            base = Color.accentColor.opacity(0.42)
        } else if hovered == notch {
            base = Color.primary.opacity(0.24)
        } else {
            base = Color.primary.opacity(0.14)
        }
        return LinearGradient(colors: [base, base.opacity(notch == position ? 0.62 : 0.9)],
                              startPoint: .bottom,
                              endPoint: .top)
    }

    private func stroke(for notch: Int) -> Color {
        notch == position ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.06)
    }

    private func helpText(for notch: Int) -> String {
        let multiplier = WindowsPointerModel.multiplier(forPosition: notch)
        return "速度 \(notch) · ×\(String(format: "%.1f", multiplier))"
    }
}

// MARK: - 状态颜色

extension MouseModel.StatusLevel {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .neutral: return Color.secondary
        }
    }
}
