//
//  UserLogoStore.swift
//  Tenra
//
//  Logos from the person's own pictures (the owner's request, 2026-11-02): DesignKit's
//  IconPicker has a Photo tab once `DesignKitIconPhotos.save` is set (DesignKitBridge). The
//  picture is cropped to a square there; here it is kept as a PNG in Application Support/
//  UserLogos (not the logos cache, which a cache version wipes) and named
//  `.brandService("photo:<uuid>")`. That icon round-trips through every place an icon is kept
//  (accounts, goals, assets as IconSource JSON, subscriptions as `brandId`, merchants in
//  MerchantLogoStore) with no schema change, and `LogoService` reads it before the provider
//  chain. Cloud backups copy the folder (CloudBackupService).
//

import UIKit

nonisolated enum UserLogoStore {
    /// The key prefix of a picture's icon: `.brandService("photo:<uuid>")`.
    static let prefix = "photo:"

    /// The side of the square kept, in pixels: an 80 pt hero at 3x, with room.
    static let pixelSize: CGFloat = 512

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UserLogos", isDirectory: true)
    }

    static func isPhotoKey(_ key: String) -> Bool {
        key.hasPrefix(prefix)
    }

    /// Whether `source` is a picture this store keeps.
    static func isPhoto(_ source: IconSource) -> Bool {
        if case .brandService(let key) = source { return isPhotoKey(key) }
        return false
    }

    /// The file of a picture's key; nil for any other key (or one that names a path).
    static func fileURL(forKey key: String) -> URL? {
        guard isPhotoKey(key) else { return nil }
        let id = String(key.dropFirst(prefix.count))
        guard UUID(uuidString: id) != nil else { return nil }
        return directory.appendingPathComponent("\(id).png")
    }

    /// Keeps a square picture; returns its key, nil when it could not be written.
    static func save(_ image: UIImage) -> String? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let side = pixelSize
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let data = square.pngData() else { return nil }
        let key = prefix + UUID().uuidString
        guard let url = fileURL(forKey: key) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return key
        } catch {
            return nil
        }
    }

    /// The picture of a key; nil when the file is missing (a restore without it, a removed one).
    static func image(forKey key: String) -> UIImage? {
        guard let url = fileURL(forKey: key), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
