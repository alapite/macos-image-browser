import SwiftUI

@main
struct ImageBrowserApp: App {
    private static let keywordManagerWindowID = "keyword-manager-window"

    private let container: AppContainer

    @StateObject private var appState: AppState
    @StateObject private var imageStore: ImageStore
    @StateObject private var filterStore: FilterStore
    @StateObject private var viewStore: ViewStore
    @StateObject private var galleryStore: GalleryStore
    @StateObject private var tagStore: TagStore
    @StateObject private var collectionStore: CollectionStore

    // Filter inspector presentation state
    @State private var showingFilters = false

    init() {
        let container = AppContainer()
        self.container = container

        _appState = StateObject(wrappedValue: container.appState)
        _imageStore = StateObject(wrappedValue: container.imageStore)
        _filterStore = StateObject(wrappedValue: container.filterStore)
        _viewStore = StateObject(wrappedValue: container.viewStore)
        _galleryStore = StateObject(wrappedValue: container.galleryStore)
        _tagStore = StateObject(wrappedValue: container.tagStore)
        _collectionStore = StateObject(wrappedValue: container.collectionStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showingFilters: $showingFilters)
                .environment(\.uiInteractionDependencies, container.uiInteractionDependencies)
                .environmentObject(appState)
                .environmentObject(imageStore)
                .environmentObject(filterStore)
                .environmentObject(viewStore)
                .environmentObject(galleryStore)
                .environmentObject(tagStore)
                .environmentObject(collectionStore)
                .frame(minWidth: 800, minHeight: 600)
                .background(FullscreenWindowController(viewStore: viewStore))
        }
        .commands {
            ImageBrowserCommands(keywordManagerWindowID: Self.keywordManagerWindowID)

            // Add items to the existing View menu (don't create a new one)
            CommandGroup(after: .toolbar) {
                Button(viewStore.isFullscreen ? "Exit Full Screen" : "Enter Full Screen") {
                    if viewStore.isFullscreen {
                        container.uiInteractionDependencies.windowCommands.exitFullscreen()
                    } else {
                        container.uiInteractionDependencies.windowCommands.enterFullscreen()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .control])

                Divider()

                Button("Fit to Both") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewStore.fitToBoth()
                    }
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Actual Size") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewStore.actualSize()
                    }
                }
                .keyboardShortcut("1", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewStore.zoomIn()
                    }
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewStore.zoomOut()
                    }
                }
                .keyboardShortcut("-", modifiers: .command)

                Divider()

                Button(showingFilters ? "Hide Filters" : "Show Filters") {
                    showingFilters.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Show Info") {
                    viewStore.showInfoPanel.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }

        Window("Keyword Manager", id: Self.keywordManagerWindowID) {
            KeywordManager()
                .environmentObject(tagStore)
                .frame(minWidth: 640, minHeight: 420)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 420, minHeight: 280)
        }
    }
}
