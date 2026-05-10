import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ImageCompressor {
    static let maxDimension: CGFloat = 800
    static let compressionQuality: CGFloat = 0.5

    /// 画像を最大800px・JPEG品質0.5に圧縮する。フル解像度デコードを避けるためImageIOで縮小読み込みする。
    static func compress(_ data: Data) -> Data {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return data
        }

        return jpegData(from: thumbnail) ?? data
    }

    /// UIImageを最大800px・JPEG品質0.5に圧縮する。カメラ/UIImagePicker経由で取得した画像向け。
    static func compress(_ image: UIImage) -> Data? {
        autoreleasepool {
            let resized = resize(image, maxDimension: maxDimension)
            guard let cgImage = resized.cgImage else {
                return resized.jpegData(compressionQuality: compressionQuality)
            }
            return jpegData(from: cgImage)
        }
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longer = max(size.width, size.height)
        guard longer > maxDimension else { return image }
        let scale = maxDimension / longer
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func jpegData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
