import SwiftUI
import AppKit

private let defaultThumbnailSize: CGFloat = 50

private enum ViewerStyle {
    static let overlayCornerRadius: CGFloat = 8
    static let overlayPadding: CGFloat = 8
    static let overlayHorizontalSpacing: CGFloat = 8
}

private func metadataKey(for url: URL) -> String {
    url.standardizedFileURL.absoluteString
}

enum SidebarStatusFormatter {
    static func formatStatus(
        activeCollectionName: String?,
        filteredCount: Int,
        unfilteredTotalCount: Int,
        isFilteringActive: Bool,
        excludedCount: Int = 0
    ) -> String {
        let filteredText = imageCountText(filteredCount)
        let totalText = imageCountText(unfilteredTotalCount)

        if let activeCollectionName {
            var status = "Collection: \(activeCollectionName) · \(filteredText) (filtered from \(unfilteredTotalCount))"
            if excludedCount > 0 {
                status += " · \(excludedCount) excluded from browsing"
            }
            return status
        }

        if isFilteringActive {
            var status = "\(filteredText) (filtered from \(unfilteredTotalCount))"
            if excludedCount > 0 {
                status += " · \(excludedCount) excluded from browsing"
            }
            return status
        }

        var status = totalText
        if excludedCount > 0 {
            status += " · \(excludedCount) excluded from browsing"
        }
        return status
    }

    private static func imageCountText(_ count: Int) -> String {
        "\(count) image\(count == 1 ? "" : "s")"
    }
}

struct ExcludedReviewSidebarMetrics: Equatable {
    let excludedCount: Int
    let subtitleText: String

    static func make(
        appStateImages: [ImageFile],
        mergedExcludedImages: [DisplayImage],
        activeCollectionName: String?,
        filteredCount: Int,
        unfilteredTotalCount: Int,
        isFilteringActive: Bool
    ) -> ExcludedReviewSidebarMetrics {
        let excludedCount = mergedExcludedImages.count
        let subtitleText = SidebarStatusFormatter.formatStatus(
            activeCollectionName: activeCollectionName,
            filteredCount: filteredCount,
            unfilteredTotalCount: unfilteredTotalCount,
            isFilteringActive: isFilteringActive,
            excludedCount: excludedCount
        )

        _ = appStateImages

        return ExcludedReviewSidebarMetrics(
            excludedCount: excludedCount,
            subtitleText: subtitleText
        )
    }
}

enum SidebarDisplayState: Equatable {
    case loading
    case noResults
    case noImagesLoaded
    case noEligible
    case grid
}

enum SidebarDisplayStateResolver {
    static func resolve(
        isLoadingImages: Bool,
        visibleImageCount: Int,
        totalImageCount: Int,
        hasActiveCollectionOrFilters: Bool,
        hasEligibleImages: Bool
    ) -> SidebarDisplayState {
        if isLoadingImages {
            return .loading
        }

        if totalImageCount == 0 {
            return .noImagesLoaded
        }

        if !hasEligibleImages {
            return .noEligible
        }

        if visibleImageCount == 0 && hasActiveCollectionOrFilters {
            return .noResults
        }

        return .grid
    }
}

enum MainImageZoomScaleResolver {
    static func effectiveScale(zoomMode: ViewStore.ZoomMode, currentZoom: Double) -> CGFloat {
        if zoomMode == .fit {
            return 1.0
        }
        return CGFloat(currentZoom)
    }
}

enum ThumbnailPresentationKind: Equatable {
    case thumbnail
}

struct ThumbnailPresentation: Equatable {
    let kind: ThumbnailPresentationKind
    let opacity: Double
    let showsExcludedBadge: Bool

    static func normalBrowsing(isExcluded: Bool) -> ThumbnailPresentation {
        ThumbnailPresentation(
            kind: .thumbnail,
            opacity: isExcluded ? 0.4 : 1.0,
            showsExcludedBadge: isExcluded
        )
    }

    static func reviewMode(isExcluded: Bool) -> ThumbnailPresentation {
        ThumbnailPresentation(
            kind: .thumbnail,
            opacity: 1.0,
            showsExcludedBadge: false
        )
    }
}

@MainActor
func clearAllFiltersAndCollection(filterStore: FilterStore, collectionStore: CollectionStore) {
    filterStore.reset()
    collectionStore.clearActiveCollection()
}

struct KeyEventHandlingModifier: ViewModifier {
    let isSlideshowRunning: Bool
    let onNavigatePrevious: () -> Void
    let onNavigateNext: () -> Void
    let onRatingShortcut: ((Int) -> Void)?
    let keyEventMonitor: KeyEventMonitoring

    func body(content: Content) -> some View {
        content
            .background(
                KeyEventHandlingView(
                    isSlideshowRunning: isSlideshowRunning,
                    onNavigatePrevious: onNavigatePrevious,
                    onNavigateNext: onNavigateNext,
                    onRatingShortcut: onRatingShortcut,
                    keyEventMonitor: keyEventMonitor
                )
            )
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    let isSlideshowRunning: Bool
    let onNavigatePrevious: () -> Void
    let onNavigateNext: () -> Void
    let onRatingShortcut: ((Int) -> Void)?
    let keyEventMonitor: KeyEventMonitoring
    @EnvironmentObject var viewStore: ViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isSlideshowRunning: isSlideshowRunning,
            viewStore: viewStore,
            onNavigatePrevious: onNavigatePrevious,
            onNavigateNext: onNavigateNext,
            onRatingShortcut: onRatingShortcut,
            keyEventMonitor: keyEventMonitor
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateSlideshowState(isSlideshowRunning)
        context.coordinator.updateNavigationHandlers(previous: onNavigatePrevious, next: onNavigateNext)
        context.coordinator.updateRatingShortcutHandler(onRatingShortcut)
        context.coordinator.updateViewStore(viewStore)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    class Coordinator {
        var monitor: Any?
        var isSlideshowRunning: Bool
        var onNavigatePrevious: () -> Void
        var onNavigateNext: () -> Void
        var onRatingShortcut: ((Int) -> Void)?
        weak var viewStore: ViewStore?
        let keyEventMonitor: KeyEventMonitoring

        init(
            isSlideshowRunning: Bool,
            viewStore: ViewStore,
            onNavigatePrevious: @escaping () -> Void,
            onNavigateNext: @escaping () -> Void,
            onRatingShortcut: ((Int) -> Void)?,
            keyEventMonitor: KeyEventMonitoring
        ) {
            self.isSlideshowRunning = isSlideshowRunning
            self.viewStore = viewStore
            self.onNavigatePrevious = onNavigatePrevious
            self.onNavigateNext = onNavigateNext
            self.onRatingShortcut = onRatingShortcut
            self.keyEventMonitor = keyEventMonitor
        }

        func startMonitoring() {
            monitor = keyEventMonitor.addLocalKeyDownMonitor { [weak self] event in
                guard let self = self else { return event }

                // Skip other key handling when slideshow is running
                guard !self.isSlideshowRunning else { return event }

                // Do not override native keyboard handling while focus is in text input
                // or other interactive controls.
                let shouldHandleArrowNavigation = KeyEventNavigationPolicy.shouldHandleArrowNavigation(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    firstResponder: event.window?.firstResponder
                )

                // Route arrow keys through injected handlers only when focus context
                // indicates navigation intent.
                switch event.keyCode {
                case 123, 126: // Left / Up
                    guard shouldHandleArrowNavigation else { return event }
                    Task { @MainActor [onNavigatePrevious = self.onNavigatePrevious] in
                        onNavigatePrevious()
                    }
                    return nil
                case 124, 125: // Right / Down
                    guard shouldHandleArrowNavigation else { return event }
                    Task { @MainActor [onNavigateNext = self.onNavigateNext] in
                        onNavigateNext()
                    }
                    return nil
                default:
                    break
                }

                if !(event.window?.firstResponder is NSTextView),
                          let rating = Self.ratingFromKeyEvent(event),
                          (0...5).contains(rating) {
                    Task { @MainActor [weak self] in
                        self?.onRatingShortcut?(rating)
                    }
                    return nil // Consume rating shortcuts to avoid list focus conflicts
                }

                return event // Don't consume other events
            }
        }

        func stopMonitoring() {
            if let monitor = monitor {
                keyEventMonitor.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func updateSlideshowState(_ state: Bool) {
            isSlideshowRunning = state
        }

        func updateNavigationHandlers(previous: @escaping () -> Void, next: @escaping () -> Void) {
            onNavigatePrevious = previous
            onNavigateNext = next
        }

        func updateRatingShortcutHandler(_ handler: ((Int) -> Void)?) {
            onRatingShortcut = handler
        }

        func updateViewStore(_ store: ViewStore) {
            viewStore = store
        }

        private static func ratingFromKeyEvent(_ event: NSEvent) -> Int? {
            switch event.keyCode {
            case 29, 82:
                return 0
            case 18, 83:
                return 1
            case 19, 84:
                return 2
            case 20, 85:
                return 3
            case 21, 86:
                return 4
            case 23, 87:
                return 5
            default:
                return nil
            }
        }
    }
}

private struct ViewerBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let style = ViewerBackgroundVisualStyleResolver.resolve(
            reduceTransparency: reduceTransparency,
            colorContrast: colorSchemeContrast
        )

        if style.usesSolidBackground {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        } else {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.black.opacity(style.gradientTopOpacity),
                Color.black.opacity(style.gradientBottomOpacity)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.03),
                    Color.black.opacity(0.0)
                ]),
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .blendMode(.screen)
            .opacity(style.radialHighlightOpacity)
        )
        }
    }
}

private struct InfoPill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, ViewerStyle.overlayPadding + 2)
            .padding(.vertical, ViewerStyle.overlayPadding)
            .background(Color.black.opacity(0.45))
            .cornerRadius(ViewerStyle.overlayCornerRadius)
    }
}

struct ContentView: View {
    @Environment(\.uiInteractionDependencies) private var uiInteractionDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var imageStore: ImageStore
    @EnvironmentObject var filterStore: FilterStore
    @EnvironmentObject var viewStore: ViewStore
    @EnvironmentObject var galleryStore: GalleryStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var collectionStore: CollectionStore
    @State private var showingCustomOrderEditor = false
    @State private var contextMenuTagEditorSheetItem: ContextMenuTagEditorSheetItem?
    @Binding var showingFilters: Bool
    @State private var toastMessage: String?
    @State private var databaseError: String?
    @State private var showingDatabaseErrorAlert = false
    @State private var ratingInteractionState = RatingInteractionState()

    // Multi-select state for batch tagging
    @State private var selectedImageIDs: Set<String> = []
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedImageIDs: $selectedImageIDs,
                databaseError: $databaseError,
                displayRatingForImage: displayRating(for:),
                onRatingChange: { image, rating in
                    setRating(for: image, rating: rating)
                },
                onAddTags: { image in
                    openContextMenuTagEditor(for: image)
                },
                onExcludeFromBrowsing: { image in
                    excludeFromBrowsing(image)
                }
            )
            .frame(minWidth: 220, idealWidth: 280)
        } detail: {
            MainImageViewer()
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(windowTitle)
        .fullscreenChrome(viewStore: viewStore)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    uiInteractionDependencies.windowCommands.toggleSidebar()
                }) {
                    Image(systemName: "sidebar.leading")
                }
                .accessibilityLabel("Toggle Sidebar")

                Button(action: {
                    if let folderURL = uiInteractionDependencies.folderPicker.pickFolder() {
                        appState.loadImages(from: folderURL)
                    }
                }) {
                    Label("Open Folder", systemImage: "folder")
                }
                .disabled(appState.isSlideshowRunning)
                .accessibilityLabel("Open Folder")

                Button(action: {
                    uiInteractionDependencies.windowCommands.openSettingsWindow()
                }) {
                    Label("Settings", systemImage: "gear")
                }
                .disabled(appState.isSlideshowRunning)
                .accessibilityLabel("Open Settings")
                .accessibilityHint("Configure slideshow interval and preferences")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { appState.navigateToPrevious() }) {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(appState.images.isEmpty || appState.isSlideshowRunning)
                .keyboardShortcut(.leftArrow)
                .accessibilityLabel("Previous Image")
                .accessibilityHint("Navigate to previous image in list")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { appState.navigateToNext() }) {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(appState.images.isEmpty || appState.isSlideshowRunning)
                .keyboardShortcut(.rightArrow)
                .accessibilityLabel("Next Image")
                .accessibilityHint("Navigate to next image in list")
            }

            ToolbarItem(placement: .automatic) {
                let currentImage = currentDisplayImage
                let isFavorite = currentImage?.isFavorite ?? false

                Button(action: {
                    guard let currentImage = currentDisplayImage else { return }
                    let newStatus = !currentImage.isFavorite

                    toggleFavorite(for: currentImage, isFavorite: newStatus)
                }) {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                }
                .disabled(controlsDisabled)
                .keyboardShortcut(".", modifiers: [])
                .accessibilityLabel(isFavorite ? "Unfavorite" : "Favorite")
                .accessibilityIdentifier("favorite-toggle")
                .accessibilityHint(isFavorite ? "Remove from favorites" : "Mark image as favorite")
                .help(databaseError ?? "Mark image as favorite or remove it from favorites")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { appState.toggleSlideshow() }) {
                    Label(appState.isSlideshowRunning ? "Stop Slideshow" : "Start Slideshow",
                          systemImage: appState.isSlideshowRunning ? "pause.circle.fill" : "play.circle.fill")
                }
                .disabled(appState.images.isEmpty)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(appState.isSlideshowRunning ? "Stop Slideshow" : "Start Slideshow")
                .accessibilityHint(appState.isSlideshowRunning ? "Stop automatic slideshow" : "Start automatic slideshow")
                .accessibilityIdentifier("slideshow-toggle")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { appState.toggleShuffle() }) {
                    Label(appState.isShuffleEnabled ? "Shuffle On" : "Shuffle Off",
                          systemImage: appState.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle.circle")
                }
                .disabled(appState.images.isEmpty)
                .accessibilityLabel(appState.isShuffleEnabled ? "Shuffle Enabled" : "Shuffle Disabled")
                .accessibilityHint(appState.isShuffleEnabled ? "Disable shuffle mode" : "Enable shuffle mode")
                .accessibilityIdentifier("shuffle-toggle")
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(AppState.SortOrder.allCases, id: \.self) { order in
                        Button(action: { appState.setSortOrder(order) }) {
                            HStack {
                                Text(order.rawValue)
                                if appState.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button(action: { showingCustomOrderEditor = true }) {
                        Label("Edit Custom Order...", systemImage: "list.bullet")
                    }
                    .disabled(appState.sortOrder != .custom)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .disabled(appState.isSlideshowRunning)
                .accessibilityLabel("Sort Images")
                .accessibilityHint("Change image sort order")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { showingFilters.toggle() }) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                        .overlay(alignment: .topTrailing) {
                            if filterStore.activeFilterCount > 0 {
                                Text("\(filterStore.activeFilterCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(2)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                        }
                }
                .disabled(appState.images.isEmpty)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .accessibilityLabel("Show Filters")
                .accessibilityHint("Show or hide the filters panel")
            }

            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 4) {
                    ForEach([25, 50, 100, 200, 400], id: \.self) { percent in
                        Button(action: {
                            withAnimation(MotionPreferenceResolver.zoomAnimation(reduceMotion: reduceMotion)) {
                                viewStore.setZoomPreset(Double(percent))
                            }
                        }) {
                            Text("\(percent)%")
                                .font(.system(size: 10))
                                .frame(width: 32)
                        }
                        .disabled(appState.images.isEmpty)
                        .help("\(percent)% zoom")
                        .accessibilityLabel("\(percent)% zoom")
                    }

                    Divider()

                    Slider(
                        value: $viewStore.currentZoom,
                        in: 0.1...5.0,
                        step: 0.1
                    )
                    .frame(width: 120)
                    .help("Zoom: \(Int(viewStore.currentZoom * 100))%")
                    .accessibilityLabel("Zoom slider")
                    .accessibilityValue("\(Int(viewStore.currentZoom * 100)) percent")
                }
            }

        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(NSColor.windowBackgroundColor), for: .windowToolbar)
        .sheet(isPresented: $showingCustomOrderEditor) {
            CustomOrderEditor()
        }
        .sheet(item: $contextMenuTagEditorSheetItem) { sheetItem in
            ContextMenuTagEditor(targetImageURLs: sheetItem.targetImageURLs)
                .environmentObject(tagStore)
        }
        .sheet(isPresented: $viewStore.showInfoPanel) {
            if let currentImage = appState.images[safe: appState.currentImageIndex] {
                InfoPanel(image: currentImage)
            }
        }
        .popover(isPresented: $showingFilters, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            FilterPopover(showsDismissControls: false)
                .environmentObject(filterStore)
                .environmentObject(tagStore)
                .environmentObject(collectionStore)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        }
        .overlay(alignment: .bottom) {
            if let toastMessage = toastMessage {
                ToastView(message: toastMessage)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
        .alert("Library Error", isPresented: $showingDatabaseErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(databaseError ?? "An unknown error occurred.")
        }
        .modifier(
            KeyEventHandlingModifier(
                isSlideshowRunning: appState.isSlideshowRunning,
                onNavigatePrevious: { navigateToPreviousEligibleImage() },
                onNavigateNext: { navigateToNextEligibleImage() },
                onRatingShortcut: handleRatingShortcut,
                keyEventMonitor: uiInteractionDependencies.keyEventMonitor
            )
        )
        .focusedSceneValue(\.imageBrowserCommandContext, commandContext)
        .onChange(of: galleryStore.snapshot.currentDisplayImage) { _, newDisplayImage in
            syncSidebarSelectionWithDisplay(newDisplayImage)
        }
        .onChange(of: selectedImageIDs) { _, newSelection in
            syncDisplayWithSidebarSelection(newSelection)
        }
        .onChange(of: databaseError) { _, newValue in
            if newValue != nil {
                showingDatabaseErrorAlert = true
            }
        }
        .onChange(of: toastMessage) { _, newMessage in
            guard let newMessage else { return }

            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                await MainActor.run {
                    if toastMessage == newMessage {
                        withAnimation {
                            toastMessage = nil
                        }
                    }
                }
            }
        }
        .onAppear {
            if appState.images.isEmpty && appState.selectedFolder == nil {
                // Show welcome message or prompt to select folder
            }
        }
    }

    private var controlsDisabled: Bool {
        appState.images.isEmpty || appState.isSlideshowRunning || databaseError != nil
    }

    private var windowTitle: String {
        if let folderName = appState.selectedFolder?.lastPathComponent, !folderName.isEmpty {
            return folderName
        }

        return "ImageBrowser"
    }

    private var commandContext: ImageBrowserCommandContext {
        ImageBrowserCommandContext(
            canOpenFolder: !appState.isSlideshowRunning,
            hasImages: !appState.images.isEmpty,
            canNavigate: !appState.images.isEmpty && !appState.isSlideshowRunning,
            canEditMetadata: !controlsDisabled && currentDisplayImage != nil,
            isSlideshowRunning: appState.isSlideshowRunning,
            isFilterPanelPresented: showingFilters,
            sortOrder: appState.sortOrder,
            isShuffleEnabled: appState.isShuffleEnabled,
            canReshuffle: appState.isShuffleEnabled && appState.hasEligibleImages,
            openFolder: {
                if let folderURL = uiInteractionDependencies.folderPicker.pickFolder() {
                    appState.loadImages(from: folderURL)
                }
            },
            toggleFilters: { showingFilters.toggle() },
            navigateToPrevious: { appState.navigateToPrevious() },
            navigateToNext: { appState.navigateToNext() },
            toggleFavorite: toggleFavoriteForCurrentImage,
            toggleSlideshow: { appState.toggleSlideshow() },
            stopSlideshow: { appState.stopSlideshow() },
            toggleShuffle: { appState.toggleShuffle() },
            reshuffle: { appState.reshuffleVisibleOrder() },
            editCustomOrder: { showingCustomOrderEditor = true },
            setSortOrder: { order in appState.setSortOrder(order) }
        )
    }

    private func handleRatingShortcut(_ rating: Int) {
        guard !controlsDisabled,
              let currentImage = currentDisplayImage else {
            return
        }

        setRating(for: currentImage, rating: rating)
    }

    private func openContextMenuTagEditor(for image: DisplayImage) {
        let targetURLs = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: image.id,
            selectedImageIDs: selectedImageIDs,
            visibleImages: galleryStore.snapshot.visibleImages
        )

        guard !targetURLs.isEmpty else { return }

        // Create sheet item with URLs - SwiftUI .sheet(item:) captures this value
        // when the sheet is presented, not when the view body is rendered
        contextMenuTagEditorSheetItem = ContextMenuTagEditorSheetItem(targetImageURLs: targetURLs)
    }

    private var currentDisplayImage: DisplayImage? {
        galleryStore.snapshot.currentDisplayImage
    }

    private func toggleFavoriteForCurrentImage() {
        guard let currentImage = currentDisplayImage else {
            return
        }

        toggleFavorite(for: currentImage, isFavorite: !currentImage.isFavorite)
    }

    // MARK: - Selection Synchronization

    /// Syncs sidebar thumbnail selection with the currently displayed image.
    ///
    /// ## Single Source of Truth Pattern
    ///
    /// Keyboard navigation follows this flow to ensure synchronization:
    ///
    /// 1. **Arrow Keys (Left/Right/Up/Down)** (KeyEventHandlingView):
    ///    - User presses arrow key
    ///    - KeyEventHandlingView calls appState.navigateToPrevious() or navigateToNext()
    ///    - This updates appState.currentImageIndex
    ///    - GalleryStore observes currentImageIndex change and recomputes snapshot
    ///    - Snapshot's currentDisplayImage updates to new index
    ///    - **This onChange handler fires** and updates selectedImageIDs
    ///    - Result: Thumbnail selection stays in sync with displayed image ✓
    ///
    /// 2. **Direct Thumbnail Selection** (mouse click):
    ///    - User selects a thumbnail
    ///    - SwiftUI List changes selectedImageIDs binding
    ///    - **syncDisplayWithSidebarSelection onChange fires** and calls navigateToIndex
    ///    - This updates appState.currentImageIndex
    ///    - GalleryStore recomputes snapshot with new currentDisplayImage
    ///    - This onChange handler fires, but guard prevents infinite loop
    ///    - Result: Displayed image stays in sync with thumbnail selection ✓
    ///
    /// This bidirectional synchronization ensures that:
    /// - Pressing any arrow key updates BOTH thumbnail highlight AND displayed image
    /// - Clicking a thumbnail updates both selection AND display
    /// - There's always a single source of truth (currentImageIndex drives both states)
    ///
    /// - Parameter newDisplayImage: The newly displayed image from galleryStore
    private func syncSidebarSelectionWithDisplay(_ newDisplayImage: DisplayImage?) {
        guard let imageID = newDisplayImage?.id else {
            selectedImageIDs = []
            return
        }

        // Only update selection if it's different (prevents infinite loop)
        guard selectedImageIDs != [imageID] else { return }

        selectedImageIDs = [imageID]
    }

    /// Syncs the displayed image with the sidebar thumbnail selection.
    ///
    /// This is the reverse direction of syncSidebarSelectionWithDisplay.
    /// When a user clicks a thumbnail or uses up/down arrows (which SwiftUI List
    /// handles natively), this ensures the main image viewer updates to show that image.
    ///
    /// See syncSidebarSelectionWithDisplay documentation for the full bidirectional
    /// synchronization flow and single source of truth pattern.
    ///
    /// - Parameter newSelection: The set of selected image IDs from the sidebar
    private func syncDisplayWithSidebarSelection(_ newSelection: Set<String>) {
        guard let imageID = newSelection.first else { return }

        // Only navigate if different from current display (prevents infinite loop)
        guard imageID != galleryStore.snapshot.currentDisplayImage?.id else { return }

        // Find the full index and check if image is excluded
        if let fullIndex = galleryStore.snapshot.fullIndex(for: imageID) {
            let selectedImage = galleryStore.snapshot.visibleImages.first { $0.id == imageID }

            // If selected image is excluded, skip to nearest eligible image
            if let selectedImage = selectedImage, selectedImage.isExcluded {
                // Navigate to the excluded image first, then skip to next eligible
                appState.navigateToIndex(fullIndex)
                _ = appState.navigateToNextDisplayableImage()

                // Update the sidebar selection to match the displayed image
                if let currentDisplayImage = galleryStore.snapshot.currentDisplayImage {
                    selectedImageIDs = [currentDisplayImage.id]
                }
            } else {
                // Not excluded - navigate directly
                appState.navigateToIndex(fullIndex)
            }
        }
    }

    private func navigateToNextEligibleImage() {
        if appState.isShuffleEnabled {
            appState.navigateToNext()
        } else {
            navigateToEligibleImage(step: 1)
        }
    }

    private func navigateToPreviousEligibleImage() {
        if appState.isShuffleEnabled {
            appState.navigateToPrevious()
        } else {
            navigateToEligibleImage(step: -1)
        }
    }

    private func navigateToEligibleImage(step: Int) {
        let visibleImages = galleryStore.snapshot.visibleImages
        guard !visibleImages.isEmpty else { return }

        let currentID = galleryStore.snapshot.currentDisplayImage?.id
        let startIndex = visibleImages.firstIndex { $0.id == currentID } ?? 0
        let totalCount = visibleImages.count

        for offset in 1...totalCount {
            let candidateIndex = (startIndex + (step * offset) + (totalCount * 2)) % totalCount
            let candidate = visibleImages[candidateIndex]
            guard !candidate.isExcluded && !candidate.isUnsupportedFormat else {
                continue
            }

            appState.navigateToIndex(candidate.fullIndex)
            return
        }
    }

    private func displayRating(for image: DisplayImage) -> Int {
        ratingInteractionState.displayRating(for: image.id, persistedRating: image.rating)
    }

    private func toggleFavorite(for image: DisplayImage, isFavorite: Bool) {
        Task {
            let success = await imageStore.updateFavoriteWithRetry(for: metadataKey(for: image.url), isFavorite: isFavorite)

            await MainActor.run {
                if success {
                    databaseError = nil
                    withAnimation {
                        toastMessage = isFavorite ? "Added to favorites" : "Removed from favorites"
                    }
                } else {
                    databaseError = "Database unavailable. Favorite and rating controls are temporarily disabled."
                    withAnimation {
                        toastMessage = "Could not save favorite change"
                    }
                }
            }
        }
    }

    private func setRating(for image: DisplayImage, rating: Int) {
        let generation = ratingInteractionState.recordPending(imageID: image.id, rating: rating)

        Task {
            let success = await imageStore.updateRatingWithRetry(for: metadataKey(for: image.url), rating: rating)

            await MainActor.run {
                guard ratingInteractionState.completeRequest(imageID: image.id, generation: generation, didSucceed: success) else {
                    return
                }

                if success {
                    databaseError = nil
                    withAnimation {
                        toastMessage = rating == 0 ? "Rating cleared" : "Rated \(rating) stars"
                    }
                } else {
                    databaseError = "Database unavailable. Favorite and rating controls are temporarily disabled."
                    withAnimation {
                        toastMessage = "Could not save rating"
                    }
                }
            }
        }
    }

    private func excludeFromBrowsing(_ image: DisplayImage) {
        Task {
            let result = await ContextMenuExclusionModel.excludeTargets(
                clickedImageID: image.id,
                selectedImageIDs: selectedImageIDs,
                visibleImages: galleryStore.snapshot.visibleImages,
                persist: { imageURL in
                    await imageStore.updateExcludedWithRetry(for: imageURL, isExcluded: true)
                }
            )

            await MainActor.run {
                if result.successfulExclusionCount > 0 {
                    appState.applyExcludedState(for: result.successfulTargetURLs, isExcluded: true)
                    databaseError = nil
                    if let toast = result.toastMessage {
                        withAnimation {
                            toastMessage = toast
                        }
                    }
                    return
                }

                databaseError = "Database unavailable. Favorite and rating controls are temporarily disabled."
                withAnimation {
                    toastMessage = "Could not save exclusion change"
                }
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var filterStore: FilterStore
    @EnvironmentObject var galleryStore: GalleryStore
    @EnvironmentObject var collectionStore: CollectionStore
    @EnvironmentObject var imageStore: ImageStore
    @Environment(\.displayScale) private var displayScale
    @Binding var selectedImageIDs: Set<String>
    @Binding var databaseError: String?
    var displayRatingForImage: (DisplayImage) -> Int
    var onRatingChange: (DisplayImage, Int) -> Void
    var onAddTags: (DisplayImage) -> Void
    var onExcludeFromBrowsing: (DisplayImage) -> Void

    var body: some View {
        let displayState = SidebarDisplayStateResolver.resolve(
            isLoadingImages: appState.isLoadingImages,
            visibleImageCount: galleryStore.snapshot.visibleImages.count,
            totalImageCount: appState.images.count,
            hasActiveCollectionOrFilters: hasActiveCollectionOrFilters,
            hasEligibleImages: appState.hasEligibleImages
        )

        VStack(spacing: 0) {
            // Smart Collections section
            SmartCollectionsSidebar()

            Divider()

            // Excluded Images review section
            excludedReviewSection

            Divider()

            if appState.isExcludedReviewMode {
                excludedReviewGrid
            } else if displayState == .loading {
                loadingState
            } else if displayState == .noResults {
                emptyFiltersState
            } else if displayState == .noImagesLoaded {
                noImagesLoadedState
            } else if displayState == .noEligible {
                noEligibleState
            } else {
                thumbnailGrid
            }
        }
        .onAppear {
            let maxPixelSize = max(1, Int(defaultThumbnailSize * displayScale))
            appState.updateThumbnailPrefetchSize(maxPixelSize)
        }
        .onChange(of: displayScale) { _, newScale in
            let maxPixelSize = max(1, Int(defaultThumbnailSize * newScale))
            appState.updateThumbnailPrefetchSize(maxPixelSize)
        }
    }

    // MARK: - Computed State Views

    /// Loading state shown while images are being loaded
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading images...")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("This may take a moment for large folders")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Empty state shown when filters exclude all images
    private var emptyFiltersState: some View {
        EmptyStateView(
            title: "No Results",
            message: "No images match your current filters. Try adjusting the filter criteria or clear all filters to see more images.",
            systemImage: "magnifyingglass",
            actionTitle: "Show All Images"
        ) {
            clearAllFiltersAndCollection(filterStore: filterStore, collectionStore: collectionStore)
        }
    }

    /// Empty state shown when no images are loaded at all
    private var noImagesLoadedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No images loaded")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Select a folder to begin")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Empty state shown when all visible images are excluded
    private var noEligibleState: some View {
        EmptyStateView(
            title: "No eligible images to display",
            message: "All images in the current folder are excluded from browsing. You can review and restore excluded images to make them visible again.",
            systemImage: "eye.slash",
            actionTitle: "Review Excluded Images"
        ) {
            // Placeholder for Phase 17: Excluded Review & Recovery
            // This will open the review surface for excluded images
        }
    }

    /// Normal thumbnail grid with subtitle and filtered images
    private var thumbnailGrid: some View {
        VStack(spacing: 0) {
            // Grid subtitle showing filtered count and selected count
            HStack {
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("sidebar-status-label")
                    .accessibilityValue(subtitleText)

                if !selectedImageIDs.isEmpty {
                    Text("· \(selectedImageIDs.count) selected")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }

                Spacer()

                if hasActiveCollectionOrFilters {
                    Button("Show All Images") {
                        clearAllFiltersAndCollection(filterStore: filterStore, collectionStore: collectionStore)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            List(selection: $selectedImageIDs) {
                ForEach(galleryStore.snapshot.visibleImages) { image in
                    SidebarItemView(
                        image: image,
                        displayedRating: displayRatingForImage(image),
                        index: image.fullIndex,
                        totalCount: galleryStore.snapshot.totalCount,
                        databaseError: $databaseError,
                        onRatingChange: onRatingChange
                    )
                        .tag(image.id)
                        .contextMenu {
                            Button("Set as First") {
                                appState.navigateToIndex(image.fullIndex)
                            }

                            Button("Add Tags...") {
                                onAddTags(image)
                            }

                            Button("Exclude from Browsing") {
                                onExcludeFromBrowsing(image)
                            }
                            .disabled(image.isExcluded || databaseError != nil)
                        }
                }
            }
            .listStyle(.sidebar)
            .disabled(appState.isSlideshowRunning)
        }
    }

    /// Subtitle text showing active collection or filter state
    private var subtitleText: String {
        excludedReviewMetrics.subtitleText
    }

    private var excludedReviewMetrics: ExcludedReviewSidebarMetrics {
        ExcludedReviewSidebarMetrics.make(
            appStateImages: appState.images,
            mergedExcludedImages: galleryStore.excludedImages,
            activeCollectionName: galleryStore.snapshot.activeCollectionName,
            filteredCount: galleryStore.snapshot.filteredCount,
            unfilteredTotalCount: galleryStore.snapshot.unfilteredTotalCount,
            isFilteringActive: hasActiveCollectionOrFilters
        )
    }

    private var hasActiveCollectionOrFilters: Bool {
        collectionStore.activeCollection != nil || filterStore.isActive
    }

    /// Excluded Images section for entering/exiting excluded review mode
    private var excludedReviewSection: some View {
        return VStack(spacing: 0) {
            Button {
                if appState.isExcludedReviewMode {
                    appState.exitExcludedReviewMode()
                } else {
                    appState.enterExcludedReviewMode()
                }
            } label: {
                HStack {
                    Image(systemName: appState.isExcludedReviewMode ? "eye.slash.fill" : "eye.slash")
                        .foregroundColor(.secondary)
                    Text("Excluded Images")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(excludedReviewMetrics.excludedCount) excluded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: appState.isExcludedReviewMode ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("excluded-review-toggle")
            .help("Review and restore excluded images")
        }
    }

    /// Grid showing only excluded images during review mode
    /// Note: Full thumbnail display with DisplayImage conversion will be implemented in Plan 17-02
    private var excludedReviewGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reviewing excluded images")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    appState.exitExcludedReviewMode()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.accentColor)
                .accessibilityIdentifier("excluded-review-done")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            let excludedImages = galleryStore.excludedImages

            if excludedImages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("No excluded images")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("All images in this folder are visible in normal browsing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(excludedImages, id: \.id) { image in
                        HStack(spacing: 8) {
                            ThumbnailView(
                                image: image,
                                size: 40,
                                presentation: ThumbnailPresentation.reviewMode(isExcluded: image.isExcluded)
                            )
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(image.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text("Excluded")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.orange)
                                .help("Excluded from browsing")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Restore") {
                                restoreFromExclusion(image)
                            }
                        }
                        .onTapGesture {
                            appState.navigateToIndex(image.fullIndex)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func restoreFromExclusion(_ image: DisplayImage) {
        Task {
            let result = await ContextMenuExclusionModel.restoreTargets(
                clickedImageID: image.id,
                selectedImageIDs: selectedImageIDs,
                visibleImages: galleryStore.excludedImages,
                persist: { imageURL in
                    await imageStore.updateExcludedWithRetry(for: imageURL, isExcluded: false)
                }
            )

            await MainActor.run {
                if result.successfulExclusionCount > 0 {
                    appState.applyExcludedState(for: result.successfulTargetURLs, isExcluded: false)
                    databaseError = nil
                    return
                }

                databaseError = "Database unavailable. Favorite and rating controls are temporarily disabled."
            }
        }
    }
}

struct SidebarItemView: View {
    let image: DisplayImage
    let displayedRating: Int
    let index: Int
    let totalCount: Int
    @Binding var databaseError: String?
    var onRatingChange: (DisplayImage, Int) -> Void

    private var itemAccessibilityLabel: String {
        let browsingStatus = image.isExcluded ? "excluded from browsing" : "included in browsing"

        if image.hasLoadError {
            return "Image failed to load, \(image.name), \(displayedRating) stars, \(browsingStatus)"
        }

        return "\(image.name), \(index + 1) of \(totalCount), \(displayedRating) stars, \(browsingStatus)"
    }

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailView(image: image, size: defaultThumbnailSize)
                .frame(width: defaultThumbnailSize, height: defaultThumbnailSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(image.name)
                    .font(.caption)
                    .lineLimit(1)
                    .accessibilityIdentifier("sidebar-filename-\(index)")
                Text("\(index + 1) of \(totalCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            StarRatingView(displayedRating: displayedRating, onSetRating: { rating in
                onRatingChange(image, rating)
            })
            .disabled(databaseError != nil)
            .help(databaseError ?? "Tap stars to set rating")

            if image.hasLoadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
                    .help("Failed to load")
                    .accessibilityIdentifier("error-indicator")
            }
        }
        .accessibilityLabel(itemAccessibilityLabel)
        .accessibilityHint(image.hasLoadError ? "Could not read image file" : "Double click to view image")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sidebar-item-\(index)")
    }
}

struct StarRatingView: View {
    let displayedRating: Int
    let onSetRating: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    let newRating = star == displayedRating ? 0 : star
                    onSetRating(newRating)
                } label: {
                    Image(systemName: star <= displayedRating ? "star.fill" : "star")
                        .foregroundColor(star <= displayedRating ? .yellow : .gray.opacity(0.5))
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .accessibilityLabel("Rating: \(displayedRating) stars")
        .accessibilityValue("\(displayedRating) of 5")
        .accessibilityHint("Tap stars to set rating")
    }
}

struct MainImageViewer: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewStore: ViewStore
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastGestureScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var retryLoadTrigger = 0
    @State private var renderedImage: CGImage?
    @State private var loadedMainPixelSize: Int?
    @State private var loadFailed = false
    @State private var isHoveringOverlay = false

    private var isUITestMode: Bool {
        ProcessInfo.processInfo.environment["IMAGEBROWSER_UI_TEST_MODE"] == "1"
    }
    
    var body: some View {
        ZStack {
            ViewerBackground()
            
            if appState.images.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No Folder Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Click 'Open Folder' to start browsing images")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("No folder selected")
                .accessibilityHint("Click Open Folder button to select an image folder")
                .accessibilityAddTraits(.isStaticText)
            } else if let currentImage = appState.images[safe: appState.currentImageIndex] {
                GeometryReader { geometry in
                    let viewportMaxPixelSize = max(1, Int(max(geometry.size.width, geometry.size.height) * displayScale))
                    let baseMainPixelSize = MainImageRequestPlanner.basePixelSize(
                        viewportMaxPixelSize: viewportMaxPixelSize,
                        normalize: appState.normalizedMainImagePixelSize
                    )
                    let targetMainPixelSize = MainImageRequestPlanner.targetPixelSize(
                        viewportMaxPixelSize: viewportMaxPixelSize,
                        zoomMode: viewStore.zoomMode,
                        currentZoom: viewStore.currentZoom,
                        normalize: appState.normalizedMainImagePixelSize
                    )
                    let baseTaskID = "\(currentImage.id)|base|\(baseMainPixelSize)|\(retryLoadTrigger)"
                    let upgradeTaskID = "\(currentImage.id)|upgrade|\(targetMainPixelSize)|\(retryLoadTrigger)"
                    let effectiveScale = MainImageZoomScaleResolver.effectiveScale(
                        zoomMode: viewStore.zoomMode,
                        currentZoom: viewStore.currentZoom
                    )

                    ZStack {
                        if let renderedImage = renderedImage {
                            Image(decorative: renderedImage, scale: displayScale)
                                .resizable()
                                .interpolation(Image.Interpolation.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .accessibilityIdentifier("main-image")
                                .scaleEffect(effectiveScale)
                                .animation(
                                    MotionPreferenceResolver.zoomAnimation(reduceMotion: reduceMotion),
                                    value: effectiveScale
                                )
                                .offset(offset)
                                .accessibilityLabel("Image: \(currentImage.name)")
                                .accessibilityHint("\(appState.currentImageIndex + 1) of \(appState.images.count). Double tap to reset zoom. Scroll with two fingers to pan.")
                                .accessibilityAddTraits(.isImage)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                                           height: lastOffset.height + value.translation.height)
                                        }
                                        .onEnded { _ in
                                            withAnimation(
                                                MotionPreferenceResolver.standardAnimation(reduceMotion: reduceMotion)
                                            ) {
                                                lastOffset = offset
                                            }
                                        }
                                )
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            viewStore.currentZoom = lastGestureScale * value
                                            // Clear refit flag when user manually zooms
                                            if viewStore.needsRefit {
                                                viewStore.needsRefit = false
                                            }
                                        }
                                        .onEnded { value in
                                            withAnimation {
                                                lastGestureScale = viewStore.currentZoom
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation {
                                        viewStore.actualSize()
                                        offset = .zero
                                        lastOffset = .zero
                                        lastGestureScale = 1.0
                                    }
                                }
                        } else if loadFailed {
                            let isUnsupportedFormat = appState.unsupportedImages.contains(currentImage.url)
                            InfoPill {
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(.secondary)
                                        .help(isUnsupportedFormat ? "This file type is visible in the browser, but this Mac cannot render it." : "Image file could not be loaded - it may be corrupted or in an unsupported format")
                                        .accessibilityIdentifier("error-indicator")
                                    Text(isUnsupportedFormat ? "Unsupported Format" : "Cannot Display Image")
                                        .font(.headline)
                                        .accessibilityIdentifier("error-display")
                                    Text(currentImage.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(isUnsupportedFormat ? "This file type is visible in the browser, but this Mac cannot render it." : "File may be corrupted or unsupported")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Button(action: {
                                        retryLoadTrigger += 1
                                    }) {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Retry loading image")
                                    .accessibilityHint("Attempt to load image again")
                                }
                            }
                            .accessibilityLabel("Cannot display image: \(currentImage.name)")
                            .accessibilityHint("File may be corrupted or unsupported. Retry button available.")
                            .accessibilityAddTraits(.isStaticText)
                        } else {
                            InfoPill {
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.1)
                                    Text("Loading image")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .accessibilityLabel("Loading image")
                        }
                    }
                    .task(id: baseTaskID) {
                        await MainActor.run {
                            loadFailed = false
                            renderedImage = nil
                            loadedMainPixelSize = nil
                        }

                        let image = await appState.loadDownsampledImage(
                            for: currentImage,
                            maxPixelSize: baseMainPixelSize,
                            cache: .main
                        )
                        if Task.isCancelled {
                            return
                        }

                        await MainActor.run {
                            appState.recordLoadResult(for: currentImage, image: image)

                            if image == nil,
                               appState.unsupportedImages.contains(currentImage.url),
                               appState.navigateToNextDisplayableImage() {
                                renderedImage = nil
                                loadFailed = false
                                return
                            }

                            renderedImage = image
                            loadedMainPixelSize = image == nil ? nil : baseMainPixelSize
                            loadFailed = image == nil
                        }

                        if image != nil {
                            appState.prefetchMainImages(
                                around: appState.currentImageIndex,
                                maxPixelSize: baseMainPixelSize
                            )
                        }
                    }
                    .task(id: upgradeTaskID) {
                        let shouldStartUpgrade = await MainActor.run {
                            MainImageRequestPlanner.shouldUpgradeImage(
                                loadedPixelSize: loadedMainPixelSize,
                                basePixelSize: baseMainPixelSize,
                                targetPixelSize: targetMainPixelSize
                            )
                        }
                        guard shouldStartUpgrade else { return }

                        let debounceNanoseconds = MainImageRequestPlanner.upgradeDebounceNanoseconds(
                            zoomMode: viewStore.zoomMode
                        )
                        if debounceNanoseconds > 0 {
                            try? await Task.sleep(nanoseconds: debounceNanoseconds)
                            if Task.isCancelled {
                                return
                            }
                        }

                        let image = await appState.loadDownsampledImage(
                            for: currentImage,
                            maxPixelSize: targetMainPixelSize,
                            cache: .main
                        )
                        if Task.isCancelled || image == nil {
                            return
                        }

                        await MainActor.run {
                            guard appState.images[safe: appState.currentImageIndex]?.id == currentImage.id else {
                                return
                            }
                            guard MainImageRequestPlanner.shouldUpgradeImage(
                                loadedPixelSize: loadedMainPixelSize,
                                basePixelSize: baseMainPixelSize,
                                targetPixelSize: targetMainPixelSize
                            ) else {
                                return
                            }

                            renderedImage = image
                            loadedMainPixelSize = targetMainPixelSize
                            loadFailed = false
                        }
                    }
                }
                .clipped()
                
                // Image info overlay
                VStack {
                    Spacer()
                    
                    HStack {
                        InfoPill {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentImage.name)
                                    .font(.headline)
                                Text("\(appState.currentImageIndex + 1) / \(appState.images.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityIdentifier("current-image-position")
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("current-image-info")
                            .accessibilityLabel("Current image: \(currentImage.name)")
                            .accessibilityValue("\(appState.currentImageIndex + 1) of \(appState.images.count)")
                        }
                        .opacity(isHoveringOverlay ? 0.98 : 0.85)
                        
                        Spacer()
                        
                        if appState.isSlideshowRunning {
                            InfoPill {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundColor(.green)
                                    Text("\(Int(appState.slideshowInterval))s")
                                        .font(.caption)
                                }
                            }
                            .opacity(isHoveringOverlay ? 0.98 : 0.85)
                        }
                    }
                    .padding()
                    .onHover { hovering in
                        isHoveringOverlay = hovering
                    }
                }
            }

            if isUITestMode {
                VStack {
                    HStack {
                        Text("Fullscreen State")
                            .font(.caption2)
                            .accessibilityIdentifier("fullscreen-state")
                            .accessibilityLabel("Fullscreen State")
                            .accessibilityValue(viewStore.isFullscreen ? "fullscreen" : "windowed")
                            .opacity(0.01)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: appState.currentImageIndex) { _, _ in
            // Reset pan offset when changing images, but preserve zoom level
            withAnimation {
                offset = .zero
                lastOffset = .zero
                lastGestureScale = viewStore.currentZoom
            }
        }
        .onChange(of: viewStore.zoomMode) { _, newMode in
            // Reset zoom state when entering fit mode
            if newMode == .fit {
                withAnimation {
                    offset = .zero
                    lastOffset = .zero
                    lastGestureScale = 1.0
                }
            }
        }
        .onChange(of: viewStore.needsRefit) { _, needsRefit in
            // Reset zoom state when refit is requested (e.g., from Fit to Both menu)
            if needsRefit {
                withAnimation {
                    offset = .zero
                    lastOffset = .zero
                    lastGestureScale = 1.0
                }
                // Clear the flag after handling
                viewStore.needsRefit = false
            }
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

struct ThumbnailView: View {
    let image: DisplayImage
    let size: CGFloat
    let presentation: ThumbnailPresentation
    @EnvironmentObject var appState: AppState
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnailImage: CGImage?
    @State private var isHovering = false

    init(image: DisplayImage, size: CGFloat, presentation: ThumbnailPresentation? = nil) {
        self.image = image
        self.size = size
        self.presentation = presentation ?? .normalBrowsing(isExcluded: image.isExcluded)
    }

    var body: some View {
        let maxPixelSize = max(1, Int(size * displayScale))

        ZStack {
            if let thumbnailImage = thumbnailImage {
                Image(decorative: thumbnailImage, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .cornerRadius(4)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }

            if image.isFavorite {
                VStack {
                    Spacer()

                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 14))

                        Spacer()
                    }
                    .padding(4)
                }
            }

            if isHovering && image.rating > 0 {
                VStack {
                    Spacer()

                    HStack {
                        HStack(spacing: 1) {
                            ForEach(1...image.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 10))
                            }
                        }
                        .padding(2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(3)

                        Spacer()
                    }
                    .padding(4)
                }
            }

            if presentation.showsExcludedBadge {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(4)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .opacity(presentation.opacity)
        .onHover { hovering in
            isHovering = hovering
        }
        .task(id: "\(image.id)|\(maxPixelSize)") {
            appState.reportThumbnailVisibility(index: image.fullIndex, maxPixelSize: maxPixelSize)
            let image = await appState.loadDownsampledImage(from: image.url, maxPixelSize: maxPixelSize, cache: .thumbnail)
            if Task.isCancelled {
                return
            }
            await MainActor.run {
                thumbnailImage = image
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var slideshowIntervalValue: Double = 3.0
    @State private var selectedSortOrder: AppState.SortOrder = .name
    @State private var didInitializeSettings = false
    
    var body: some View {
        Form {
            Section("Playback") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Slideshow Interval")
                        .font(.headline)

                    HStack {
                        Slider(value: $slideshowIntervalValue, in: 1...10, step: 0.5)
                        Text(String(format: "%.1f", slideshowIntervalValue) + "s")
                            .frame(width: 44)
                    }

                    Text("Time between slides in slideshow mode.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Library") {
                Picker("Sort Order", selection: $selectedSortOrder) {
                    ForEach(AppState.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420, height: 280)
        .onAppear {
            didInitializeSettings = false
            slideshowIntervalValue = appState.slideshowInterval
            selectedSortOrder = appState.sortOrder
            didInitializeSettings = true
        }
        .onChange(of: slideshowIntervalValue) { _, newValue in
            guard didInitializeSettings else { return }
            appState.updateSlideshowInterval(newValue)
        }
        .onChange(of: selectedSortOrder) { _, newValue in
            guard didInitializeSettings else { return }
            appState.setSortOrder(newValue)
        }
    }
}

struct CustomOrderEditor: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var editingOrder: [String] = []

    private var imageNameByKey: [String: String] {
        Dictionary(uniqueKeysWithValues: appState.images.map { ($0.id, $0.name) })
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Custom Image Order")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Drag to reorder images in your preferred sequence")
                .font(.caption)
                .foregroundColor(.secondary)
            
            List {
                ForEach(Array(editingOrder.enumerated()), id: \.offset) { _, imageKey in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                        Text(imageNameByKey[imageKey] ?? URL(string: imageKey)?.lastPathComponent ?? imageKey)
                            .font(.caption)
                    }
                }
                .onMove { source, destination in
                    editingOrder.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(height: 300)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Apply") {
                    appState.updateCustomOrder(editingOrder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .onAppear {
            editingOrder = appState.images.map { $0.id }
        }
    }
}

#if ENABLE_PREVIEWS
#Preview {
    let container = PreviewContainer.shared

    return ContentView(showingFilters: .constant(false))
        .environment(\.uiInteractionDependencies, container.uiInteractionDependencies)
        .environmentObject(container.appState)
        .environmentObject(container.imageStore)
        .environmentObject(container.filterStore)
        .environmentObject(container.viewStore)
        .environmentObject(container.galleryStore)
        .environmentObject(container.tagStore)
        .environmentObject(container.collectionStore)
}
#endif
