import Foundation

struct SplashPhrase: Sendable {
    let title: String
    let subtitle: String
    let boardLines: [String]

    var boardColumns: Int {
        (boardLines.map(\.count).max() ?? 1) + 2
    }
}

enum SplashConfig {
    static let phrases: [SplashPhrase] = [
        SplashPhrase(
            title: "Momo's Money",
            subtitle: "Budget loading",
            boardLines: ["MOMO'S", "MONEY"]
        ),
        SplashPhrase(
            title: "Save Smart",
            subtitle: "Every dollar counts",
            boardLines: ["SAVE", "SMART"]
        ),
        SplashPhrase(
            title: "Stack Paper",
            subtitle: "Build that wealth",
            boardLines: ["STACK", "PAPER"]
        ),
        SplashPhrase(
            title: "Pay Yourself First",
            subtitle: "Savings first",
            boardLines: ["PAY YOUR", "SELF"]
        ),
        SplashPhrase(
            title: "You Got This",
            subtitle: "Stay on budget",
            boardLines: ["YOU", "GOT", "THIS"]
        ),
        SplashPhrase(
            title: "Dream Big",
            subtitle: "Save for it",
            boardLines: ["DREAM", "BIG"]
        ),
    ]

    static func random() -> SplashPhrase {
        phrases.randomElement()!
    }
}
