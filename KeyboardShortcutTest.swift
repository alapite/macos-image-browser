import SwiftUI

// Minimal test to verify multiple keyboardShortcut behavior
struct KeyboardShortcutTest: View {
    @State private var message = "Press Space or Escape"

    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .font(.title)

            // Test: Multiple keyboardShortcut modifiers on same button
            Button(action: {
                message = "Button triggered!"
            }) {
                Text("Test Button")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
            }
            .keyboardShortcut(.space, modifiers: [])
            .keyboardShortcut(.escape)

            Text("Try pressing Space or Escape key")
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 300)
    }
}

#if ENABLE_PREVIEWS
// Preview
#Preview {
    KeyboardShortcutTest()
}
#endif
