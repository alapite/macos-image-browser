import SwiftUI
import AppKit
import os

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
            ToolbarItem(placement: .navigation) {
                Button(action: { appState.selectFolder() }) {
                    Label("Open Folder", systemImage: "folder")
                }
                .disabled(appState.isSlideshowRunning)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { appState.navigateToPrevious() }) {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(appState.images.isEmpty || appState.isSlideshowRunning)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { appState.navigateToNext() }) {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(appState.images.isEmpty || appState.isSlideshowRunning)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { appState.toggleSlideshow() }) {
                    Label(appState.isSlideshowRunning ? "Stop Slideshow" : "Start Slideshow",
                          systemImage: appState.isSlideshowRunning ? "pause.circle.fill" : "play.circle.fill")
                }
                .disabled(appState.images.isEmpty)
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
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
                .disabled(appState.isSlideshowRunning)
            }
        }
        .sheet(isPresented: $showingCustomOrderEditor) {
            CustomOrderEditor()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            if appState.images.isEmpty && appState.selectedFolder == nil {
                // Show welcome message or prompt to select folder
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            if appState.images.isEmpty {
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No images loaded")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Select a folder to begin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
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
            }
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
            ThumbnailView(image: image, size: 50)
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(image.name)
                    .font(.caption)
                    .lineLimit(1)
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
    }
}

struct MainImageViewer: View {
    @EnvironmentObject var appState: AppState
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var retryLoadTrigger = 0
    @State private var lastLoggedImageLoadAt = Date.distantPast

    private func loadImage(url: URL, context: String) -> NSImage? {
        let start = DispatchTime.now()
        let image = NSImage(contentsOf: url)
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNs) / 1_000_000.0

        // Avoid spamming logs for repeated view updates.
        if Date().timeIntervalSince(lastLoggedImageLoadAt) > 0.5 {
            lastLoggedImageLoadAt = Date()

            if image == nil {
                Logger.imageLoad.error("Image decode failed context=\(context) file=\(url.lastPathComponent)")
            } else {
                Logger.imageLoad.info("Image decode context=\(context) file=\(url.lastPathComponent) elapsedMs=\(elapsedMs)")
            }
        }

        return image
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
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
                .padding()
            } else if let currentImage = appState.images[safe: appState.currentImageIndex] {
                GeometryReader { geometry in
                    if let nsImage = loadImage(url: currentImage.url, context: "main") {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
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
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
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
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                        }
                        .onChange(of: retryLoadTrigger) { _ in
                            if loadImage(url: currentImage.url, context: "main-retry") != nil {
                                appState.failedImages.remove(currentImage.url)
                            }
                        }
                        .onAppear {
                            appState.failedImages.insert(currentImage.url)
                        }
                    }
                }
                .clipped()
                
                // Image info overlay
                VStack {
                    Spacer()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentImage.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("\(appState.currentImageIndex + 1) / \(appState.images.count)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        if appState.isSlideshowRunning {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(Int(appState.slideshowInterval))s")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
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

    @State private var lastLoggedAt = Date.distantPast

    private func loadThumbnail(url: URL) -> NSImage? {
        let start = DispatchTime.now()
        let image = NSImage(contentsOf: url)
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNs) / 1_000_000.0

        // Thumbnails can be requested in large numbers; keep logging coarse.
        if Date().timeIntervalSince(lastLoggedAt) > 3.0 {
            lastLoggedAt = Date()

            if image == nil {
                Logger.imageLoad.error("Thumbnail decode failed file=\(url.lastPathComponent)")
            } else {
                Logger.imageLoad.info("Thumbnail decode file=\(url.lastPathComponent) elapsedMs=\(elapsedMs)")
            }
        }

        return image
    }
    
    var body: some View {
        if let nsImage = loadThumbnail(url: image.url) {
            Image(nsImage: nsImage)
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

#Preview {
    ContentView()
        .environmentObject(AppState())
}
