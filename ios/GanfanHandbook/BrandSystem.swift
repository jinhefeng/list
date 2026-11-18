import ImageIO
import SwiftUI
import UIKit

enum GanfanPalette {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemGroupedBackground.resolvedColor(with: traits)
            : UIColor(red: 246.0 / 255, green: 247.0 / 255, blue: 242.0 / 255, alpha: 1)
    })
    static let ink = Color(uiColor: .label)
    static let forest = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.68, blue: 0.48, alpha: 1)
            : UIColor(red: 0.19, green: 0.30, blue: 0.21, alpha: 1)
    })
    static let forestSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.25, blue: 0.15, alpha: 1)
            : UIColor(red: 0.19, green: 0.30, blue: 0.21, alpha: 1)
    })
    static let leaf = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.59, green: 0.75, blue: 0.55, alpha: 1)
            : UIColor(red: 0.36, green: 0.47, blue: 0.32, alpha: 1)
    })
    static let paleLeaf = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.25, blue: 0.18, alpha: 1)
            : UIColor(red: 0.91, green: 0.94, blue: 0.88, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
            : UIColor.white
    })
}

@MainActor
enum GanfanThumbnailLoader {
    struct Key: Hashable {
        let resource: String
        let maxPixelSize: Int

        init(resource: String, dimension: CGFloat, scale: CGFloat) {
            self.resource = resource
            maxPixelSize = max(1, Int((dimension * scale).rounded(.up)))
        }

        var cacheKey: NSString { "\(resource)@\(maxPixelSize)" as NSString }
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private static var inFlight: [Key: Task<UIImage?, Never>] = [:]

    static func cachedImage(for key: Key) -> UIImage? {
        cache.object(forKey: key.cacheKey)
    }

    static func load(_ key: Key, readData: @escaping @Sendable () -> Data?) async -> UIImage? {
        if let image = cachedImage(for: key) { return image }
        if let task = inFlight[key] { return await task.value }

        let maxPixelSize = key.maxPixelSize
        let task = Task.detached(priority: .utility) {
            readData().flatMap { downsample($0, maxPixelSize: maxPixelSize) }
        }
        inFlight[key] = task
        let image = await task.value
        if let image, let pixels = image.cgImage {
            cache.setObject(image, forKey: key.cacheKey, cost: pixels.bytesPerRow * pixels.height)
        }
        inFlight[key] = nil
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct GanfanBrandLogoIcon: View {
    private static let assetsWithOwnBackground: Set<String> = [
        "BrandIconAmasha",
        "BrandIconCoco",
        "BrandIconYidiandian",
        "BrandIconNayuki",
        "BrandIconPeets",
        "BrandIconTims",
        "BrandIconCocaCola",
        "BrandIconMcDonalds",
        "BrandIconKFC",
        "BrandIconSuiYinJiLiang",
        "BrandIconQuchashan",
        "BrandIconTaiBenNiu"
    ]

    let assetName: String?
    let symbol: String?
    let imageID: UUID?
    var dimension: CGFloat = 20
    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: (key: GanfanThumbnailLoader.Key, image: UIImage)?

    init(assetName: String? = nil, symbol: String?, imageID: UUID? = nil, dimension: CGFloat = 20) {
        self.assetName = assetName
        self.symbol = symbol
        self.imageID = imageID
        self.dimension = dimension
    }

    private var resolvedAssetName: String? {
        guard let assetName = assetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !assetName.isEmpty,
              UIImage(named: assetName) != nil else {
            return nil
        }
        return assetName
    }

    private var imageKey: GanfanThumbnailLoader.Key? {
        imageID.map { .init(resource: "logo:\($0.uuidString)", dimension: dimension, scale: displayScale) }
    }

    var body: some View {
        let key = imageKey
        let customImage = key.flatMap { key in
            if let loadedImage, loadedImage.key == key { return loadedImage.image }
            return GanfanThumbnailLoader.cachedImage(for: key)
        }
        Group {
            if let customImage {
                Image(uiImage: customImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: dimension, height: dimension)
            } else if let resolvedAssetName {
                Image(resolvedAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding(resolvedAssetName == "BrandIconCharlieTown" ? dimension * 0.06 : 0)
                    .frame(width: dimension, height: dimension)
                    .background(Self.assetsWithOwnBackground.contains(resolvedAssetName) ? Color.clear : Color.white)
            } else {
                fallbackIcon
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(RoundedRectangle(cornerRadius: dimension * 0.24, style: .continuous))
        .task(id: key) {
            guard let key, let imageID else {
                loadedImage = nil
                return
            }
            guard loadedImage?.key != key, !Task.isCancelled else { return }
            let image = await GanfanThumbnailLoader.load(key) { AppStoragePaths.brandLogoImageData(for: imageID) }
            guard let image, !Task.isCancelled else { return }
            loadedImage = (key, image)
        }
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image("BrandIconGenericLion")
            .resizable()
            .scaledToFit()
            .frame(width: dimension, height: dimension)
            .background(Color.white)
    }
}

enum GanfanSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let mediumSmall: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let pageHorizontal: CGFloat = 20
}

enum GanfanShape {
    static let photo: CGFloat = 12
    static let control: CGFloat = 14
    static let surface: CGFloat = 16
}

struct GanfanBrandHeader: View {
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("吃吃喝喝")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GanfanPalette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(GanfanPalette.leaf)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct GanfanCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}
