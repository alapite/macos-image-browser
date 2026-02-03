import SwiftUI

// Test 2: Separate buttons to verify Space and Escape work individually
struct SeparateButtonTest: View {
    @State private var message = "Press Space or Escape"

    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .font(.title)

            HStack(spacing: 20) {
                // Test Space key on separate button
                Button(action: {
                    message = "Space button triggered!"
                }) {
                    Text("Space Button")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                }
                .keyboardShortcut(.space, modifiers: [])

                // Test Escape key on separate button
                Button(action: {
                    message = "Escape button triggered!"
                }) {
                    Text("Escape Button")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                }
                .keyboardShortcut(.escape)
            }

            Text("Press Space for left button, Escape for right button")
                .foregroundColor(.secondary)
        }
        .frame(width: 500, height: 300)
    }
}

#if ENABLE_PREVIEWS
#Preview {
    SeparateButtonTest()
}
#endif
