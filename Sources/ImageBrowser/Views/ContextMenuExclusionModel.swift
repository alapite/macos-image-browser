import Foundation

@MainActor
struct ContextMenuExclusionResult {
    let targetURLs: [String]
    let successfulTargetURLs: [String]
    let successfulExclusionCount: Int
    let failedExclusionCount: Int
    let toastMessage: String?
}

@MainActor
enum ContextMenuExclusionModel {
    static func excludeTargets(
        clickedImageID: String,
        selectedImageIDs: Set<String>,
        visibleImages: [DisplayImage],
        persist: (String) async -> Bool
    ) async -> ContextMenuExclusionResult {
        let targetURLs = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: clickedImageID,
            selectedImageIDs: selectedImageIDs,
            visibleImages: visibleImages
        )

        var successfulExclusionCount = 0
        var successfulTargetURLs: [String] = []
        for targetURL in targetURLs {
            if await persist(targetURL) {
                successfulExclusionCount += 1
                successfulTargetURLs.append(targetURL)
            }
        }

        let failedExclusionCount = targetURLs.count - successfulExclusionCount
        let toastMessage: String?
        switch successfulExclusionCount {
        case 0:
            toastMessage = nil
        case 1:
            toastMessage = "Excluded from normal browsing"
        default:
            toastMessage = "Excluded \(successfulExclusionCount) images from normal browsing"
        }

        return ContextMenuExclusionResult(
            targetURLs: targetURLs,
            successfulTargetURLs: successfulTargetURLs,
            successfulExclusionCount: successfulExclusionCount,
            failedExclusionCount: failedExclusionCount,
            toastMessage: toastMessage
        )
    }

    static func restoreTargets(
        clickedImageID: String,
        selectedImageIDs: Set<String>,
        visibleImages: [DisplayImage],
        persist: (String) async -> Bool
    ) async -> ContextMenuExclusionResult {
        let targetURLs = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: clickedImageID,
            selectedImageIDs: selectedImageIDs,
            visibleImages: visibleImages
        )

        var successfulExclusionCount = 0
        var successfulTargetURLs: [String] = []
        for targetURL in targetURLs {
            if await persist(targetURL) {
                successfulExclusionCount += 1
                successfulTargetURLs.append(targetURL)
            }
        }

        let failedExclusionCount = targetURLs.count - successfulExclusionCount
        let toastMessage: String?
        switch successfulExclusionCount {
        case 0:
            toastMessage = nil
        case 1:
            toastMessage = "Restored to normal browsing"
        default:
            toastMessage = "Restored \(successfulExclusionCount) images to normal browsing"
        }

        return ContextMenuExclusionResult(
            targetURLs: targetURLs,
            successfulTargetURLs: successfulTargetURLs,
            successfulExclusionCount: successfulExclusionCount,
            failedExclusionCount: failedExclusionCount,
            toastMessage: toastMessage
        )
    }
}
