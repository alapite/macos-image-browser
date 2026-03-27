import SwiftUI

/// Reusable empty state view component
///
/// Displays an icon, title, message, and action button for empty states throughout the app.
/// Suitable for: empty folders, no search results, no filtered images, etc.
///
/// Design principles:
/// - Centered layout with generous spacing
/// - Large, secondary-colored icon for visual emphasis
/// - Clear, descriptive messaging
/// - Prominent action button for user recovery
///
/// Usage pattern:
/// ```swift
/// EmptyStateView(
///     title: "No Results",
///     message: "No images match your current filters.",
///     systemImage: "magnifyingglass",
///     actionTitle: "Clear Filters"
/// ) {
///     filterStore.reset()
/// }
/// ```
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Large icon for visual emphasis
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            // Title and message with proper spacing
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Prominent action button
            Button(action: action) {
                Text(actionTitle)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#if ENABLE_PREVIEWS
#Preview("No Results - Filters") {
    EmptyStateView(
        title: "No Results",
        message: "No images match your current filters. Try adjusting the filter criteria or clear all filters to see more images.",
        systemImage: "magnifyingglass",
        actionTitle: "Clear Filters"
    ) {
        // Action handler
        print("Clear filters tapped")
    }
}

#Preview("No Images") {
    EmptyStateView(
        title: "No Images",
        message: "Open a folder to start browsing images.",
        systemImage: "folder.open",
        actionTitle: "Open Folder"
    ) {
        // Action handler
        print("Open folder tapped")
    }
}
#endif
