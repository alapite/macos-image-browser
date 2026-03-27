import Foundation

enum MainImageRequestPlanner {
    static let fitInitialQualityMultiplier: Double = 1.5
    private static let interactiveUpgradeDebounceNanoseconds: UInt64 = 150_000_000

    static func basePixelSize(
        viewportMaxPixelSize: Int,
        normalize: (Int) -> Int
    ) -> Int {
        normalize(max(1, viewportMaxPixelSize))
    }

    static func targetPixelSize(
        viewportMaxPixelSize: Int,
        zoomMode: ViewStore.ZoomMode,
        currentZoom: Double,
        normalize: (Int) -> Int
    ) -> Int {
        let zoomFactor: Double
        if zoomMode == .fit {
            zoomFactor = max(1.0, fitInitialQualityMultiplier)
        } else {
            zoomFactor = max(1.0, currentZoom)
        }

        let requested = Int(ceil(Double(max(1, viewportMaxPixelSize)) * zoomFactor))
        return normalize(requested)
    }

    static func upgradeDebounceNanoseconds(zoomMode: ViewStore.ZoomMode) -> UInt64 {
        zoomMode == .fit ? 0 : interactiveUpgradeDebounceNanoseconds
    }

    static func shouldUpgradeImage(
        loadedPixelSize: Int?,
        basePixelSize: Int,
        targetPixelSize: Int
    ) -> Bool {
        let loaded = max(loadedPixelSize ?? 0, basePixelSize)
        return targetPixelSize > loaded
    }
}
