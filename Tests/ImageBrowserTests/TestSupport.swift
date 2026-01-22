import Foundation
@testable import ImageBrowser

func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0
) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return components.date!
}

func makeImageFile(
    name: String,
    creationDate: Date
) -> ImageFile {
    ImageFile(
        url: URL(fileURLWithPath: "/tmp/ImageBrowserTests/\(name)"),
        name: name,
        creationDate: creationDate
    )
}
