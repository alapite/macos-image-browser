import Foundation

@MainActor
final class AppContainer {
    let database: AppDatabase
    let appState: AppState
    let imageStore: ImageStore
    let filterStore: FilterStore
    let viewStore: ViewStore
    let galleryStore: GalleryStore
    let tagStore: TagStore
    let collectionStore: CollectionStore
    let uiInteractionDependencies: UIInteractionDependencies

    init(
        database: AppDatabase? = nil,
        processInfo: EnvironmentProviding = ProcessInfo.processInfo,
        fileManager: FileManager = .default,
        uiInteractionDependencies: UIInteractionDependencies = .live
    ) {
        self.uiInteractionDependencies = uiInteractionDependencies

        let resolvedDatabase = database ?? AppDatabase(
            configuration: AppDatabaseConfiguration.from(environment: processInfo.environment),
            fileManager: fileManager
        )
        self.database = resolvedDatabase

        let preferencesStore: PreferencesStore
        if processInfo.environment["IMAGEBROWSER_UI_TEST_MODE"] == "1" {
            preferencesStore = VolatilePreferencesStore()
        } else {
            preferencesStore = UserDefaultsPreferencesStore()
        }

        let fileSystem = LocalFileSystem()
        let downsamplingPipeline = ImageDownsamplingPipeline(thumbnailLimit: 1000)
        let imageScanner = ImageDirectoryScanner(fileSystem: fileSystem)
        let imageCache = NSImageCacheStore(
            totalCostLimit: 1024 * 1024 * 100,
            countLimit: 100
        )
        let slideshowScheduler = TimerSlideshowScheduler()

        let filterStore = FilterStore()
        let tagStore = TagStore(dbPool: resolvedDatabase.dbPool)
        let imageStore = ImageStore(
            dbPool: resolvedDatabase.dbPool,
            filtering: filterStore,
            tagLookup: tagStore
        )
        let appState = AppState(
            dependencies: AppStateDependencies(
                fileSystem: fileSystem,
                preferencesStore: preferencesStore,
                downsamplingPipeline: downsamplingPipeline,
                imageScanner: imageScanner,
                imageCache: imageCache,
                slideshowScheduler: slideshowScheduler,
                environment: processInfo,
                fileWatcherFactory: { watchURL in
                    FileWatcher(fileSystem: fileSystem, url: watchURL)
                }
            )
        )
        let viewStore = ViewStore()
        let collectionStore = CollectionStore(
            dbPool: resolvedDatabase.dbPool,
            imageSource: appState,
            tagStore: tagStore
        )
        let galleryStore = GalleryStore(
            imageSource: appState,
            metadataSource: imageStore,
            filtering: filterStore,
            tagLookup: tagStore,
            collectionSource: collectionStore
        )

        self.appState = appState
        self.imageStore = imageStore
        self.filterStore = filterStore
        self.viewStore = viewStore
        self.galleryStore = galleryStore
        self.tagStore = tagStore
        self.collectionStore = collectionStore
    }
}

@MainActor
enum PreviewContainer {
    static let shared = AppContainer()
}
