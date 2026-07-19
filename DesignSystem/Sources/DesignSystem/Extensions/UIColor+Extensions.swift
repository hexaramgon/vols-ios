//
//  UIColor+Extensions.swift
//  Volspire
//
//

import UIKit

extension UIColor {
    convenience init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }

    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}
