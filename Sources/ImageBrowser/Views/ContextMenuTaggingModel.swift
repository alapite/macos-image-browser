import Foundation

enum ContextMenuTaggingModel {
    static func resolveTargetImageURLs(
        clickedImageID: String,
        selectedImageIDs: Set<String>,
        visibleImages: [DisplayImage]
    ) -> [String] {
        let targetIDs: Set<String>
        if selectedImageIDs.contains(clickedImageID) {
            targetIDs = selectedImageIDs
        } else {
            targetIDs = [clickedImageID]
        }

        return visibleImages
            .filter { targetIDs.contains($0.id) }
            .map { $0.url.standardizedFileURL.absoluteString }
    }

    static func committedTags(from inputText: String, existingTags: Set<String>) -> Set<String> {
        var committedTags: Set<String> = existingTags
        var normalizedTags = Set(existingTags.map { $0.lowercased() })
        let delimiters = CharacterSet(charactersIn: ",\n")

        for rawToken in inputText.components(separatedBy: delimiters) {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }

            let normalizedToken = token.lowercased()
            guard !normalizedTags.contains(normalizedToken) else { continue }

            committedTags.insert(token)
            normalizedTags.insert(normalizedToken)
        }

        return committedTags
    }
}

struct TagCommitParser {
    static func committedTags(from inputText: String, existingTags: Set<String>) -> Set<String> {
        ContextMenuTaggingModel.committedTags(from: inputText, existingTags: existingTags)
    }
}
