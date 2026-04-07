// Custom ViewModifier with convenience View extension
import SwiftUI

struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(radius: shadowRadius)
            .padding(.horizontal)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 12, shadow: CGFloat = 4) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, shadowRadius: shadow))
    }
}

struct ExampleView: View {
    var body: some View {
        VStack {
            Text("Featured Recipe")
                .font(.headline)
            Text("Homemade pasta with fresh basil")
                .font(.subheadline)
        }
        .cardStyle()
    }
}
