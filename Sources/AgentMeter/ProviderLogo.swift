import SwiftUI
import AgentMeterCore

private let providerLogoBundle: Bundle = {
    // Packaged apps keep SwiftPM resources in Contents/Resources.
    if let url = Bundle.main.url(forResource: "AgentMeter_AgentMeter", withExtension: "bundle"),
       let bundle = Bundle(url: url) {
        return bundle
    }
    return .module
}()

private let providerLogoImages: [Provider: NSImage] = Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { provider in
    let fileExtension = provider == .gemini ? "jpg" : "png"
    guard let url = providerLogoBundle.url(forResource: provider.rawValue, withExtension: fileExtension),
          let image = NSImage(contentsOf: url) else { return nil }
    return (provider, image)
})

struct ProviderLogo: View {
    let provider: Provider
    var size: CGFloat = 20

    // MenuBarExtra bridges to NSStatusItem and may ignore SwiftUI frame modifiers.
    // Give AppKit an image with the desired intrinsic size instead.
    static func menuBarImage(for provider: Provider) -> NSImage {
        let source = providerLogoImages[provider]
            ?? NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: provider.name)!
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let circle = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            NSColor.white.setFill()
            circle.fill()
            source.draw(in: NSRect(x: 1, y: 1, width: 16, height: 16),
                        from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }

    // Render the title with AppKit so MenuBarExtra cannot replace its font.
    static func menuBarLabel(for provider: Provider, title: String) -> NSImage {
        let logo = menuBarImage(for: provider)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        let gap: CGFloat = 8
        // Lay out each field explicitly so repeated spaces cannot widen a gap.
        let fields = title.split(whereSeparator: { $0.isWhitespace }).map { String($0) as NSString }
        let fieldSizes = fields.map { $0.size(withAttributes: [.font: font]) }
        let size = NSSize(width: logo.size.width + fieldSizes.reduce(0) { $0 + gap + ceil($1.width) },
                          height: max(logo.size.height, ceil(fieldSizes.map(\.height).max() ?? 0)))
        let image = NSImage(size: size, flipped: false) { bounds in
            logo.draw(at: NSPoint(x: 0, y: (bounds.height - logo.size.height) / 2),
                      from: .zero, operation: .sourceOver, fraction: 1)
            var x = logo.size.width
            for (field, fieldSize) in zip(fields, fieldSizes) {
                x += gap
                field.draw(
                    at: NSPoint(x: x, y: (bounds.height - fieldSize.height) / 2),
                    withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
                x += ceil(fieldSize.width)
            }
            return true
        }
        image.isTemplate = false
        image.cacheMode = .never
        image.accessibilityDescription = "\(provider.name) · \(title)"
        return image
    }

    var body: some View {
        logo
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .padding(provider == .claude ? 0 : size * 0.08)
            .frame(width: size, height: size)
            .background(.white)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var logo: Image {
        if let image = providerLogoImages[provider] {
            return Image(nsImage: image)
        }
        return Image(systemName: "photo")
    }
}
