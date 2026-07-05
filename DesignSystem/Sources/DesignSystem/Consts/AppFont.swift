//
//  AppFont.swift
//  Volspire
//
//

import SwiftUI

public enum AppFont {
    public static let timingIndicator: Font = .geist(12, weight: .semibold)
    static let miniPlayerTitle: Font = .geist(15, weight: .medium)
    public static let button: Font = .geist(17, weight: .semibold)
    public static let mediaListHeaderSubtitle: Font = .geist(20)
    public static let mediaListItemSubtitle: Font = .geist(13)
    public static let mediaListItemFooter: Font = .geist(15)
    static let tabbar: Font = .geist(10)
}

public extension Font {
    static var appFont: AppFont.Type {
        AppFont.self
    }
}
