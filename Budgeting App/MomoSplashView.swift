import SwiftUI

enum MomoSplashBoardFormatter {
    static func rows(for lines: [String], columns: Int, rowCount: Int) -> [[String]] {
        (0..<rowCount).map { rowIndex in
            let line = rowIndex < lines.count ? lines[rowIndex].uppercased() : ""
            let characters = Array(line.prefix(columns)).map(String.init)
            let leadingPadding = max(0, (columns - characters.count) / 2)
            let trailingPadding = max(0, columns - leadingPadding - characters.count)
            return Array(repeating: " ", count: leadingPadding) + characters + Array(repeating: " ", count: trailingPadding)
        }
    }
}

struct MomoLaunchSplashContainer<Content: View>: View {
    @State private var isSplashVisible = true
    let scaleFactor: CGFloat
    let phrase: SplashPhrase
    @ViewBuilder let content: () -> Content

    init(scaleFactor: CGFloat = 1.0, @ViewBuilder content: @escaping () -> Content) {
        self.scaleFactor = scaleFactor
        self.phrase = SplashConfig.random()
        self.content = content
    }

    var body: some View {
        ZStack {
            content()
                .disabled(isSplashVisible)

            if isSplashVisible {
                MomoSplashView(phrase: phrase, scaleFactor: scaleFactor)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(2300))
            withAnimation(.easeOut(duration: 0.35)) {
                isSplashVisible = false
            }
        }
    }
}

struct MomoSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    let phrase: SplashPhrase
    let scaleFactor: CGFloat

    private var rows: [[String]] {
        MomoSplashBoardFormatter.rows(
            for: phrase.boardLines,
            columns: phrase.boardColumns,
            rowCount: phrase.boardLines.count
        )
    }

    var body: some View {
        ZStack {
            CuanTheme.background
                .ignoresSafeArea()

            VStack(spacing: 28 * scaleFactor) {
                VStack(spacing: 10 * scaleFactor) {
                    Text(phrase.title)
                        .font(.title2.weight(.black))
                        .foregroundStyle(CuanTheme.text)

                    Text(phrase.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CuanTheme.muted)
                }

                if reduceMotion {
                    MomoStaticSplitFlapBoard(rows: rows, scaleFactor: scaleFactor)
                } else {
                    TimelineView(.animation) { timeline in
                        MomoAnimatedSplitFlapBoard(
                            rows: rows,
                            elapsed: timeline.date.timeIntervalSince(startDate),
                            scaleFactor: scaleFactor
                        )
                    }
                }

                ProgressView()
                    .controlSize(.small)
                    .tint(CuanTheme.primary)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(phrase.title) is loading")
        }
    }
}

private struct MomoStaticSplitFlapBoard: View {
    let rows: [[String]]
    let scaleFactor: CGFloat

    var body: some View {
        MomoSplitFlapBoardShell(scaleFactor: scaleFactor) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 5 * scaleFactor) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        MomoSplitFlapTile(character: rows[row][column], accent: false, rotation: 0, scaleFactor: scaleFactor)
                    }
                }
            }
        }
    }
}

private struct MomoAnimatedSplitFlapBoard: View {
    let rows: [[String]]
    let elapsed: TimeInterval
    let scaleFactor: CGFloat

    private let characterSet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$%#@+")
    private let accentColors: [Color] = [
        CuanTheme.primary,
        CuanTheme.gain,
        Color(red: 0.95, green: 0.71, blue: 0.18),
        Color(red: 0.26, green: 0.56, blue: 0.92)
    ]

    var body: some View {
        MomoSplitFlapBoardShell(scaleFactor: scaleFactor) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 5 * scaleFactor) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        let index = (row * rows[row].count) + column
                        let state = tileState(target: rows[row][column], index: index)
                        MomoSplitFlapTile(
                            character: state.character,
                            accent: state.isScrambling,
                            rotation: state.rotation,
                            accentColor: accentColors[index % accentColors.count],
                            scaleFactor: scaleFactor
                        )
                    }
                }
            }
        }
    }

    private func tileState(target: String, index: Int) -> (character: String, isScrambling: Bool, rotation: Double) {
        guard target != " " else {
            return (" ", false, 0)
        }

        let localTime = elapsed - (Double(index) * 0.035)
        if localTime < 0 {
            return (" ", false, 0)
        }

        if localTime < 0.72 {
            let scrambleIndex = abs(Int((localTime * 18).rounded(.down)) + (index * 7)) % characterSet.count
            let rotation = -8 + sin(localTime * 24) * 4
            return (String(characterSet[scrambleIndex]), true, rotation)
        }

        let settleProgress = min(1, (localTime - 0.72) / 0.24)
        let rotation = (1 - settleProgress) * -10
        return (target, false, rotation)
    }
}

private struct MomoSplitFlapBoardShell<Content: View>: View {
    let scaleFactor: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10 * scaleFactor) {
            MomoAccentRail(scaleFactor: scaleFactor)
            VStack(spacing: 6 * scaleFactor) {
                content()
            }
            MomoAccentRail(scaleFactor: scaleFactor)
        }
        .padding(10 * scaleFactor)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 14 * scaleFactor, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scaleFactor, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 22 * scaleFactor, x: 0, y: 14 * scaleFactor)
    }
}

private struct MomoAccentRail: View {
    let scaleFactor: CGFloat

    var body: some View {
        VStack(spacing: 5 * scaleFactor) {
            RoundedRectangle(cornerRadius: 3 * scaleFactor, style: .continuous)
                .fill(CuanTheme.gain)
            RoundedRectangle(cornerRadius: 3 * scaleFactor, style: .continuous)
                .fill(CuanTheme.primary)
        }
        .frame(width: 10 * scaleFactor, height: 48 * scaleFactor)
        .accessibilityHidden(true)
    }
}

private struct MomoSplitFlapTile: View {
    let character: String
    let accent: Bool
    let rotation: Double
    var accentColor: Color = CuanTheme.primary
    let scaleFactor: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * scaleFactor, style: .continuous)
                .fill(Color(red: 0.06, green: 0.06, blue: 0.07))

            RoundedRectangle(cornerRadius: 3 * scaleFactor, style: .continuous)
                .fill(accent ? accentColor : Color(red: 0.13, green: 0.13, blue: 0.15))
                .padding(1 * scaleFactor)

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)

            Text(character == " " ? "" : character)
                .font(.system(size: 20 * scaleFactor, weight: .black, design: .monospaced))
                .foregroundStyle(accent ? .black.opacity(0.78) : .white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)

            LinearGradient(
                colors: [.clear, .white.opacity(accent ? 0.18 : 0.07), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 3 * scaleFactor, style: .continuous))
            .padding(1 * scaleFactor)
        }
        .frame(width: 26 * scaleFactor, height: 32 * scaleFactor)
        .rotation3DEffect(.degrees(rotation), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
        .accessibilityHidden(true)
    }
}

#Preview {
    MomoSplashView(phrase: SplashConfig.random(), scaleFactor: 1.6)
}
