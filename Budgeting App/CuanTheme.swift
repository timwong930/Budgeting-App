import SwiftUI

enum CuanTheme {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let elevatedCard = Color(.tertiarySystemGroupedBackground)
    static let text = Color.primary
    static let muted = Color.secondary
    static let border = Color.primary.opacity(0.10)
    static let primary = Color.accentColor
    static let gain = Color.green
    static let gainSoft = Color(red: 0.675, green: 0.816, blue: 0.745)
    static let loss = Color.red
    static let navy = Color.primary

    static func changeColor(for direction: CuanMarketDirection) -> Color {
        switch direction {
        case .gain:
            return gain
        case .loss:
            return loss
        case .flat:
            return muted
        }
    }
}

struct CuanCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CuanTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(CuanTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

struct CuanPrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(CuanTheme.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CuanMetricPill: View {
    let title: String
    let value: String
    let tint: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(CuanTheme.muted)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CuanTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CuanTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CuanSegmentedRange<Selection: Hashable, Content: View>: View {
    let values: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> Content

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { value in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = value
                    }
                } label: {
                    label(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == value ? CuanTheme.primary : CuanTheme.muted)
                        .frame(minWidth: 34, minHeight: 30)
                        .background(selection == value ? CuanTheme.elevatedCard : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CuanTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CuanTickerAvatar: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Text(String(symbol.prefix(1)).uppercased())
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }
}

struct CuanSparkline: View {
    let values: [Double]
    let tint: Color
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let normalized = CuanSparklineSeries(values: values).normalized
            Path { path in
                guard normalized.count > 1 else { return }
                let step = proxy.size.width / CGFloat(normalized.count - 1)
                for index in normalized.indices {
                    let x = CGFloat(index) * step
                    let y = proxy.size.height - (CGFloat(normalized[index]) * proxy.size.height)
                    if index == normalized.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}
