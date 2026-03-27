import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class ImageStoreExclusionPersistenceTests: XCTestCase {
    private var filterStore: FilterStore!

    override func setUp() async throws {
        filterStore = FilterStore()
    }

    override func tearDown() async throws {
        filterStore = nil
    }

    func testImageMetadataRecord_roundTripsExcludedFields() throws {
        let expectedDate = Date(timeIntervalSince1970: 1_710_000_000)
        let dbQueue = try DatabaseQueue()
        let decodedRecord = try dbQueue.write { db in
            try db.create(table: "image_metadata") { table in
                table.column("url", .text).primaryKey()
                table.column("rating", .integer).notNull()
                table.column("isFavorite", .boolean).notNull()
                table.column("isExcluded", .boolean).notNull()
                table.column("excludedAt", .datetime)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            let record = ImageMetadataRecord(
                url: "file:///tmp/round-trip.jpg",
                rating: 4,
                isFavorite: true,
                isExcluded: true,
                excludedAt: expectedDate,
                createdAt: expectedDate,
                updatedAt: expectedDate
            )
            try record.insert(db)
            return try XCTUnwrap(ImageMetadataRecord.fetchOne(db, key: record.url))
        }

        XCTAssertTrue(decodedRecord.isExcluded)
        XCTAssertEqual(decodedRecord.excludedAt, expectedDate)
        XCTAssertEqual(decodedRecord.rating, 4)
        XCTAssertTrue(decodedRecord.isFavorite)
    }

    func testImageStore_updateExcluded_createsMetadataRecordWithTimestamp() async throws {
        let databaseURL = makeTempDirectory().appendingPathComponent("excluded-create.sqlite")
        let database = AppDatabase(
            configuration: AppDatabaseConfiguration(
                overridePath: databaseURL.path,
                resetOnLaunch: false
            )
        )
        let imageStore = ImageStore(dbPool: database.dbPool, filtering: filterStore)
        let imageURL = URL(fileURLWithPath: "/tmp/excluded-create.jpg")

        try await imageStore.updateExcluded(for: imageURL.absoluteString, isExcluded: true)

        let record = try await database.dbPool.read { db in
            try ImageMetadataRecord.fetchOne(db, key: imageURL.standardizedFileURL.absoluteString)
        }

        XCTAssertEqual(record?.url, imageURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(record?.isExcluded, true)
        XCTAssertNotNil(record?.excludedAt)
        XCTAssertEqual(record?.rating, 0)
        XCTAssertEqual(record?.isFavorite, false)
    }

    func testImageStore_updateExcluded_preservesRatingAndFavorite() async throws {
        let databaseURL = makeTempDirectory().appendingPathComponent("excluded-preserve.sqlite")
        let database = AppDatabase(
            configuration: AppDatabaseConfiguration(
                overridePath: databaseURL.path,
                resetOnLaunch: false
            )
        )
        let imageStore = ImageStore(dbPool: database.dbPool, filtering: filterStore)
        let imageURL = URL(fileURLWithPath: "/tmp/excluded-preserve.jpg")
        let key = imageURL.standardizedFileURL.absoluteString

        try await database.dbPool.write { db in
            let record = ImageMetadataRecord(url: key, rating: 5, isFavorite: true)
            try record.insert(db)
        }

        try await imageStore.updateExcluded(for: imageURL.absoluteString, isExcluded: true)
        try await imageStore.updateExcluded(for: imageURL.absoluteString, isExcluded: false)

        let record = try await database.dbPool.read { db in
            try ImageMetadataRecord.fetchOne(db, key: key)
        }

        XCTAssertEqual(record?.rating, 5)
        XCTAssertEqual(record?.isFavorite, true)
        XCTAssertEqual(record?.isExcluded, false)
        XCTAssertNil(record?.excludedAt)
    }

    func testRestorePersistence_setsExcludedFalseAndClearsTimestamp() async throws {
        let databaseURL = makeTempDirectory().appendingPathComponent("restore-persist.sqlite")
        let database = AppDatabase(
            configuration: AppDatabaseConfiguration(
                overridePath: databaseURL.path,
                resetOnLaunch: false
            )
        )
        let imageStore = ImageStore(dbPool: database.dbPool, filtering: filterStore)
        let imageURL = URL(fileURLWithPath: "/tmp/restore-clear.jpg")
        let key = imageURL.standardizedFileURL.absoluteString

        try await database.dbPool.write { db in
            let record = ImageMetadataRecord(url: key, rating: 3, isFavorite: true, isExcluded: true, excludedAt: Date())
            try record.insert(db)
        }

        let success = await imageStore.updateExcludedWithRetry(for: imageURL.absoluteString, isExcluded: false)
        XCTAssertTrue(success, "updateExcludedWithRetry should succeed for restore operation")

        let record = try await database.dbPool.read { db in
            try ImageMetadataRecord.fetchOne(db, key: key)
        }

        XCTAssertEqual(record?.isExcluded, false, "Image should no longer be excluded after restore")
        XCTAssertNil(record?.excludedAt, "excludedAt should be cleared after restore")
        XCTAssertEqual(record?.rating, 3, "Rating should be preserved after restore")
        XCTAssertEqual(record?.isFavorite, true, "Favorite status should be preserved after restore")
    }

    func testImageStore_excludedMetadataSurvivesDatabaseReopen() async throws {
        let databaseURL = makeTempDirectory().appendingPathComponent("excluded-reopen.sqlite")
        let imageURL = URL(fileURLWithPath: "/tmp/excluded-reopen.jpg")
        let key = imageURL.standardizedFileURL.absoluteString
        var database: AppDatabase? = AppDatabase(
            configuration: AppDatabaseConfiguration(
                overridePath: databaseURL.path,
                resetOnLaunch: false
            )
        )
        var imageStore: ImageStore? = ImageStore(dbPool: try XCTUnwrap(database?.dbPool), filtering: filterStore)

        try await imageStore?.updateRating(for: imageURL.absoluteString, rating: 3)
        try await imageStore?.updateFavorite(for: imageURL.absoluteString, isFavorite: true)
        try await imageStore?.updateExcluded(for: imageURL.absoluteString, isExcluded: true)

        imageStore = nil
        database = nil
        try? await Task.sleep(nanoseconds: 50_000_000)

        let reopenedDatabase = AppDatabase(
            configuration: AppDatabaseConfiguration(
                overridePath: databaseURL.path,
                resetOnLaunch: false
            )
        )
        let reopenedStore = ImageStore(dbPool: reopenedDatabase.dbPool, filtering: filterStore)

        let persistedRecord = try await reopenedDatabase.dbPool.read { db in
            try ImageMetadataRecord.fetchOne(db, key: key)
        }

        await waitForImage(
            in: reopenedStore,
            matching: { $0.url.standardizedFileURL.absoluteString == key && $0.isExcluded }
        )

        XCTAssertEqual(persistedRecord?.isExcluded, true)
        XCTAssertNotNil(persistedRecord?.excludedAt)
        XCTAssertEqual(persistedRecord?.rating, 3)
        XCTAssertEqual(persistedRecord?.isFavorite, true)
        XCTAssertEqual(reopenedStore.images.first?.isExcluded, true)
        XCTAssertEqual(reopenedStore.images.first?.rating, 3)
        XCTAssertEqual(reopenedStore.images.first?.isFavorite, true)
    }

    private func waitForImage(
        in imageStore: ImageStore,
        timeout: TimeInterval = 1.5,
        matching predicate: @escaping (ImageFile) -> Bool
    ) async {
        let expectation = XCTestExpectation(description: "image metadata loaded")
        let deadline = Date().addingTimeInterval(timeout)

        Task {
            while Date() < deadline {
                if imageStore.images.contains(where: predicate) {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: timeout + 0.25)
    }
}
