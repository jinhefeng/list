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
        "BrandIconSuiYinJiLiang"
    ]

    let assetName: String?
    let symbol: String?
    let imageID: UUID?
    var dimension: CGFloat = 20
    @State private var customImage: UIImage?

    init(assetName: String? = nil, symbol: String?, imageID: UUID? = nil, dimension: CGFloat = 20) {
        self.assetName = assetName
        self.symbol = symbol
        self.imageID = imageID
        self.dimension = dimension
        _customImage = State(initialValue: nil)
    }

    private var resolvedAssetName: String? {
        guard let assetName = assetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !assetName.isEmpty,
              UIImage(named: assetName) != nil else {
            return nil
        }
        return assetName
    }

    private var needsWhiteBacking: Bool {
        guard let resolvedAssetName else { return false }
        return !Self.assetsWithOwnBackground.contains(resolvedAssetName)
    }

    var body: some View {
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
                    .frame(width: dimension, height: dimension)
                    .background(needsWhiteBacking ? Color.white : Color.clear)
            } else {
                fallbackIcon
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(RoundedRectangle(cornerRadius: dimension * 0.24, style: .continuous))
        .task(id: imageID) {
            guard let imageID else {
                customImage = nil
                return
            }
            let data = await Task.detached(priority: .utility) {
                AppStoragePaths.brandLogoImageData(for: imageID)
            }.value
            customImage = data.flatMap(UIImage.init(data:))
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
                Text("食光记")
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
