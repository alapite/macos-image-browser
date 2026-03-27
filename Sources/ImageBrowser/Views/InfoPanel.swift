import SwiftUI

struct InfoPanel: View {
    let image: ImageFile
    @State private var exifData: ExifMetadata?
    @State private var dimensions: CGSize?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox(label: Label("Basic Info", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Filename", value: image.name)
                        if let dimensions = dimensions {
                            InfoRow(label: "Dimensions", value: "\(Int(dimensions.width)) × \(Int(dimensions.height))")
                        }
                        InfoRow(label: "File Size", value: String(format: "%.2f MB", image.fileSizeMB))
                        InfoRow(label: "Created", value: formatDate(image.creationDate))
                    }
                }

                if let exif = exifData {
                    GroupBox(label: Label("Camera Data", systemImage: "camera.fill")) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let camera = exif.cameraModel {
                                InfoRow(label: "Camera", value: camera)
                            }
                            if let lens = exif.lensModel {
                                InfoRow(label: "Lens", value: lens)
                            }
                            if let iso = exif.iso {
                                InfoRow(label: "ISO", value: "\(iso)")
                            }
                            if let shutter = exif.shutterSpeed {
                                InfoRow(label: "Shutter", value: shutter)
                            }
                            if let aperture = exif.aperture {
                                InfoRow(label: "Aperture", value: aperture)
                            }
                            if let focal = exif.focalLength {
                                InfoRow(label: "Focal Length", value: focal)
                            }
                            if let dateTaken = exif.dateTaken {
                                InfoRow(label: "Date Taken", value: formatDate(dateTaken))
                            }
                        }
                    }
                }

                GroupBox(label: Label("File Details", systemImage: "doc.fill")) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Path", value: image.url.path)
                        InfoRow(label: "Type", value: image.url.pathExtension.uppercased())
                    }
                }
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .task {
            exifData = await image.exifMetadata()
            dimensions = await image.dimensions()
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
