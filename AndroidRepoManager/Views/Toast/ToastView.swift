import SwiftUI

struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
