import PracticeKit
import SwiftUI

/// Instrument symbol tinted with the instrument's color.
struct InstrumentIcon: View {
    let symbolName: String
    let colorHex: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex).gradient, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

extension InstrumentIcon {
    init(_ instrument: Instrument, size: CGFloat = 36) {
        self.init(symbolName: instrument.symbolName, colorHex: instrument.colorHex, size: size)
    }
}

/// Today's progress toward the daily goal.
struct GoalRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
            if progress >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: lineWidth * 1.6, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .animation(.smooth, value: progress)
    }
}

/// 1–5 picker used for "How did it go?" and focus.
struct RatingPicker: View {
    let title: LocalizedStringKey
    let symbol: String
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        value = value == n ? nil : n
                    } label: {
                        Image(systemName: (value ?? 0) >= n ? "\(symbol).fill" : symbol)
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle((value ?? 0) >= n ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
            .sensoryFeedback(.selection, trigger: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(value.map { Text("\($0) of 5") } ?? Text("Not set"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(5, (value ?? 0) + 1)
                case .decrement: value = (value ?? 1) <= 1 ? nil : (value ?? 1) - 1
                @unknown default: break
                }
            }
        }
    }
}

/// Empty states teach the app.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.glassProminent)
            }
        }
    }
}

/// A live timer that needs no per-second state updates.
struct SessionTimerText: View {
    let session: ActiveSession
    var segmentOnly = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: session.isPaused)) { context in
            let elapsed = segmentOnly ? session.currentSegmentElapsed(at: context.date) : session.elapsed(at: context.date)
            Text(DurationText.clock(elapsed))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel(segmentOnly ? Text("Current item time") : Text("Total time"))
                .accessibilityValue(DurationText.timerSpoken(elapsed))
        }
    }
}

/// A tag chip with remove button.
struct TagChip: View {
    let text: String
    var isSelected = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.maxY } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            for (index, frame) in row.frames {
                subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                      proposal: ProposedViewSize(frame.size))
            }
        }
    }

    private struct Row { var frames: [(Int, CGRect)] = []; var width: CGFloat = 0; var maxY: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
                rows.append(Row())
            }
            rows[rows.count - 1].frames.append((index, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            rows[rows.count - 1].width = x - spacing
            rows[rows.count - 1].maxY = y + rowHeight
        }
        return rows
    }
}
