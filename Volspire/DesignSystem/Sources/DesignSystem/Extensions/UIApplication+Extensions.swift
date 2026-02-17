//
//  UIApplication+Extensions.swift
//  Volspire
//
//

import UIKit

extension UIApplication {
    static var keyWindow: UIWindow? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow
    }
}
