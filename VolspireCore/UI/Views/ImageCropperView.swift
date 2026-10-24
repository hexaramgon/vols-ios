//
//  ImageCropperView.swift
//  Volspire
//
//  Image picker for a fixed output aspect ratio (default 1:1; pass e.g. 3 for a
//  wide banner) with two modes:
//   • Fit  — the whole image, aspect-fit into the target canvas, with the empty
//            bars filled by a blurred, zoomed copy of the same image (mirrors the
//            web app's blur-fill for off-ratio covers). Nothing is cropped.
//   • Crop — the classic "move & scale" cropper (a UIScrollView does the zoom/pan
//            + crop-rect math, more reliable than SwiftUI gestures).
//  The image must be orientation-normalised first — see `normalizedUp()`.
//

import CoreImage
import DesignSystem
import SwiftUI
import UIKit

/// A picked image awaiting crop — drives the full-screen cropper presentation.
/// THE shared item type for `.fullScreenCover(item:)` + `ImageCropperView`
/// (four screens had private copies of it).
struct CropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// A "what this platform shows" band drawn inside the crop frame: the
/// centred region of `aspect` (width ÷ height) that a display filling that
/// shape keeps (e.g. banners: iPhone vs desktop).
struct CropGuide: Hashable {
    let label: String
    let aspect: CGFloat
}

struct ImageCropperView: View {
    /// Source image — pass `someImage.normalizedUp()` so pixel coords match display.
    let image: UIImage
    /// Cropped/fitted JPEG data at `aspectRatio`, delivered when the user taps Done.
    let onCrop: (Data) -> Void
    let onCancel: () -> Void

    /// Output width ÷ height. 1 = square (avatar/track cover), 3 = wide banner.
    var aspectRatio: CGFloat = 1
    /// Max side length (px) of the exported image's longer edge.
    var outputSize: CGFloat = 1024
    /// When false the picker is crop-only: no Fit/Crop toggle, no blur-fill —
    /// avatars and banners always crop; covers keep both modes.
    var allowsFitMode = true
    /// Dim outside an inscribed circle (avatar crops) so the preview shows
    /// exactly what the round profile picture will contain.
    var showsCircularMask = false
    /// Centred safe-area bands to draw in the frame (see `CropGuide`).
    var guides: [CropGuide] = []

    /// Pixel size of the exported canvas, sized so its longer edge is `outputSize`.
    private var outputCanvas: CGSize {
        aspectRatio >= 1
            ? CGSize(width: outputSize, height: outputSize / aspectRatio)
            : CGSize(width: outputSize * aspectRatio, height: outputSize)
    }

    private enum Mode: String, CaseIterable, Identifiable {
        case fit = "Fit", crop = "Crop"
        var id: Self { self }
    }

    @State private var mode: Mode
    @State private var cropper = ScrollCropper()
    /// True while a finger is dragging / pinching — shows the thirds grid.
    @State private var adjusting = false
    /// The rendered blur-fill image — generated once so the preview is exactly
    /// what gets uploaded (WYSIWYG), and reused for Done.
    @State private var fitImage: UIImage?

    init(
        image: UIImage,
        onCrop: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void,
        aspectRatio: CGFloat = 1,
        outputSize: CGFloat = 1024,
        allowsFitMode: Bool = true,
        showsCircularMask: Bool = false,
        guides: [CropGuide] = []
    ) {
        self.image = image
        self.onCrop = onCrop
        self.onCancel = onCancel
        self.aspectRatio = aspectRatio
        self.outputSize = outputSize
        self.allowsFitMode = allowsFitMode
        self.showsCircularMask = showsCircularMask
        self.guides = guides
        // Crop-only starts (and stays) in crop — no onAppear flip, no re-mount.
        _mode = State(initialValue: allowsFitMode ? .fit : .crop)
    }

    var body: some View {
        // A full-screen cover lays out edge-to-edge with no safe-area inset, so pad
        // by the window's real insets. (A GeometryReader with .ignoresSafeArea
        // reports zero insets, so that approach is a no-op — use the window here.)
        let insets = ViewConst.safeAreaInsets
        return VStack(spacing: 0) {
            header

            GeometryReader { geo in
                // Largest box of the target aspect ratio that fits the space,
                // with a margin so the image can show (dimmed) around it.
                let margin: CGFloat = mode == .crop ? 20 : 0
                let boxW = min(geo.size.width - margin * 2, (geo.size.height - margin * 2) * aspectRatio)
                let boxH = boxW / aspectRatio
                let box = CGRect(
                    x: (geo.size.width - boxW) / 2, y: (geo.size.height - boxH) / 2,
                    width: boxW, height: boxH
                )
                Group {
                    switch mode {
                    case .fit:
                        if let fitImage {
                            Image(uiImage: fitImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: boxW, height: boxH)
                        } else {
                            // Sharp aspect-fit stand-in while the blur-fill renders —
                            // same placement as the final render, only the letterbox
                            // bars change when it lands.
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: boxW, height: boxH)
                        }
                    case .crop:
                        // The photo fills the whole area and pans/zooms behind
                        // the frame (Photos / Instagram style); what's outside
                        // the frame stays visible, dimmed.
                        ZoomableImageScrollView(
                            image: image,
                            cropper: cropper,
                            box: box,
                            onAdjusting: { on in withAnimation(.easeOut(duration: 0.2)) { adjusting = on } }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay { cropChrome(box: box) }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height) // centre the box
            }

            if mode == .crop {
                Text("Pinch to zoom · Drag to move")
                    .font(.appFootnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 10)
                    .padding(.bottom, allowsFitMode ? 4 : 12)
            }

            if allowsFitMode {
                modeToggle
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .padding(.top, insets.top)
        .padding(.bottom, max(insets.bottom, 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        // The manual window-inset paddings above are the ONLY inset source —
        // without this, the cover ALSO applies the system safe area and the
        // whole layout ends up double-padded (header pushed down, box floating
        // between giant black gaps).
        .ignoresSafeArea()
        .alwaysDark()
        // Render the blur-fill once so the Fit preview matches the exported bytes
        // exactly. Off the main thread: the Gaussian blur on a full-size photo is
        // slow enough to freeze the cover presentation (the header and Fit/Crop
        // toggle drew visibly late). (Crop-only skips it.)
        .task {
            guard allowsFitMode, fitImage == nil else { return }
            let source = image
            let canvas = outputCanvas
            fitImage = await Task.detached(priority: .userInitiated) {
                BlurFill.render(source, size: canvas)
            }.value
        }
    }

    /// App-style top bar: an "X" close, a centred title, and a white-capsule Done
    /// (the primary-action treatment used across the app's sheets).
    private var header: some View {
        ZStack {
            Text(mode == .fit ? "Fit Image" : "Move & Scale")
                .font(.appCalloutSemibold)
                .foregroundStyle(.white)

            HStack {
                Button(action: onCancel) {
                    LucideIcon(.x, .xxl)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: done) {
                    Text("Done")
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// Over the crop: the area outside the frame dimmed (a circle cut-out for
    /// avatars), the frame's hairline, and a rule-of-thirds grid while
    /// adjusting. Never takes touches — the scroll view below does.
    private func cropChrome(box: CGRect) -> some View {
        ZStack {
            CropCutoutMask(box: box, circular: showsCircularMask)
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            Group {
                if showsCircularMask {
                    Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                } else {
                    Rectangle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                }
            }
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
            ThirdsGrid()
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .opacity(adjusting ? 1 : 0)
            ForEach(guides, id: \.self) { guide in
                guideBand(guide, in: box)
            }
        }
        .allowsHitTesting(false)
    }

    /// One guide: a dashed outline of the centred band `guide.aspect` keeps,
    /// with its name in the corner.
    private func guideBand(_ guide: CropGuide, in box: CGRect) -> some View {
        let boxAspect = box.width / box.height
        let size = guide.aspect < boxAspect
            ? CGSize(width: box.height * guide.aspect, height: box.height)
            : CGSize(width: box.width, height: box.width / guide.aspect)
        return Rectangle()
            .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .overlay(alignment: .topLeading) {
                Text(guide.label)
                    .font(.appCaption2Medium)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(4)
            }
            .frame(width: size.width, height: size.height)
            .position(x: box.midX, y: box.midY)
    }

    /// Capsule segmented toggle matching the app's pill controls.
    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { option in
                Button { mode = option } label: {
                    Text(option.rawValue)
                        .font(.appFootnoteMedium)
                        .foregroundStyle(mode == option ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(mode == option ? Color.white : Color.clear, in: Capsule())
                        // The unselected side's background is clear, and clear
                        // doesn't hit-test — without this only the text glyphs
                        // were tappable.
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08), in: Capsule())
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
    }

    private func done() {
        switch mode {
        case .fit:
            if let data = fitImage?.jpegData(compressionQuality: 0.9) { onCrop(data) }
        case .crop:
            if let data = cropper.cropJPEG(maxPixel: outputSize) {
                onCrop(data)
            } else if let data = centerFillJPEG() {
                // The live crop couldn't be read (scroll view not laid out) —
                // export the default framing rather than a dead Done button.
                onCrop(data)
            }
        }
    }

    /// The image aspect-filled (center-cropped) into the output canvas — what
    /// the crop view shows before any pan/zoom.
    private func centerFillJPEG() -> Data? {
        let canvas = CGRect(origin: .zero, size: outputCanvas)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = max(canvas.width / max(image.size.width, 1), canvas.height / max(image.size.height, 1))
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: canvas.size, format: format).image { _ in
            image.draw(in: CGRect(
                x: canvas.midX - drawn.width / 2,
                y: canvas.midY - drawn.height / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }
        return rendered.jpegData(compressionQuality: 0.9)
    }
}

/// The whole area with the crop frame removed (even-odd fill) — a rectangle,
/// or the frame's inscribed circle for avatars.
private struct CropCutoutMask: Shape {
    let box: CGRect
    let circular: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if circular {
            let side = min(box.width, box.height)
            path.addEllipse(in: CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side))
        } else {
            path.addRect(box)
        }
        return path
    }
}

/// Rule-of-thirds lines inside a rect.
private struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1 ... 2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            let y = rect.minY + rect.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}

// MARK: - Blur-fill (letterbox) renderer

/// Renders an image into a fixed-size canvas: a blurred, aspect-filled copy
/// behind the sharp, aspect-fit original — so off-ratio images fit without
/// cropping (the web app's cover treatment).
enum BlurFill {
    static func render(_ image: UIImage, size: CGSize) -> UIImage {
        let canvas = CGRect(origin: .zero, size: size)
        let background = blurred(image, radius: min(size.width, size.height) * 0.045) ?? image

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas.size, format: format).image { _ in
            // Blurred fill (covers the whole square), then a subtle scrim so the
            // sharp foreground reads clearly against a busy blur.
            background.draw(in: aspectFillRect(for: background.size, in: canvas))
            UIColor.black.withAlphaComponent(0.12).setFill()
            UIRectFillUsingBlendMode(canvas, .normal)
            // Sharp, whole image centred.
            image.draw(in: aspectFitRect(for: image.size, in: canvas))
        }
    }

    private static func aspectFitRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let out = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - out.width / 2, y: bounds.midY - out.height / 2, width: out.width, height: out.height)
    }

    private static func aspectFillRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let out = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - out.width / 2, y: bounds.midY - out.height / 2, width: out.width, height: out.height)
    }

    private static func blurred(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let ciInput = CIImage(image: image) else { return nil }
        // Clamp so the blur samples the edge pixels instead of fading to transparent.
        let clamped = ciInput.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(output, from: ciInput.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Zoom/pan scroll view

/// UIScrollView that reports layout passes, so we can size the image once the
/// view actually has bounds (SwiftUI may call `updateUIView` before that).
private final class CropScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage
    let cropper: ScrollCropper
    /// The crop frame within the scroll view's bounds; the space around it is
    /// content inset, so the image can pan under the dimmed margins while the
    /// frame stays fully covered.
    let box: CGRect
    let onAdjusting: (Bool) -> Void

    func makeUIView(context: Context) -> CropScrollView {
        let scrollView = CropScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)

        context.coordinator.imageView = imageView
        cropper.scrollView = scrollView
        cropper.image = image

        scrollView.onLayout = { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.setupIfNeeded(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: CropScrollView, context: Context) {
        context.coordinator.onAdjusting = onAdjusting
        context.coordinator.box = box
        context.coordinator.setupIfNeeded(scrollView)
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.box = box
        c.onAdjusting = onAdjusting
        return c
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var box: CGRect = .zero
        var onAdjusting: (Bool) -> Void = { _ in }
        private var didSetup = false

        /// Sized once the scroll view has real bounds: fit the image to fill the
        /// (possibly non-square) crop box (min zoom), cap max zoom, and centre it.
        func setupIfNeeded(_ scrollView: UIScrollView) {
            guard !didSetup, let imageView, scrollView.bounds.width > 1, scrollView.bounds.height > 1,
                  box.width > 1, box.height > 1 else { return }
            let imageSize = imageView.image?.size ?? .zero
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            didSetup = true

            // The margins around the frame are inset, so the image's edges can
            // reach the frame's edges but never come inside it.
            let bounds = scrollView.bounds.size
            scrollView.contentInset = UIEdgeInsets(
                top: box.minY, left: box.minX,
                bottom: bounds.height - box.maxY, right: bounds.width - box.maxX
            )

            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize

            let minScale = max(box.width / imageSize.width, box.height / imageSize.height)
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = minScale * 5
            scrollView.zoomScale = minScale

            // Centre the image on the frame.
            let scaled = CGSize(width: imageSize.width * minScale, height: imageSize.height * minScale)
            scrollView.contentOffset = CGPoint(
                x: (scaled.width - box.width) / 2 - box.minX,
                y: (scaled.height - box.height) / 2 - box.minY
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        // The thirds grid shows while a finger is on it.
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { onAdjusting(true) }
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { onAdjusting(true) }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { onAdjusting(false) }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { onAdjusting(false) }
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            onAdjusting(false)
        }
    }
}

// MARK: - Crop math bridge

/// Holds a reference to the live scroll view so Done can read its visible square.
/// Main-actor: it only ever touches the scroll view from UI code.
@MainActor
final class ScrollCropper {
    weak var scrollView: UIScrollView?
    var image: UIImage?

    /// Crops the frame's current contents to JPEG, downscaled so its longer edge is at
    /// most `maxPixel` (preserving the box's aspect). Assumes `image` is scale-1 /
    /// orientation-up.
    func cropJPEG(maxPixel: CGFloat) -> Data? {
        guard let scrollView, let image, let cg = image.cgImage, scrollView.zoomScale > 0 else { return nil }
        let zoom = scrollView.zoomScale
        // The frame is the bounds minus the content inset (see setup).
        let inset = scrollView.contentInset
        let box = CGSize(
            width: scrollView.bounds.width - inset.left - inset.right,
            height: scrollView.bounds.height - inset.top - inset.bottom
        )

        var rect = CGRect(
            x: (scrollView.contentOffset.x + inset.left) / zoom,
            y: (scrollView.contentOffset.y + inset.top) / zoom,
            width: box.width / zoom,
            height: box.height / zoom
        )
        // Guard against bounce overscroll spilling past the image edges.
        rect = rect.intersection(CGRect(origin: .zero, size: image.size))
        guard !rect.isNull, rect.width > 0, rect.height > 0, let cropped = cg.cropping(to: rect) else { return nil }

        let croppedImage = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        let maxSide = max(rect.width, rect.height)
        let renderScale = maxSide > maxPixel ? maxPixel / maxSide : 1
        let renderSize = CGSize(width: rect.width * renderScale, height: rect.height * renderScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: renderSize, format: format).image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: renderSize))
        }
        return rendered.jpegData(compressionQuality: 0.9)
    }
}

// MARK: - Orientation helper

extension UIImage {
    /// Returns a copy with EXIF orientation baked into the pixels (.up) at scale 1,
    /// so CGImage pixel coordinates line up with what's displayed — required for
    /// correct cropping.
    func normalizedUp() -> UIImage {
        if imageOrientation == .up && scale == 1 { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
