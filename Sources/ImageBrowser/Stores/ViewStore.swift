import Foundation

/// Navigation and slideshow state management store.
///
/// Responsibilities:
/// - Manage current image index for navigation
/// - Track slideshow running state and interval
/// - Handle sort order preferences
/// - Provide navigation methods (next, previous)
///
/// Design principles:
/// - Max 10 @Published properties to prevent bloat
/// - @MainActor ensures UI updates on main thread (SwiftUI requirement)
/// - Navigation state independent of image loading or filters
/// - No direct dependencies on ImageStore or FilterStore (loose coupling)
///
/// Usage pattern:
/// ```swift
/// @StateObject var viewStore = ViewStore()
///
/// // Navigate to next image
/// viewStore.navigateToNext(totalImages: images.count)
///
/// // Start slideshow
/// viewStore.isSlideshowRunning = true
///
/// // Change sort order
/// viewStore.sortOrder = .creationDate
/// ```
@MainActor
final class ViewStore: ObservableObject {

    // MARK: - Sort Order Enum

    /// Image sort order options
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case creationDate = "Creation Date"
        case custom = "Custom Order"
    }

    // MARK: - Zoom Mode Enum

    /// Zoom mode for tracking fit/actual/custom zoom states
    enum ZoomMode: String, CaseIterable {
        case fit = "Fit to Both"
        case actual = "Actual Size"
        case custom = "Custom"
    }

    // MARK: - Published Properties (max 10)

    /// Current image index in the images array
    @Published var currentImageIndex: Int = 0

    /// Slideshow running state
    @Published var isSlideshowRunning: Bool = false

    /// Slideshow interval in seconds
    @Published var slideshowInterval: Double = 3.0

    /// Current sort order
    @Published var sortOrder: SortOrder = .name

    /// Custom image order (URL strings in custom sequence)
    @Published var customOrder: [String] = []

    /// Current zoom level as multiplier (0.1 to 5.0, default 1.0 = 100%)
    @Published var currentZoom: Double = 1.0

    /// Current zoom mode (fit, actual, custom)
    @Published var zoomMode: ZoomMode = .fit

    /// Fullscreen mode state (true when in fullscreen)
    @Published var isFullscreen: Bool = false

    /// Info panel visibility state (true when showing)
    @Published var showInfoPanel: Bool = false

    /// Signal to view layer that a fit-to-viewport reset is needed.
    /// MainImageViewer observes this to clear pan/gesture state in fit mode.
    @Published var needsRefit: Bool = false

    // MARK: - Initialization

    /// Initialize with default navigation state
    init() {
        // Default values set in property declarations
    }

    // MARK: - Navigation Methods

    /// Navigate to next image with wrap-around
    /// - Parameter totalImages: Total number of images in the current folder
    ///
    /// If at the last image, wraps around to the first image.
    /// Does nothing if there are no images.
    func navigateToNext(totalImages: Int) {
        guard totalImages > 0 else { return }
        currentImageIndex = (currentImageIndex + 1) % totalImages
    }

    /// Navigate to previous image with wrap-around
    /// - Parameter totalImages: Total number of images in the current folder
    ///
    /// If at the first image, wraps around to the last image.
    /// Does nothing if there are no images.
    func navigateToPrevious(totalImages: Int) {
        guard totalImages > 0 else { return }
        currentImageIndex = (currentImageIndex - 1 + totalImages) % totalImages
    }

    /// Navigate to specific image index
    /// - Parameters:
    ///   - index: Target image index
    ///   - totalImages: Total number of images in the current folder
    ///
    /// Does nothing if index is out of bounds.
    func navigateToIndex(_ index: Int, totalImages: Int) {
        guard index >= 0 && index < totalImages else { return }
        currentImageIndex = index
    }

    // MARK: - Slideshow Control

    /// Start slideshow
    ///
    /// Sets isSlideshowRunning to true.
    /// Note: Timer management is handled by the view layer (e.g., AppState).
    func startSlideshow() {
        isSlideshowRunning = true
    }

    /// Stop slideshow
    ///
    /// Sets isSlideshowRunning to false.
    /// Note: Timer management is handled by the view layer (e.g., AppState).
    func stopSlideshow() {
        isSlideshowRunning = false
    }

    /// Toggle slideshow running state
    func toggleSlideshow() {
        isSlideshowRunning.toggle()
    }

    // MARK: - Slideshow Interval Management

    /// Update slideshow interval
    /// - Parameter interval: New interval in seconds (must be > 0)
    ///
    /// If slideshow is running, the timer will need to be restarted
    /// by the view layer to apply the new interval.
    func updateSlideshowInterval(_ interval: Double) {
        guard interval > 0 else { return }
        slideshowInterval = interval
    }

    // MARK: - Sort Order Management

    /// Set sort order
    /// - Parameter order: New sort order
    func setSortOrder(_ order: SortOrder) {
        sortOrder = order
    }

    /// Cycle to next sort order
    ///
    /// Order cycle: name → creationDate → custom → name
    func cycleSortOrder() {
        switch sortOrder {
        case .name:
            sortOrder = .creationDate
        case .creationDate:
            sortOrder = .custom
        case .custom:
            sortOrder = .name
        }
    }

    // MARK: - Custom Order Management

    /// Update custom image order
    /// - Parameter order: Array of URL strings in custom sequence
    func updateCustomOrder(_ order: [String]) {
        customOrder = order
    }

    /// Clear custom order
    func clearCustomOrder() {
        customOrder.removeAll()
    }

    // MARK: - Index Validation

    /// Check if current index is valid
    /// - Parameter totalImages: Total number of images
    /// - Returns: True if current index is within valid range
    func isIndexValid(totalImages: Int) -> Bool {
        return currentImageIndex >= 0 && currentImageIndex < totalImages
    }

    /// Reset index to zero
    ///
    /// Useful when loading a new folder or clearing images.
    func resetIndex() {
        currentImageIndex = 0
    }

    // MARK: - Zoom Management

    /// Set zoom to preset percentage
    /// - Parameter percent: Zoom percentage (25, 50, 100, 200, 400, etc.)
    ///
    /// Converts percentage to multiplier (e.g., 50% = 0.5, 200% = 2.0)
    /// and updates zoomMode to .custom unless exact preset match.
    func setZoomPreset(_ percent: Double) {
        currentZoom = percent / 100.0
        if percent == 100 {
            zoomMode = .actual
        } else {
            zoomMode = .custom
        }
    }

    /// Fit image to viewport.
    ///
    /// Sets zoomMode to `.fit`, restores the neutral fit baseline zoom (1.0),
    /// and triggers a view-layer reset of pan/gesture state.
    ///
    func fitToBoth() {
        zoomMode = .fit
        currentZoom = 1.0
        needsRefit = true
    }

    /// Set zoom to actual size (100%)
    ///
    /// Sets currentZoom to 1.0 and zoomMode to .actual.
    func actualSize() {
        currentZoom = 1.0
        zoomMode = .actual
    }

    /// Zoom in by 25%
    ///
    /// Multiplies currentZoom by 1.25, caps at 5.0 (500%).
    func zoomIn() {
        currentZoom = min(5.0, currentZoom * 1.25)
        zoomMode = .custom
    }

    /// Zoom out by 20%
    ///
    /// Multiplies currentZoom by 0.8, caps at 0.1 (10%).
    func zoomOut() {
        let newZoom = currentZoom * 0.8
        currentZoom = max(0.1, newZoom)
        // Snap to minimum if very close (within 0.05 of minimum)
        if currentZoom < 0.15 {
            currentZoom = 0.1
        }
        zoomMode = .custom
    }

    // MARK: - Fullscreen Management

    /// Toggle fullscreen mode
    ///
    /// Switches between fullscreen and windowed mode.
    func toggleFullscreen() {
        isFullscreen.toggle()
    }

    /// Enter fullscreen mode
    ///
    /// Sets isFullscreen to true.
    func enterFullscreen() {
        isFullscreen = true
    }

    /// Exit fullscreen mode
    ///
    /// Sets isFullscreen to false.
    func exitFullscreen() {
        isFullscreen = false
    }
}
