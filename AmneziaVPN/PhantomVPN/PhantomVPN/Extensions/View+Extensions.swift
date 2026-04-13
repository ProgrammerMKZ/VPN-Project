import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct MaurtenFont {
    static let mono = Font.custom("Courier New", size: 12)
    static let monoSmall = Font.custom("Courier New", size: 11)
    static let monoBody = Font.custom("Courier New", size: 13)
    static let monoLabel = Font.custom("Courier New", size: 14)
    static let monoTitle = Font.custom("Courier New", size: 22)
    static let monoLarge = Font.custom("Courier New", size: 28)
    static let monoButton = Font.custom("Courier New", size: 15)

    static func size(_ s: CGFloat) -> Font {
        Font.custom("Courier New", size: s)
    }
}
