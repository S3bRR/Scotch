import SwiftUI

/// Shared Liquid Glass styling helpers for Scotch's macOS Tahoe interface.
public enum ScotchGlass {
    /// Standard tinted glass using the app accent.
    public static var accentTinted: Glass {
        Glass.regular.tint(ScotchTheme.accent.opacity(0.18))
    }

    /// Subtle glass for ambient panels and bars.
    public static var ambient: Glass {
        Glass.regular
    }

    /// Reactive glass for tappable surfaces (pin tiles, etc).
    public static var interactive: Glass {
        Glass.regular.interactive()
    }
}

extension View {
    /// Applies a soft glass panel with rounded corners, suitable for floating cards.
    func scotchGlassCard(cornerRadius: CGFloat = ScotchTheme.Radius.medium) -> some View {
        self.glassEffect(ScotchGlass.ambient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Applies a translucent capsule-shaped glass background, ideal for pills/badges.
    func scotchGlassPill() -> some View {
        self.glassEffect(ScotchGlass.ambient)
    }

    /// Applies an interactive glass surface that responds to hover/press.
    func scotchGlassInteractive(cornerRadius: CGFloat = ScotchTheme.Radius.medium) -> some View {
        self.glassEffect(ScotchGlass.interactive, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
