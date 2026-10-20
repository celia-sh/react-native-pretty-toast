import SwiftUI

struct PrettyToastView: View {
    @ObservedObject var window: PassThroughWindow
    @State private var measuredContentHeight: CGFloat = 0

    var body: some View {
        let hole = window.useDynamicIsland ? CameraCutout.holePunch(screenSize: window.bounds.size) : nil
        GeometryReader {
            let safeArea = $0.safeAreaInsets
            let cutout: CameraCutout? = if let hole {
                .holePunch(hole)
            } else if window.useDynamicIsland && CameraCutout.hasDynamicIsland(safeAreaTop: safeArea.top) {
                .dynamicIsland
            } else {
                nil
            }
            let geometry = PillGeometry(cutout: cutout, size: $0.size, safeAreaTop: safeArea.top)
            let morphsFromCutout = geometry.morphsFromCutout

            let expandedWidth = geometry.expandedWidth
            let overflow = max(0, measuredContentHeight - geometry.baseContentArea)
            let expandedHeight: CGFloat = geometry.baseHeight + overflow

            let scaleX: CGFloat = isExpanded ? 1 : (geometry.collapsedSize.width / expandedWidth)
            let scaleY: CGFloat = isExpanded ? 1 : (geometry.collapsedSize.height / expandedHeight)

            ZStack {
                toastBackground()
                    .overlay {
                        ToastContent(insets: geometry.contentInsets)
                            .frame(width: expandedWidth, height: expandedHeight)
                            .scaleEffect(x: scaleX, y: scaleY)
                    }
                    .frame(
                        width: isExpanded ? expandedWidth : geometry.collapsedSize.width,
                        height: isExpanded ? expandedHeight : geometry.collapsedSize.height
                    )
                    .opacity(morphsFromCutout ? 1 : (isExpanded ? 1 : 0))
                    .modifier(CapsuleOpacityModifier(
                        haveDynamicIsland: morphsFromCutout,
                        isExpanded: isExpanded
                    ))
                    .modifier(GeometryGroupModifier())
                    .contentShape(Rectangle())
                    .onTapGesture {
                        window.wasTapped = true
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2).onEnded { value in
                            if value.translation.height < -8 || value.predictedEndTranslation.height < -40 {
                                window.isPresented = false
                            }
                        }
                    )
                    .offset(isExpanded ? geometry.expandedOffset : geometry.collapsedOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, morphsFromCutout ? 0 : (isExpanded ? max(safeArea.top, 10) : 0))
            .ignoresSafeArea()
            .animation(.bouncy(duration: 0.3, extraBounce: 0), value: isExpanded)
        }
        // A hole is placed against the whole window: the safe area can exclude a
        // vertical status bar, and a pill wider than the safe area gets pinned to
        // its leading edge instead of centered.
        .ignoresSafeArea(edges: hole == nil ? [] : .all)
    }

    @ViewBuilder
    func ToastContent(insets: EdgeInsets) -> some View {
        if let toast = window.toast {
            contentRow(toast, measuring: false)
                // Keep the content clear of the camera. The enclosing fixed-height
                // frame centers this padded box, which — because the insets are
                // asymmetric — centers the content within [islandHeight, height - 12]
                // for short content under an island and lets it fill that band
                // exactly once it overflows.
                .padding(insets)
                .compositingGroup()
                .blur(radius: isExpanded ? 0 : 5)
                .opacity(isExpanded ? 1 : 0)

            // Hidden measurer — drives measuredContentHeight so the pill grows for
            // overflowing text. It renders the SAME row as the visible copy: measuring a
            // different layout than the one on screen is what used to truncate messages.
            contentRow(toast, measuring: true)
                // A hole beside the content narrows the row, so the measurer needs the
                // same side insets to wrap the text the same way.
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ContentHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )
                .hidden()
                .allowsHitTesting(false)
                .onPreferenceChange(ContentHeightKey.self) { height in
                    measuredContentHeight = height
                }
        }
    }

    /// The one row layout, used both to draw the toast and to measure how tall it needs to
    /// be. Keeping them in one place is the point: when the measurer was a separate copy it
    /// left out the action button, so it sized the text against a column ~90pt wider than
    /// the text actually gets. A message that wraps to three lines next to a button was
    /// measured at two, the pill came up a line short, and the text was clipped.
    @ViewBuilder
    private func contentRow(_ toast: Toast, measuring: Bool) -> some View {
        HStack(spacing: 10) {
            // Only the width matters for measurement, and drawing the icon twice would run
            // its symbol animation twice.
            if measuring {
                Color.clear.frame(width: 50, height: 1)
            } else {
                ToastIconView(toast: toast, isExpanded: isExpanded)
                    .frame(width: 50)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(toast.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    // Without this the enclosing fixed-height frame may clamp the text
                    // rather than let it report the height it actually wants — which
                    // truncated even single-line strings when the frame was a point short.
                    .fixedSize(horizontal: false, vertical: true)

                if !toast.message.isEmpty {
                    Text(toast.message)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let label = toast.actionLabel, !label.isEmpty {
                Button(action: { window.actionTapped = true }) {
                    Text(label)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(toast.accentColor)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func toastBackground() -> some View {
        let accent = window.toast?.accentColor ?? .white
        let strokeOverride = window.toast?.strokeOverride
        let disableSampling = window.toast?.disableBackdropSampling ?? false
        let tint: BackdropTint = disableSampling ? .gray : window.backdropTint
        return Group {
            if #available(iOS 26, *) {
                makeStrokeBackground(
                    shape: ConcentricRectangle(
                        corners: .concentric(minimum: .fixed(30)),
                        isUniform: true
                    ),
                    accent: accent,
                    strokeOverride: strokeOverride,
                    tint: tint
                )
            } else {
                makeStrokeBackground(
                    shape: RoundedRectangle(cornerRadius: 30, style: .continuous),
                    accent: accent,
                    strokeOverride: strokeOverride,
                    tint: tint
                )
            }
        }
    }

    private func makeStrokeBackground<S: Shape>(
        shape: S,
        accent: Color,
        strokeOverride: Color?,
        tint: BackdropTint
    ) -> some View {
        shape
            .fill(.black)
            .overlay {
                ZStack {
                    if let override = strokeOverride {
                        strokeLayer(shape: shape, color: override, alpha: 1.0, visible: isExpanded)
                    } else {
                        strokeLayer(shape: shape, color: accent, alpha: 0.2, visible: isExpanded && tint == .colored)
                        strokeLayer(shape: shape, color: .white, alpha: 0.06, visible: isExpanded && tint == .gray)
                    }
                }
            }
    }

    @ViewBuilder
    private func strokeLayer<S: Shape>(shape: S, color: Color, alpha: Double, visible: Bool) -> some View {
        let stroke = shape.stroke(color.opacity(alpha), lineWidth: 1.5)
        if #available(iOS 17, *) {
            // Scope easeInOut to opacity only; frame changes keep the bouncy
            // ambient animation so the stroke tracks the pill geometry.
            stroke.animation(.easeInOut(duration: 0.3)) { view in
                view.opacity(visible ? 1 : 0)
            }
        } else {
            stroke
                .opacity(visible ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: visible)
        }
    }

    var isExpanded: Bool {
        window.isPresented
    }
}

struct ToastIconView: View {
    let toast: Toast
    let isExpanded: Bool

    var body: some View {
        if let image = toast.customIcon {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 35, height: 35)
        } else {
            Image(systemName: toast.symbol)
                .font(toast.symbolFont)
                .foregroundStyle(toast.symbolForegroundStyle.0, toast.symbolForegroundStyle.1)
                .modifier(WiggleModifier(isExpanded: isExpanded))
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct WiggleModifier: ViewModifier {
    let isExpanded: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.symbolEffect(.wiggle, value: isExpanded)
        } else {
            content
        }
    }
}

private struct CapsuleOpacityModifier: ViewModifier {
    let haveDynamicIsland: Bool
    let isExpanded: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .animation(.linear(duration: 0.02).delay(isExpanded ? 0 : 0.28)) { inner in
                    inner.opacity(haveDynamicIsland ? (isExpanded ? 1 : 0) : 1)
                }
        } else {
            content
                .opacity(haveDynamicIsland ? (isExpanded ? 1 : 0) : 1)
                .animation(.linear(duration: 0.02).delay(isExpanded ? 0 : 0.28), value: isExpanded)
        }
    }
}

private struct GeometryGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.geometryGroup()
        } else {
            content
        }
    }
}
