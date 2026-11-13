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
                Text("干饭手册")
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
