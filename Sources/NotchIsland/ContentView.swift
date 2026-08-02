import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "macbook")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            Text("NotchIsland")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("The macOS development environment is ready.")
                .foregroundStyle(.secondary)

            Label("Next: build the notch overlay", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(.regularMaterial)
    }
}
