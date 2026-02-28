import UIKit

enum ImageCompressor {
    static let maxDimension: CGFloat = 800
    static let compressionQuality: CGFloat = 0.5

    /// 画像を最大800px・JPEG品質0.5に圧縮する
    static func compress(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let resized = resize(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: compressionQuality) ?? data
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
}
