//
//  UIScreen+Extensions.swift
//  Volspire
//
//

import UIKit

public extension UIScreen {
    static var deviceCornerRadius: CGFloat {
        main.value(forKey: "_displayCornerRadius") as? CGFloat ?? 0
    }

    static var hairlineWidth: CGFloat {
        1 / main.scale
    }

    static let size = UIScreen.main.bounds.size
}
