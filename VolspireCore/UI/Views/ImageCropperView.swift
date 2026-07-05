//
//  ImageCropperView.swift
//  Volspire
//
//  Square image picker with two modes:
//   • Fit  — the whole image, aspect-fit into a 1:1 canvas, with the empty bars
//            filled by a blurred, zoomed copy of the same image (mirrors the web
//            app's blur-fill for vertical/horizontal covers). Nothing is cropped.
//   • Crop — the classic "move & scale" square cropper (a UIScrollView does the
//            zoom/pan + crop-rect math, more reliable than SwiftUI gestures).
//  The image must be orientation-normalised first — see `normalizedUp()`.
//

import CoreImage
import DesignSystem
import SwiftUI
import UIKit

struct ImageCropperView: View {
    /// Source image — pass `someImage.normalizedUp()` so pixel coords match display.
    let image: UIImage
    /// Square 1:1 JPEG data, delivered when the user taps Done.
    let onCrop: (Data) -> Void
    let onCancel: () -> Void

    /// Max side length (px) of the exported image.
    var outputSize: CGFloat = 1024

    private enum Mode: String, CaseIterable, Identifiable {
        case fit = "Fit", crop = "Crop"
        var id: Self { self }
    }

    @State private var mode: Mode = .fit
    @State private var cropper = ScrollCropper()
    /// The rendered blur-fill square — generated once so the preview is exactly
    /// what gets uploaded (WYSIWYG), and reused for Done.
    @State private var fitImage: UIImage?

    var body: some View {
        // A full-screen cover lays out edge-to-edge with no safe-area inset, so pad
        // by the window's real insets. (A GeometryReader with .ignoresSafeArea
        // reports zero insets, so that approach is a no-op — use the window here.)
        let insets = ViewConst.safeAreaInsets
        return VStack(spacing: 0) {
            header

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                Group {
                    switch mode {
                    case .fit:
                        if let fitImage {
                            Image(uiImage: fitImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: side, height: side)
                        } else {
                            Color.black.frame(width: side, height: side)
                        }
                    case .crop:
                        ZoomableImageScrollView(image: image, cropper: cropper)
                            .frame(width: side, height: side)
                            .overlay {
                                Rectangle()
                                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                                    .allowsHitTesting(false)
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height) // centre the square
            }

            modeToggle
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .padding(.top, max(insets.top, 12))
        .padding(.bottom, max(insets.bottom, 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // Render the blur-fill up front so switching to Fit is instant and the
        // preview matches the exported bytes exactly.
        .onAppear {
            if fitImage == nil {
                fitImage = SquareBlurFill.render(image, side: outputSize)
            }
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
                    LucideIcon(.x, .lg)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
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
        .padding(.top, 12)
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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08), in: Capsule())
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: mode)
    }

    private func done() {
        switch mode {
        case .fit:
            if let data = fitImage?.jpegData(compressionQuality: 0.9) { onCrop(data) }
        case .crop:
            if let data = cropper.cropJPEG(maxPixel: outputSize) { onCrop(data) }
        }
    }
}

// MARK: - Blur-fill (letterbox) renderer

/// Renders an image into a 1:1 square: a blurred, aspect-filled copy behind the
/// sharp, aspect-fit original — so vertical/horizontal images become square
/// without cropping (the web app's cover treatment).
enum SquareBlurFill {
    static func render(_ image: UIImage, side: CGFloat) -> UIImage {
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let background = blurred(image, radius: side * 0.045) ?? image

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
        /// square (min zoom), cap max zoom, and centre the initial crop.
        func setupIfNeeded(_ scrollView: UIScrollView) {
            guard !didSetup, let imageView, scrollView.bounds.width > 1 else { return }
            let imageSize = imageView.image?.size ?? .zero
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            didSetup = true

            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize

            let side = scrollView.bounds.width
            let minScale = max(side / imageSize.width, side / imageSize.height)
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = minScale * 5
            scrollView.zoomScale = minScale

            let scaled = CGSize(width: imageSize.width * minScale, height: imageSize.height * minScale)
            scrollView.contentOffset = CGPoint(
                x: max(0, (scaled.width - side) / 2),
                y: max(0, (scaled.height - side) / 2)
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

    /// Crops the currently-visible square to JPEG, downscaled so its side is at
    /// most `maxPixel`. Assumes `image` is scale-1 / orientation-up.
    func cropJPEG(maxPixel: CGFloat) -> Data? {
        guard let scrollView, let image, let cg = image.cgImage, scrollView.zoomScale > 0 else { return nil }
        let zoom = scrollView.zoomScale
        let side = scrollView.bounds.width

        var rect = CGRect(
            x: scrollView.contentOffset.x / zoom,
            y: scrollView.contentOffset.y / zoom,
            width: side / zoom,
            height: side / zoom
        )
        // Guard against bounce overscroll spilling past the image edges.
        rect = rect.intersection(CGRect(origin: .zero, size: image.size))
        guard !rect.isNull, rect.width > 0, rect.height > 0, let cropped = cg.cropping(to: rect) else { return nil }

        let croppedImage = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        let target = min(maxPixel, max(rect.width, rect.height))
        let renderSize = CGSize(width: target, height: target)
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
