import SwiftUI

struct ImageBrowserCommandContext {
    let canOpenFolder: Bool
    let hasImages: Bool
    let canNavigate: Bool
    let canEditMetadata: Bool
    let isSlideshowRunning: Bool
    let isFilterPanelPresented: Bool
    let sortOrder: AppState.SortOrder
    let isShuffleEnabled: Bool
    let canReshuffle: Bool
    let openFolder: () -> Void
    let toggleFilters: () -> Void
    let navigateToPrevious: () -> Void
    let navigateToNext: () -> Void
    let toggleFavorite: () -> Void
    let toggleSlideshow: () -> Void
    let stopSlideshow: () -> Void
    let toggleShuffle: () -> Void
    let reshuffle: () -> Void
    let editCustomOrder: () -> Void
    let setSortOrder: (AppState.SortOrder) -> Void
}

private struct ImageBrowserCommandContextKey: FocusedValueKey {
    typealias Value = ImageBrowserCommandContext
}

extension FocusedValues {
    var imageBrowserCommandContext: ImageBrowserCommandContext? {
        get { self[ImageBrowserCommandContextKey.self] }
        set { self[ImageBrowserCommandContextKey.self] = newValue }
    }
}

struct ImageBrowserCommands: Commands {
    @FocusedValue(\.imageBrowserCommandContext) private var context
    @Environment(\.openWindow) private var openWindow

    let keywordManagerWindowID: String

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .newItem) {
            Button("Open Folder...") {
                context?.openFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!(context?.canOpenFolder ?? true))
        }

        CommandMenu("Navigate") {
            Button("Previous Image") {
                context?.navigateToPrevious()
            }
            .keyboardShortcut(.leftArrow)
            .disabled(!(context?.canNavigate ?? false))

            Button("Next Image") {
                context?.navigateToNext()
            }
            .keyboardShortcut(.rightArrow)
            .disabled(!(context?.canNavigate ?? false))

            Divider()

            Button("Toggle Shuffle") {
                context?.toggleShuffle()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!(context?.hasImages ?? false))

            Button("Reshuffle") {
                context?.reshuffle()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift, .option])
            .disabled(!(context?.canReshuffle ?? false))

            Divider()

            Button((context?.isSlideshowRunning ?? false) ? "Stop Slideshow" : "Start Slideshow") {
                context?.toggleSlideshow()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!(context?.hasImages ?? false))

            Button("Stop Slideshow") {
                context?.stopSlideshow()
            }
            .disabled(!(context?.isSlideshowRunning ?? false))
        }

        CommandMenu("Image") {
            Button("Toggle Favorite") {
                context?.toggleFavorite()
            }
            .keyboardShortcut(".", modifiers: [])
            .disabled(!(context?.canEditMetadata ?? false))

            Divider()

            Button(AppState.SortOrder.name.rawValue) {
                context?.setSortOrder(.name)
            }
            .disabled(!(context?.hasImages ?? false))

            Button(AppState.SortOrder.creationDate.rawValue) {
                context?.setSortOrder(.creationDate)
            }
            .disabled(!(context?.hasImages ?? false))

            Button(AppState.SortOrder.custom.rawValue) {
                context?.setSortOrder(.custom)
            }
            .disabled(!(context?.hasImages ?? false))

            Divider()

            Button("Edit Custom Order...") {
                context?.editCustomOrder()
            }
            .disabled((context?.sortOrder ?? .name) != .custom)
        }

        CommandGroup(after: .windowArrangement) {
            Button("Keyword Manager") {
                openWindow(id: keywordManagerWindowID)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }

}
