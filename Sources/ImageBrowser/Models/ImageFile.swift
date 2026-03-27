import Foundation
import ImageIO

// MARK: - EXIF Metadata Model

/// EXIF metadata extracted from image files
struct ExifMetadata: Sendable {
    let cameraModel: String?
    let lensModel: String?
    let iso: Int?
    let shutterSpeed: String?
    let aperture: String?
    let focalLength: String?
    let dateTaken: Date?
}

// MARK: - Image Metadata Model

/// In-memory metadata associated with an image file (favorites, ratings, tags, etc.)
/// Loaded lazily from database to avoid eager loading all metadata at startup
///
/// This is a lightweight in-memory representation. For database persistence,
/// see `ImageMetadataRecord` in the Database module.
struct ImageMetadata: Sendable, Equatable {
    var rating: Int
    var isFavorite: Bool
    var isExcluded: Bool
    var excludedAt: Date?

    init(
        rating: Int = 0,
        isFavorite: Bool = false,
        isExcluded: Bool = false,
        excludedAt: Date? = nil
    ) {
        self.rating = rating
        self.isFavorite = isFavorite
        self.isExcluded = isExcluded
        self.excludedAt = excludedAt
    }
}

// MARK: - Image File Model

/// Represents an image file in the filesystem with optional metadata
///
/// This struct provides value semantics and thread safety for image file representation.
/// The optional `metadata` property allows lazy loading - metadata is fetched from the
/// database only when needed, preventing expensive eager loading at startup.
///
/// Computed properties provide safe access to metadata fields with sensible defaults:
/// - `rating`: Returns 0 if metadata not loaded (instead of crashing)
/// - `isFavorite`: Returns false if metadata not loaded (instead of crashing)
///
/// This design allows existing code to access `image.rating` without optional unwrapping,
/// while new code can explicitly check `image.metadata` when needed.
struct ImageFile: Identifiable, Equatable, Sendable {
    /// Unique identifier based on standardized file URL
    var id: String {
        url.standardizedFileURL.absoluteString
    }

    /// File system URL of the image
    let url: URL

    /// Display name of the file (filename with extension)
    let name: String

    /// File creation date from filesystem attributes
    let creationDate: Date

    /// File size in bytes.
    ///
    /// This is captured at scan time so filtering does not perform filesystem IO in render paths.
    let fileSizeBytes: Int64

    /// Optional metadata loaded from database (lazy loading pattern)
    ///
    /// When nil, computed properties provide safe defaults:
    /// - `rating` returns 0
    /// - `isFavorite` returns false
    ///
    /// This allows UI to display images without waiting for metadata load,
    /// while metadata can be fetched asynchronously in the background.
    var metadata: ImageMetadata?

    init(
        url: URL,
        name: String,
        creationDate: Date,
        fileSizeBytes: Int64 = 0,
        metadata: ImageMetadata? = nil
    ) {
        self.url = url
        self.name = name
        self.creationDate = creationDate
        self.fileSizeBytes = fileSizeBytes
        self.metadata = metadata
    }

    /// File size in megabytes
    var fileSizeMB: Double {
        Double(fileSizeBytes) / 1_000_000.0
    }

    /// Safe access to rating - returns 0 if metadata not loaded
    var rating: Int {
        metadata?.rating ?? 0
    }

    /// Safe access to favorite status - returns false if metadata not loaded
    var isFavorite: Bool {
        metadata?.isFavorite ?? false
    }

    /// Safe access to excluded status - returns false if metadata not loaded
    var isExcluded: Bool {
        metadata?.isExcluded ?? false
    }

    /// EXIF metadata loaded asynchronously from image file
    func exifMetadata() async -> ExifMetadata? {
        await loadExifMetadata()
    }

    /// Image dimensions loaded asynchronously from image file
    func dimensions() async -> CGSize? {
        await loadDimensions()
    }

    /// Equality based on file URL and metadata (two ImageFile instances are equal if they point to same file AND have same metadata)
    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.url == rhs.url && lhs.metadata == rhs.metadata
    }

    // MARK: - Private EXIF Loading

    private func loadExifMetadata() async -> ExifMetadata? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let dateTaken: Date?
        if let dateString = tiffDict?[kCGImagePropertyTIFFDateTime] as? String {
            dateTaken = parseExifDate(dateString)
        } else {
            dateTaken = nil
        }

        return ExifMetadata(
            cameraModel: tiffDict?[kCGImagePropertyTIFFModel] as? String,
            lensModel: exifDict?[kCGImagePropertyExifLensModel] as? String,
            iso: exifDict?[kCGImagePropertyExifISOSpeedRatings] as? Int,
            shutterSpeed: formatShutterSpeed(exifDict?[kCGImagePropertyExifShutterSpeedValue] as? Double),
            aperture: formatAperture(exifDict?[kCGImagePropertyExifFNumber] as? Double),
            focalLength: formatFocalLength(exifDict?[kCGImagePropertyExifFocalLength] as? Double),
            dateTaken: dateTaken
        )
    }

    private func loadDimensions() async -> CGSize? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = properties[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        return CGSize(width: width, height: height)
    }

    private func formatShutterSpeed(_ value: Double?) -> String? {
        guard let value = value else { return nil }
        if value >= 1 {
            return "\(Int(value))s"
        } else {
            let denominator = Int(1.0 / value)
            return "1/\(denominator)"
        }
    }

    private func formatAperture(_ value: Double?) -> String? {
        guard let value = value else { return nil }
        return "f/\(String(format: "%.1f", value))"
    }

    private func formatFocalLength(_ value: Double?) -> String? {
        guard let value = value else { return nil }
        return "\(Int(value))mm"
    }

    private func parseExifDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}
