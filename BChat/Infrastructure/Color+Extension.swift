//
//  Color+Extension.swift
//  BChat
//
//  Created by hs on 9/6/25.
//

import SwiftUI

extension Color {
    static var systemBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(.background)
        #endif
    }
    
    static var separator: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator)
        #elseif canImport(AppKit)
        return Color(NSColor.separatorColor)
        #else
        return Color(.separator)
        #endif
    }
    
    static var secondarySystemBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.textBackgroundColor)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }
}
