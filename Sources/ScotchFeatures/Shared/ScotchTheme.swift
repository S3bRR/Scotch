import SwiftUI

public enum ScotchTheme {
    public static let accent = Color(red: 0.53, green: 0.86, blue: 0.12)

    public enum Spacing {
        public static let xSmall: CGFloat = 6
        public static let small: CGFloat = 10
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
    }

    public enum Radius {
        public static let medium: CGFloat = 10
    }

    public enum ViewWidth {
        public static let small: CGFloat = 400
        public static let medium: CGFloat = 500
        public static let large: CGFloat = 600
    }
}

extension Animation {
    static let scotchDefault: Animation = .easeInOut(duration: 0.2)
}
