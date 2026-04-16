import SwiftUI
import AppKit
import ServiceManagement

@main
struct ClaudeUsageMenuBarApp: App {
    @State private var service = UsageService()
    @State private var settings = AppSettings()

    init() {
        // Auto-register as login item so the app starts on boot
        try? SMAppService.mainApp.register()
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(service: service, settings: settings)
        } label: {
            Image(nsImage: MenuBarIconRenderer.renderFull(
                remaining: service.menuBarRemaining,
                resetTime: settings.showResetTime ? service.sessionWindow?.resetClockShort : nil,
                showLogo: settings.showLogo
            ))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Renders the circular ring icon as an NSImage for the menu bar.
enum MenuBarIconRenderer {
    private static let logoBase64 = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAJKADAAQAAAABAAAAJAAAAAAqDuP8AAAJmUlEQVRYCaVYC2wUxxmemd27vTvbvILKKyCSYvt4hQSSWoU0KH0mTaDClbENbeKUQoRC01KwfTakvfIItkmTVDS00BahiocPN2lTKG3VqI0UkqYBNTgI/OCRh4EIaG1szN3t7e5Mv3/NOn6f1Yy0nr1//pn55n98/6w5G0Y7W1o41zD0ZcmU/dal0JU/Phh93R7GtP9LRU83q2lDwSTmsJgm+LQMw7duUmLc05izY6B5H0aWjU4q59ecs4DDU49N3/b7/w6kN5RMDDVIY9LRHgn5fNM6TYuZjsMUY0+diC4KDTQvyezvjAz487MM/9c16f/WQDrpZGkBCeWcSdhdHrIcyQxdy81MBB8dcGHFv2TaDkvhcZS6PqBOGmF6QPHxx4HjGIB0L8UVX3OooOATAUZgOY5urFSKpRypmKaauyfceqkvy7/9QmXxc+fKC6vr1387o+84/U4LKHvHDhOnLXWkNDmCg06va2LBPVPZ/T0X/CBaYgDRKJIB1A3dcVp6jp8uL5gSEv4/B3RtXWbAX+bXUhtvHaKnWn9AJ1YtCvVVnFETexuH3hOElTDGdMGFFIKCu7slzXY68QgCjdbSfn3sFW+waV3xWINrv/PrYtYNxGIShxKM9zqQp9vLQk2RosLbxmaeOl9R/ObZiuKFnhL1UvEtWOgKso1RnGhCLGquKMrr1lFGlmQsUwMgQDpz7+7dFo29Hy0JcF3u8+vafUnLcdV9AnAYexUPna9X6wWIKfW0TxN3wgKf17g62lhe+H1PO1xTe9lx1Da/1mUln+A+6chKb1w5agy2CdJOivGTnjyVSNQEffrXElZXYsBlrDNlH5MqtMvT6dn3BsTY2zrQu1kiWQiTXzwXKdr7HviFJmXYcjcWrvdrwrUSwD/SVFr0BRrTdDXep3FhIwOAqZ5kTeVLV0L3ex4Y6LOUlJc4F4+Ha/bcIJ2+rReguGlu7jCtPQQKnnE3hakfD3H1t4ZIwbzJL9QlYOMfk53pgZ6m+C0rSTYJwU4ZllS6c7J5fVGeLrQXKOFIV3TFFvColTlVBy70BeL9xrb929lI4XJAel7X+WfI75TyyLJ2LF6eUx3b1VReeBTWe5iCE6Ak6HK+lHIhSLG6I2k1MF1+RTjaa3B9GADdDeA2FresZ8LVh7b03/ETSS8LeeLsqth+20otBBH+hXxuS4nwYiNhrV8C7K+gt8OWqoMOTW4CmDVIvDEuFSnWym3xM2RUDzAaA7kezQ1erfL2GKzvRW49lX7+z4b/3D9heu24Uewa4yIP/g9RbAV8+lwAvAvc5IcbMsklcOAYpHsG+Gcqnimw2gzPMuR+gG/hUl9y29bDadl7QJf1BEbvTRXFYU2p5yiIqXwQ1xAj00PNDQ+8dv1yRd1/ENQqZani3O21MU8IKhhlpswpWDMHi8wAhcyUSrakktZPhwWIFopGo2J5onG10NgmHe6h+EnXKKssx3nHcfgKsMUsJMq9QD1XcZaDs4xDbCIPuBvwRLrX4mY+vxxdFYqnOvOU7SSYJjuEZJ2GCN4URiAx4XSbyevqeu3cECma6mPsRZzkUVupQV1OYMly8OhNdBo2DxBpelakMQVUSBpHCP6+o9ib8WTyB7w5Ulg60vDX3ARxgUMoJZKYFEffiYe44gbmUt+Gs1xWQn2opLqOg61HIM+mgB+qUQyRpagRw4MEUFJ4MyT12OddiN/NCIxomhjdTXsy3Ra+fR1magHiYpbiHJSjgpBn4hkDcwpakE6GU7j9rVMzuh8NBQaHoKRLIfjPS9v+N5joLc6cfwVMdob4jIYHau48GmhZWxC0lWWoUNAwpQpy6Rhg1AAXPMCkNLC4H773S5sLTVNZ2G0jMn7GYKAIOFonKtsxWOVUl2WYxG8d75SbbVyyVpSiNiTK1ZyaWANN6AZEP4bTcL/+LExViYnFsFqQsm6gRsyMzLmIuqZnGb7xBqKaspIOAKu58YO4wVlpPk9CttsKOKXDBnSmMn+CX/l/iMlPBn1aFtUncNAp7DudTu1RgAeOsget2ZHOCg3Zgth7ADjmQzoH/WTwGQcsxC39BesG/KwtYZalBVS//qsZQW30d3Hi9ciU28kVpi0/dpSzCRs+7Nf0xQhWSoAAxnRs1t2o5MAiF0xpLZ5Z/fJpGjgbXT5CxlVYE87ncLj5ADMP8TsRy75ucb5hSEDNZYX5miae0TV+Nw7hmhwWroun1DpdZ6uzDK0ibjkdKJg7EPxlAAn7c6MbEaZkoIbgAFcsxZaFqw7+vceY++rGrqGNu6Oq9gMSDAjoVGXxuKBUVYiREmJlyjLQxUfw94bs6kP7GkqXFhs+7QBloGnbT5HNR4WMnW1x8xd4zTV0/YvkQsuWR7DDiBEB/wPxlH0Dv1eEt8fqXCSD/OlXXJsjS7+Mb5w3UEhLCC1RE2rYXls48wlMY2XxXT5d20nuQME8gkK8E8w5x70nMtYANow4SqJ8KffujVDa2mmm9lPcwVj7m8uKVg2CxRX3A6QU3z7C8GVTTGJRfDnwJdOqap/I3Vp3iS5qwpG/Bc2Piqesj4S0VtMqUM2h7AHzduRWxY7jfT/dLBHYo5Flm66ZcmVnytqOOuFDLO9qLCssHQxUP0BYfA/o/AiezXaKL5i27eAfaDLVMoPJl0J+fQ7qGG5J4snsmlcunigvGInhHPqIhHWuuhuZakPSsi/TTQDXl7wxPl6RUxUrg9vWwnAmaKAGoLYorOnq9/hDXhlWayxfWhbU9Wril4Rtbc6pOvQjmng2UnQPuuMwjwDr5ZGFSI4Nlxu62AffUfFM4v79YDa+XhrLlj4Il+9CucpuTSS3AuhG0vdaP4TeQM++MVLwkE9om3FNwK3Pfs0KqO5bH9w6G1bQkF5J4bBWb15uTewASPNlijUAwrc+e6mxbHFWuObQP0xmLkS5OoxkCHv6Xp8WUHNk2Z2oZr8J+DR/wrJO4XpaMjNal/IWQNzMI6uhdUop2j05JMq0+Fpw1EUK8Ey/PhfEXkLjM5595eM7nj34jcxg/DFP3+vTApLK2Tw2ZExMpOxz+C/IEgpubzL1oIW7Ec702u7PMoggu9vs52tbUBLWEF7384mred4gAZ4YPexWeE9GfVpAyLaT+BI5ZiknP3t77HzPyfRFinXDIEaIeevU6F6z5zi9h6tjr9q23IjMewMZ96e+431/u7buKxzu76ZI4X34OHyHvtMStvNXbP7QcOcOppfWQoNNJHkoIM8jPs6BCmAo9t5QusMd+1SAJkfrWpUjvtlu2k+Y0v+T4W46lN7/ALlBeJ+q43J/AAAAAElFTkSuQmCC"

    static func claudeLogo() -> NSImage? {
        guard let data = Data(base64Encoded: logoBase64),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    static func shortModelName(_ raw: String) -> String {
        if raw.contains("opus") { return "OPUS" }
        if raw.contains("sonnet") { return "SONNET" }
        if raw.contains("haiku") { return "HAIKU" }
        return raw.uppercased()
    }

    static func renderFull(remaining: Double, resetTime: String?, showLogo: Bool = true) -> NSImage {
        let logoSize: CGFloat = 16
        let ringSize: CGFloat = 22
        let gap: CGFloat = 4
        let timeText = (resetTime != nil && resetTime != "—") ? resetTime! : ""

        // Measure the time text width
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: timeFont,
            .foregroundColor: NSColor.white,
        ]
        let timeSize = (timeText as NSString).size(withAttributes: timeAttrs)
        let textWidth = timeText.isEmpty ? 0 : timeSize.width
        let timeGap = timeText.isEmpty ? 0 : gap
        let logoWidth = showLogo ? logoSize + gap : 0

        let totalWidth = logoWidth + ringSize + timeGap + textWidth
        let height: CGFloat = 22

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
            var xOffset: CGFloat = 0

            // Draw Claude logo on the left
            if showLogo {
                if let logoData = Data(base64Encoded: logoBase64),
                   let logoImg = NSImage(data: logoData) {
                    let logoY = (height - logoSize) / 2
                    logoImg.draw(in: CGRect(x: 0, y: logoY, width: logoSize, height: logoSize),
                                 from: .zero, operation: .sourceOver, fraction: 1.0)
                }
                xOffset = logoSize + gap
            }

            // Draw ring
            let ringImg = renderRing(remaining: remaining)
            ringImg.draw(in: CGRect(x: xOffset, y: 0, width: ringSize, height: ringSize),
                         from: .zero, operation: .sourceOver, fraction: 1.0)
            xOffset += ringSize

            // Draw reset time text on the right
            if !timeText.isEmpty {
                xOffset += gap
                let textY = (height - timeSize.height) / 2
                (timeText as NSString).draw(
                    at: CGPoint(x: xOffset, y: textY),
                    withAttributes: timeAttrs
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func renderRing(remaining: Double) -> NSImage {
        let size: CGFloat = 22
        let lineWidth: CGFloat = 2.0
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = (size - lineWidth) / 2

            let trackPath = NSBezierPath()
            trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            trackPath.lineWidth = lineWidth
            NSColor.gray.withAlphaComponent(0.3).setStroke()
            trackPath.stroke()

            let color: NSColor
            if remaining > 30 {
                color = NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1)
            } else if remaining > 10 {
                color = NSColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1)
            } else {
                color = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)
            }

            if remaining > 0 {
                let startAngle: CGFloat = 90
                let endAngle = startAngle - (remaining / 100.0) * 360.0
                let arcPath = NSBezierPath()
                arcPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                arcPath.lineWidth = lineWidth
                arcPath.lineCapStyle = .round
                color.setStroke()
                arcPath.stroke()
            }

            let pct = Int(remaining)
            let text = "\(pct)" as NSString
            let fontSize: CGFloat = pct == 100 ? 7.0 : 8.0
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }
}
