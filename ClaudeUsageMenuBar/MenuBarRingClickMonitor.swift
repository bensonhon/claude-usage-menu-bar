import AppKit

/// Picks the account tab whose ring was clicked in the menu bar. MenuBarExtra
/// does not say where its item was clicked, so this watches the app's own mouse
/// events and, just before the popover toggles, reports the ring under the click.
@MainActor
final class MenuBarRingClickMonitor {
    private var eventMonitor: Any?

    init(accountRings: @escaping () -> [MenuBarAccountRing],
         showLogo: @escaping () -> Bool,
         onRingClicked: @escaping (Int) -> Void) {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if let button = Self.menuBarButton(in: event.window),
               let image = button.image {
                // The image is centered in the button.
                let imageX = button.convert(event.locationInWindow, from: nil).x
                    - (button.bounds.width - image.size.width) / 2
                if let index = MenuBarIconRenderer.accountIndex(atX: imageX,
                                                                accountRings: accountRings(),
                                                                showLogo: showLogo()) {
                    onRingClicked(index)
                }
            }
            return event
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private static func menuBarButton(in window: NSWindow?) -> NSButton? {
        guard let window, window.level == .statusBar, let contentView = window.contentView else { return nil }
        return firstButton(in: contentView)
    }

    private static func firstButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let button = firstButton(in: subview) { return button }
        }
        return nil
    }
}
