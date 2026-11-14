import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Design tokens matching Shadowrocket's dark utility aesthetic
public enum Theme {
    /// Pure deep black background
    public static let background = Color.black

    /// Card and grouped cell background (#1C1C1E)
    public static let cardBackground = Color(red: 28/255, green: 28/255, blue: 30/255)

    /// Elevated subcard / border separator (#2C2C2E)
    public static let secondaryCard = Color(red: 44/255, green: 44/255, blue: 46/255)

    /// Divider color
    public static let divider = Color(red: 58/255, green: 58/255, blue: 60/255)

    /// Signature active node selection dot and accent (#FF9500)
    public static let orange = Color(red: 255/255, green: 149/255, blue: 0/255)

    /// Connected state and DIRECT action (#34C759)
    public static let green = Color(red: 52/255, green: 199/255, blue: 89/255)

    /// PROXY action accent (#007AFF)
    public static let blue = Color(red: 0/255, green: 122/255, blue: 255/255)

    /// BLOCK action and error accent (#FF3B30)
    public static let red = Color(red: 255/255, green: 59/255, blue: 48/255)

    /// Secondary label color (#8E8E93)
    public static let secondaryText = Color(red: 142/255, green: 142/255, blue: 147/255)

    /// Subtle text color (#636366)
    public static let tertiaryText = Color(red: 99/255, green: 99/255, blue: 102/255)
}

/// Cross-platform clipboard utility for iOS and macOS
public enum ClipboardHelper {
    public static func getString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }

    public static func setString(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
