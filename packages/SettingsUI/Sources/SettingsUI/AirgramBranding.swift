import Cocoa
import TGUIKit
import TelegramTheme

enum AirgramBranding {
    static var versionText: String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
        return "\(version) (\(build))"
    }

    static func logo(size: NSSize, cornerRadius: CGFloat) -> CGImage? {
        guard let source = NSImage(named: "Icon_AirGram_Logo")?.precomposed(flipVertical: true) else {
            return nil
        }
        return generateImage(size, contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
            ctx.round(size, cornerRadius)
            ctx.draw(source, in: size.bounds)
        }, scale: System.backingScale)
    }

    static var settingsLogo: CGImage? {
        return logo(size: NSMakeSize(24, 24), cornerRadius: 5)
    }

    static func categoryIcon(symbol: String, color: String) -> CGImage? {
        let background = NSColor(hexString: color) ?? .gray
        return generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
            ctx.round(size, 5)
            ctx.setFillColor(background.cgColor)
            ctx.fill(size.bounds)
            if #available(macOS 11.0, *), let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)) {
                let glyph = image.precomposed(.white, flipVertical: true)
                let glyphSize = glyph.backingSize
                ctx.draw(glyph, in: NSMakeRect(floorToScreenPixels(System.backingScale, (size.width - glyphSize.width) / 2), floorToScreenPixels(System.backingScale, (size.height - glyphSize.height) / 2), glyphSize.width, glyphSize.height))
            }
        }, scale: System.backingScale)
    }

    static var airgramCategoryIcon: CGImage? {
        return categoryIcon(symbol: "hand.raised.fill", color: "#5E5CE6")
    }

    static var ghostModeIcon: CGImage? {
        return categoryIcon(symbol: "eye.fill", color: "#AF52DE")
    }
}
