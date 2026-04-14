import SwiftUI

extension View {
    func bottomBar<Content>(
        @ViewBuilder content: () -> Content
    ) -> some View where Content: View {
        modifier(BottomBarViewModifier(barContent: content()))
    }
}

private struct BottomBarViewModifier<BarContent>: ViewModifier where BarContent: View {
    var barContent: BarContent

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                barContent
                    .buttonStyle(BottomBarButtonStyle())
            }
    }
}

private struct BottomBarButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.trigger()
        } label: {
            configuration.label
                .foregroundStyle(.foreground)
        }
    }
}
