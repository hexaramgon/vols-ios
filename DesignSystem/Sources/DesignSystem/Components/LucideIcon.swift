//
//  LucideIcon.swift
//  DesignSystem
//
//  Renders a Lucide icon (matching the web app) from the bundled SVG assets.
//  Tint with `.foregroundStyle`; `size` is the square point size, analogous to
//  an SF Symbol's point size.
//

import SwiftUI

public struct LucideIcon: View {
    public enum Name: String, Sendable {
        case globe = "lucide-globe"
        case chevronLeft = "lucide-chevron-left"
        case chevronRight = "lucide-chevron-right"
        case layoutGrid = "lucide-layout-grid"
        case plus = "lucide-plus"
        case refreshCw = "lucide-refresh-cw"
        case x = "lucide-x"
        case circlePlus = "lucide-circle-plus"
        case play = "lucide-play"
        case user = "lucide-user"
        case ellipsis = "lucide-ellipsis"
        case circleX = "lucide-circle-x"
        case volume2 = "lucide-volume-2"
        case volume1 = "lucide-volume-1"
        case listVideo = "lucide-list-video"
        case circleUser = "lucide-circle-user"
        case circleHelp = "lucide-circle-help"
        case chartLine = "lucide-chart-line"
        case search = "lucide-search"
        case camera = "lucide-camera"
        case slidersHorizontal = "lucide-sliders-horizontal"
        case tag = "lucide-tag"
        case squarePen = "lucide-square-pen"
        case share2 = "lucide-share-2"
        case shuffle = "lucide-shuffle"
        case skipBack = "lucide-skip-back"
        case skipForward = "lucide-skip-forward"
        case logOut = "lucide-log-out"
        case images = "lucide-images"
        case phone = "lucide-phone"
        case music = "lucide-music"
        case circleMinus = "lucide-circle-minus"
        case mapPin = "lucide-map-pin"
        case house = "lucide-house"
        case heart = "lucide-heart"
        case heartFill = "lucide-heart-fill"
        case bookmarkFill = "lucide-bookmark-fill"
        case settings = "lucide-settings"
        case folder = "lucide-folder"
        case folderPlus = "lucide-folder-plus"
        case triangleAlert = "lucide-triangle-alert"
        case messageCircle = "lucide-message-circle"
        case bookmark = "lucide-bookmark"
        case bell = "lucide-bell"
        case inbox = "lucide-inbox"
        case radio = "lucide-radio"
        case airplay = "lucide-airplay"
        case file = "lucide-file"
        case trash2 = "lucide-trash-2"
        case list = "lucide-list"
        case `repeat` = "lucide-repeat"
        case check = "lucide-check"
        case circleCheck = "lucide-circle-check"
        case arrowUpRight = "lucide-arrow-up-right"
        case pause = "lucide-pause"
        case playFill = "lucide-play-fill"
        case pauseFill = "lucide-pause-fill"
        case square = "lucide-square"
        case download = "lucide-download"
        case shoppingCart = "lucide-shopping-cart"
        case library = "lucide-library"
        case listMusic = "lucide-list-music"
        case upload = "lucide-upload"
        case chevronDown = "lucide-chevron-down"
        case zap = "lucide-zap"
        case userCheck = "lucide-user-check"
        case users = "lucide-users"
        case handshake = "lucide-handshake"
        case flame = "lucide-flame"
        case sparkles = "lucide-sparkles"
        case clock = "lucide-clock"
        case fileAudio = "lucide-file-audio"
        case video = "lucide-video"
        case image = "lucide-image"
        case lock = "lucide-lock"
        case eyeOff = "lucide-eye-off"
        case micVocal = "lucide-mic-vocal"
        case drum = "lucide-drum"
        case guitar = "lucide-guitar"
        case penTool = "lucide-pen-tool"
        case star = "lucide-star"
        case briefcase = "lucide-briefcase"
        case cpu = "lucide-cpu"
        case layers = "lucide-layers"
        case package = "lucide-package"
        case eye = "lucide-eye"
        case mail = "lucide-mail"
        case copy = "lucide-copy"
        case reply = "lucide-reply"
        case flag = "lucide-flag"
        case ban = "lucide-ban"
    }

    private let name: Name
    @ScaledMetric private var scaledSize: CGFloat

    /// - Parameters:
    ///   - name: the Lucide icon to render.
    ///   - size: base square point size (analogous to an SF Symbol's point size).
    ///   - textStyle: the Dynamic Type text style `size` scales relative to.
    ///     Defaults to `.body`; pass the style of adjacent text for tighter alignment.
    public init(_ name: Name, size: CGFloat = 20, relativeTo textStyle: Font.TextStyle = .body) {
        self.name = name
        self._scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    /// Token-based initializer — prefer this over a raw point size so icons stay
    /// on the shared `IconSize` scale. `LucideIcon(.bookmark, .md)`.
    public init(_ name: Name, _ size: IconSize, relativeTo textStyle: Font.TextStyle = .body) {
        self.init(name, size: size.rawValue, relativeTo: textStyle)
    }

    public var body: some View {
        Image(name.rawValue, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: scaledSize, height: scaledSize)
    }
}

/// Canonical icon-size scale — collapses the app's many ad-hoc point sizes into
/// one consistent set. Use `LucideIcon(.bookmark, .md)` at call sites.
public enum IconSize: CGFloat {
    case xs = 12    // inline with caption/footnote text (meta rows, tiny chips)
    case sm = 14    // standard list-row / inline icons
    case md = 16    // buttons, section headers, secondary actions
    case lg = 20    // nav-bar / toolbar actions, row "…" menus
    case xl = 24    // prominent actions
    case xxl = 28   // player transport-adjacent
    case hero = 40  // empty-state glyphs
}

public extension Image {
    /// A Lucide icon as a raw `Image`, for contexts that require `Image` rather
    /// than a view (tab items, resizable artwork placeholders, `Label`). The
    /// asset is template-rendered, so tint it with `.foregroundStyle`.
    init(lucide name: LucideIcon.Name) {
        self.init(name.rawValue, bundle: .module)
    }
}
