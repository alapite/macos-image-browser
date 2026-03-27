import Foundation

/// Filter rules for smart collections.
///
/// Collection rules define which images belong to a smart collection using
/// AND or OR logic based on the `matchAny` property:
///
/// - **Match All (default, matchAny: false):** All non-nil criteria must match
/// - **Match Any (matchAny: true):** Any non-nil criterion can match
///
/// Empty rules (all properties nil) match all images regardless of matchAny.
///
/// Example usage:
/// ```swift
/// // 5-star favorites tagged "vacation" (Match All - all must match)
/// let rules = CollectionRules(
///     minimumRating: 5,
///     favoritesOnly: true,
///     requiredTags: Set(["vacation"])
/// )
///
/// // 5-star OR favorites OR tagged (Match Any - any can match)
/// let anyRules = CollectionRules(
///     minimumRating: 5,
///     favoritesOnly: true,
///     requiredTags: Set(["vacation"]),
///     matchAny: true
/// )
///
/// // All images (no filters)
/// let emptyRules = CollectionRules(
///     minimumRating: nil,
///     favoritesOnly: nil,
///     requiredTags: nil
/// )
/// ```
public struct CollectionRules: Codable, Sendable {

    // MARK: - Properties

    /// Minimum rating filter (nil = no rating filter, 0-5 = minimum star rating)
    ///
    /// If set, only images with rating >= minimumRating match the collection.
    /// If nil, rating is not considered for filtering.
    public let minimumRating: Int?

    /// Favorites filter (nil = no favorite filter, true = favorites only, false = exclude favorites)
    ///
    /// If true, only favorited images match the collection.
    /// If false, only non-favorited images match the collection.
    /// If nil, favorite status is not considered for filtering.
    public let favoritesOnly: Bool?

    /// Required tags filter (nil = no tag filter, non-empty = images must have all these tags)
    ///
    /// If set with matchAny=false (AND): images must have ALL tags in this set.
    /// If set with matchAny=true (OR): images must have AT LEAST ONE tag.
    /// If nil, tags are not considered for filtering.
    public let requiredTags: Set<String>?

    /// Match mode for combining filter criteria.
    ///
    /// If false (default): AND logic - all non-nil criteria must match.
    /// If true: OR logic - any non-nil criterion can match.
    /// Empty rules (all nil) match all images regardless of matchAny.
    public let matchAny: Bool

    // MARK: - Initialization

    /// Initialize with filter criteria
    /// - Parameters:
    ///   - minimumRating: Minimum star rating (0-5), nil = no rating filter
    ///   - favoritesOnly: Favorite filter, nil = no favorite filter
    ///   - requiredTags: Required tags, nil = no tag filter
    ///   - matchAny: Match mode (false = AND logic, true = OR logic), defaults to false
    public init(
        minimumRating: Int? = nil,
        favoritesOnly: Bool? = nil,
        requiredTags: Set<String>? = nil,
        matchAny: Bool = false
    ) {
        self.minimumRating = minimumRating
        self.favoritesOnly = favoritesOnly
        self.requiredTags = requiredTags
        self.matchAny = matchAny
    }

    // MARK: - Computed Properties

    /// Returns true if all filter properties are nil (no filters active)
    ///
    /// Empty rules match all images - useful for detecting if a collection
    /// has any active filters or if it's an "all images" collection.
    public var isEmpty: Bool {
        minimumRating == nil && favoritesOnly == nil && requiredTags == nil
    }
}

// MARK: - Codable Conformance

extension CollectionRules {
    /// Custom coding keys for JSON encoding/decoding
    enum CodingKeys: String, CodingKey {
        case minimumRating
        case favoritesOnly
        case requiredTags
        case matchAny
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumRating = try container.decodeIfPresent(Int.self, forKey: .minimumRating)
        favoritesOnly = try container.decodeIfPresent(Bool.self, forKey: .favoritesOnly)
        requiredTags = try container.decodeIfPresent(Set<String>.self, forKey: .requiredTags)
        matchAny = try container.decodeIfPresent(Bool.self, forKey: .matchAny) ?? false
    }
}
