import SwiftUI

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(Rectangle())
            .overlay(
                Rectangle()
                    .stroke(Color.black, lineWidth: 1)
            )
    }

    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
