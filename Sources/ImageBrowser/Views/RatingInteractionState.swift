import Foundation

struct RatingInteractionState {
    private struct PendingRequest {
        let rating: Int
        let generation: UInt64
    }

    private var pendingByImageID: [String: PendingRequest] = [:]
    private var latestGenerationByImageID: [String: UInt64] = [:]

    mutating func recordPending(imageID: String, rating: Int) -> UInt64 {
        let nextGeneration = (latestGenerationByImageID[imageID] ?? 0) + 1
        latestGenerationByImageID[imageID] = nextGeneration
        pendingByImageID[imageID] = PendingRequest(rating: rating, generation: nextGeneration)
        return nextGeneration
    }

    func displayRating(for imageID: String, persistedRating: Int) -> Int {
        pendingByImageID[imageID]?.rating ?? persistedRating
    }

    mutating func completeRequest(imageID: String, generation: UInt64, didSucceed: Bool) -> Bool {
        guard let pending = pendingByImageID[imageID], pending.generation == generation else {
            return false
        }

        if didSucceed {
            pendingByImageID[imageID] = nil
        } else {
            pendingByImageID[imageID] = nil
        }
        return true
    }
}
