import Foundation
import UIKit

struct NotePhoto: Codable, Identifiable, Equatable {
    var id: String
    var contentType = "image/jpeg"
}

extension PlannerTask {
    var photos: [NotePhoto] {
        get { photoData.flatMap { try? JSONDecoder().decode([NotePhoto].self, from: Data($0.utf8)) } ?? [] }
        set { photoData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } }
    }
}

enum NotePhotos {
    static let bucket = "orbit-note-photos"
    static var directory: URL {
        let group = Bundle.main.object(forInfoDictionaryKey: "OrbitAppGroup") as? String ?? "group.com.jaiten.orbit.shared"
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("note-photos", isDirectory: true)
    }
    static func file(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil, id == id.lowercased() else { throw CocoaError(.fileReadInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(id + ".jpg")
    }
    static func save(_ image: UIImage) throws -> NotePhoto {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let scale = min(1, 1600 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.8), data.count <= 2_097_152 else { throw CocoaError(.fileWriteOutOfSpace) }
        let photo = NotePhoto(id: UUID().uuidString.lowercased())
        try cache(data, id: photo.id)
        return photo
    }
    static func cache(_ data: Data, id: String) throws {
        guard data.count <= 2_097_152, data.starts(with: [0xff, 0xd8]), UIImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
        try data.write(to: file(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func local(_ id: String) -> UIImage? {
        guard let file = try? file(id) else { return nil }
        return UIImage(contentsOfFile: file.path)
    }
    static func backupFiles(_ records: [[String: Any]]) throws -> [String: String] {
        var result: [String: String] = [:]
        for record in records {
            let payload = record["payload"] as? [String: Any] ?? [:]
            for photo in payload["photos"] as? [[String: String]] ?? [] {
                guard let id = photo["id"] else { throw CocoaError(.coderReadCorrupt) }
                result[id] = try Data(contentsOf: file(id)).base64EncodedString()
            }
        }
        return result
    }
    static func restoreFiles(_ files: [String: String], records: [[String: Any]]) throws {
        for record in records {
            let payload = record["payload"] as? [String: Any] ?? [:]
            for photo in payload["photos"] as? [[String: String]] ?? [] {
                guard let id = photo["id"], let value = files[id] else { continue }
                guard let data = Data(base64Encoded: value) else { throw CocoaError(.fileReadCorruptFile) }
                let location = try file(id)
                if FileManager.default.fileExists(atPath: location.path) {
                    guard try Data(contentsOf: location) == data else { throw CocoaError(.fileWriteFileExists) }
                } else { try cache(data, id: id) }
            }
        }
    }
    static func eraseLocal() { try? FileManager.default.removeItem(at: directory) }
}
