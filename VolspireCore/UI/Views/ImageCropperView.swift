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
        showsCircularMask: Bool = false
    ) {
        self.image = image
        self.onCrop = onCrop
        self.onCancel = onCancel
        self.aspectRatio = aspectRatio
        self.outputSize = outputSize
        self.allowsFitMode = allowsFitMode
        self.showsCircularMask = showsCircularMask
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
                // Largest box of the target aspect ratio that fits the space.
                let boxW = min(geo.size.width, geo.size.height * aspectRatio)
                let boxH = boxW / aspectRatio
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
                        ZoomableImageScrollView(image: image, cropper: cropper)
                            .frame(width: boxW, height: boxH)
                            .overlay {
                                if showsCircularMask {
                                    // Dim everything outside the inscribed circle —
                                    // the round-avatar preview.
                                    CircleCutoutMask()
                                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                                        .allowsHitTesting(false)
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                                        .allowsHitTesting(false)
                                } else {
                                    Rectangle()
                                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height) // centre the box
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
        .preferredColorScheme(.dark)
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

/// Full-rect path with an inscribed circle removed (even-odd fill) — dims the
/// corners of an avatar crop so the round preview is obvious.
private struct CircleCutoutMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let side = min(rect.width, rect.height)
        path.addEllipse(in: CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        ))
        return path
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
        context.coordinator.setupIfNeeded(scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        private var didSetup = false

        /// Sized once the scroll view has real bounds: fit the image to fill the
        /// (possibly non-square) crop box (min zoom), cap max zoom, and centre it.
        func setupIfNeeded(_ scrollView: UIScrollView) {
            guard !didSetup, let imageView, scrollView.bounds.width > 1, scrollView.bounds.height > 1 else { return }
            let imageSize = imageView.image?.size ?? .zero
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            didSetup = true

            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize

            let box = scrollView.bounds.size
            let minScale = max(box.width / imageSize.width, box.height / imageSize.height)
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = minScale * 5
            scrollView.zoomScale = minScale

            let scaled = CGSize(width: imageSize.width * minScale, height: imageSize.height * minScale)
            scrollView.contentOffset = CGPoint(
                x: max(0, (scaled.width - box.width) / 2),
                y: max(0, (scaled.height - box.height) / 2)
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}

// MARK: - Crop math bridge

/// Holds a reference to the live scroll view so Done can read its visible square.
/// Main-actor: it only ever touches the scroll view from UI code.
@MainActor
final class ScrollCropper {
    weak var scrollView: UIScrollView?
    var image: UIImage?

    /// Crops the currently-visible box to JPEG, downscaled so its longer edge is at
    /// most `maxPixel` (preserving the box's aspect). Assumes `image` is scale-1 /
    /// orientation-up.
    func cropJPEG(maxPixel: CGFloat) -> Data? {
        guard let scrollView, let image, let cg = image.cgImage, scrollView.zoomScale > 0 else { return nil }
        let zoom = scrollView.zoomScale
        let box = scrollView.bounds.size

        var rect = CGRect(
            x: scrollView.contentOffset.x / zoom,
            y: scrollView.contentOffset.y / zoom,
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
