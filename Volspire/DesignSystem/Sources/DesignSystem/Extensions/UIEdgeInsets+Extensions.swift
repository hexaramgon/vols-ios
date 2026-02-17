//
//  UIEdgeInsets+Extensions.swift
//  Volspire
//
//

import SwiftUI

extension UIEdgeInsets {
    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}
