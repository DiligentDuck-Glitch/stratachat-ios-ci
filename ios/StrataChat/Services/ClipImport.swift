import UIKit
import AVFoundation

/// Reading a picked clip and pulling a still out of it are both synchronous, and doing them on
/// the main actor froze the composer while a clip was loading — that was the stutter when the
/// keyboard opened or closed. They live here so the composer can run them on a background queue.
enum ClipImport {
    static let maxBytes = 25 * 1024 * 1024

    enum Outcome {
        case loaded(Data, UIImage?, String)
        case failed
    }

    /// Read the mp4 or mov brand so the server gets a container it recognises.
    static func containerHint(for data: Data) -> String {
        guard data.count > 12 else { return "mp4" }
        let bytes = [UInt8](data.prefix(12))
        let boxType = String(bytes: bytes[4..<8], encoding: .ascii) ?? ""
        let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
        if boxType == "ftyp" {
            if brand.hasPrefix("qt") { return "mov" }
            if brand.hasPrefix("M4V") || brand.hasPrefix("m4v") { return "m4v" }
        }
        return "mp4"
    }

    static func thumbnail(from data: Data) -> UIImage? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString)")
        guard (try? data.write(to: file)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let image = try? generator.copyCGImage(
            at: CMTime(seconds: 0.4, preferredTimescale: 600),
            actualTime: nil
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// Decide what the composer should show once the bytes arrived. Called from a background
    /// task, so nothing here touches the main actor.
    static func finish(_ data: Data?) -> Outcome {
        guard let clip = data, !clip.isEmpty, clip.count <= maxBytes else { return .failed }
        return .loaded(clip, thumbnail(from: clip), containerHint(for: clip))
    }
}
