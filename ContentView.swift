import SwiftUI
import AppKit

private let defaultThumbnailSize: CGFloat = 50

private enum ViewerStyle {
    static let overlayCornerRadius: CGFloat = 8
    static let overlayPadding: CGFloat = 8
    static let overlayHorizontalSpacing: CGFloat = 8
}

struct KeyEventHandlingModifier: ViewModifier {
    let isSlideshowRunning: Bool
    @EnvironmentObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .background(KeyEventHandlingView(isSlideshowRunning: isSlideshowRunning))
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    let isSlideshowRunning: Bool
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(isSlideshowRunning: isSlideshowRunning, appState: appState)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateSlideshowState(isSlideshowRunning)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    class Coordinator {
        var monitor: Any?
        var isSlideshowRunning: Bool
        weak var appState: AppState?

        init(isSlideshowRunning: Bool, appState: AppState) {
            self.isSlideshowRunning = isSlideshowRunning
            self.appState = appState
        }

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self,
                      !self.isSlideshowRunning else { return event }

                if event.keyCode == 123 { // Left arrow
                    self.appState?.navigateToPrevious()
                    return nil // Consume the event
                } else if event.keyCode == 124 { // Right arrow
                    self.appState?.navigateToNext()
                    return nil // Consume the event
                }

                return event // Don't consume other events
            }
        }

        func stopMonitoring() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func updateSlideshowState(_ state: Bool) {
            isSlideshowRunning = state
        }
    }
}

private struct ViewerBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.black.opacity(0.92),
                Color.black.opacity(0.98)
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
            .opacity(0.6)
        )
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
    @EnvironmentObject var appState: AppState
    @State private var showingCustomOrderEditor = false
    @State private var showingSettings = false
    
    var body: some View {
        HSplitView {
            // Sidebar with thumbnail list
            SidebarView()
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)
            
            // Main image viewer
            MainImageViewer()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { appState.selectFolder() }) {
                    Label("Open Folder", systemImage: "folder")
                }
                .disabled(appState.isSlideshowRunning)
                .accessibilityLabel("Open Folder")

                Button(action: { showingSettings = true }) {
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
                Button(action: { appState.toggleSlideshow() }) {
                    Label(appState.isSlideshowRunning ? "Stop Slideshow" : "Start Slideshow",
                          systemImage: appState.isSlideshowRunning ? "pause.circle.fill" : "play.circle.fill")
                }
                .disabled(appState.images.isEmpty)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(appState.isSlideshowRunning ? "Stop Slideshow" : "Start Slideshow")
                .accessibilityHint(appState.isSlideshowRunning ? "Stop automatic slideshow" : "Start automatic slideshow")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    if appState.isSlideshowRunning {
                        appState.toggleSlideshow()  // Stops slideshow if running
                    }
                }) {
                    Label("Stop Slideshow", systemImage: "pause.circle.fill")
                }
                .opacity(0)  // Hidden - Escape key only
                .keyboardShortcut(.escape)
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
            
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(NSColor.windowBackgroundColor), for: .windowToolbar)
        .sheet(isPresented: $showingCustomOrderEditor) {
            CustomOrderEditor()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .modifier(KeyEventHandlingModifier(isSlideshowRunning: appState.isSlideshowRunning))
        .onAppear {
            if appState.images.isEmpty && appState.selectedFolder == nil {
                // Show welcome message or prompt to select folder
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.displayScale) private var displayScale
    
    var body: some View {
        VStack(spacing: 0) {
            if appState.isLoadingImages {
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
            } else if appState.images.isEmpty {
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
            } else {
                List(selection: $appState.currentImageIndex) {
                    ForEach(Array(appState.images.enumerated()), id: \.element.id) { index, image in
                        SidebarItemView(image: image, index: index, totalCount: appState.images.count)
                            .tag(index)
                            .contextMenu {
                                Button("Set as First") {
                                    appState.navigateToIndex(index)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .disabled(appState.isSlideshowRunning)
            }
        }
        .onAppear {
            let maxPixelSize = max(1, Int(defaultThumbnailSize * displayScale))
            appState.updateThumbnailPrefetchSize(maxPixelSize)
        }
        .onChange(of: displayScale) { newScale in
            let maxPixelSize = max(1, Int(defaultThumbnailSize * newScale))
            appState.updateThumbnailPrefetchSize(maxPixelSize)
        }
    }
}

struct SidebarItemView: View {
    @EnvironmentObject var appState: AppState
    let image: ImageFile
    let index: Int
    let totalCount: Int

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

            if appState.failedImages.contains(image.url) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
                    .help("Failed to load")
            }
        }
        .accessibilityLabel(appState.failedImages.contains(image.url) ? "Image failed to load, \(image.name)" : "\(image.name), \(index + 1) of \(totalCount)")
        .accessibilityHint(appState.failedImages.contains(image.url) ? "Could not read image file" : "Double click to view image")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sidebar-item-\(index)")
    }
}

struct MainImageViewer: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.displayScale) private var displayScale
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var retryLoadTrigger = 0
    @State private var renderedImage: CGImage?
    @State private var loadFailed = false
    @State private var isHoveringOverlay = false
    
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
                    let maxPixelSize = max(1, Int(max(geometry.size.width, geometry.size.height) * displayScale))
                    let taskID = "\(currentImage.id.uuidString)|\(maxPixelSize)|\(retryLoadTrigger)"

                    ZStack {
                        if let renderedImage = renderedImage {
                            Image(decorative: renderedImage, scale: displayScale)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .accessibilityIdentifier("main-image")
                                // NOTE: .interpolation(.high) modifier requires macOS 14.0+
                                // Current rendering uses default interpolation suitable for macOS 13.0
                                // For smoother zoom at high magnification, consider increasing minimum OS to 14.0
                                .scaleEffect(scale)
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
                                            withAnimation {
                                                lastOffset = offset
                                            }
                                        }
                                )
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = lastScale * value
                                        }
                                        .onEnded { value in
                                            withAnimation {
                                                lastScale = scale
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation {
                                        scale = 1.0
                                        offset = .zero
                                        lastScale = 1.0
                                        lastOffset = .zero
                                    }
                                }
                        } else if loadFailed {
                            InfoPill {
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(.secondary)
                                    Text("Cannot Display Image")
                                        .font(.headline)
                                    Text(currentImage.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text("File may be corrupted or unsupported")
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
                    .task(id: taskID) {
                        await MainActor.run {
                            loadFailed = false
                            renderedImage = nil
                        }

                        let image = await appState.loadDownsampledImage(from: currentImage.url, maxPixelSize: maxPixelSize, cache: .main)
                        if Task.isCancelled {
                            return
                        }

                        await MainActor.run {
                            renderedImage = image
                            loadFailed = image == nil
                            if image == nil {
                                appState.failedImages.insert(currentImage.url)
                            } else {
                                appState.failedImages.remove(currentImage.url)
                            }
                        }

                        if image != nil {
                            appState.prefetchMainImages(around: appState.currentImageIndex, maxPixelSize: maxPixelSize)
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
                            }
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
        }
        .onChange(of: appState.currentImageIndex) { _ in
            // Reset zoom when changing images
            withAnimation {
                scale = 1.0
                offset = .zero
                lastScale = 1.0
                lastOffset = .zero
            }
        }
    }
}

struct ThumbnailView: View {
    let image: ImageFile
    let size: CGFloat
    @EnvironmentObject var appState: AppState
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnailImage: CGImage?

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
        }
        .task(id: "\(image.id.uuidString)|\(maxPixelSize)") {
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
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
            
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Slideshow Interval")
                            .font(.headline)
                        
                        HStack {
                            Slider(value: $appState.slideshowInterval, in: 1...10, step: 0.5)
                            Text("\(Int(appState.slideshowInterval))s")
                                .frame(width: 40)
                        }
                        
                        Text("Time between slides in slideshow mode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sort Order")
                            .font(.headline)
                        
                        Picker("Sort Order", selection: $appState.sortOrder) {
                            ForEach(AppState.SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

struct CustomOrderEditor: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var editingOrder: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Custom Image Order")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Drag to reorder images in your preferred sequence")
                .font(.caption)
                .foregroundColor(.secondary)
            
            List {
                ForEach(Array(editingOrder.enumerated()), id: \.offset) { index, imageName in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                        Text(imageName)
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
            editingOrder = appState.images.map { $0.name }
        }
    }
}

#if ENABLE_PREVIEWS
#Preview {
    ContentView()
        .environmentObject(AppState())
}
#endif
