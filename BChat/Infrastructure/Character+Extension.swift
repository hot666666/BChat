//
//  Character+Extension.swift
//  BChat
//
//  Created by hs on 9/4/25.
//

extension Character {
    /// Check if character is a hexadecimal digit
    var isHexDigit: Bool {
        return isASCII && (isWholeNumber || "abcdefABCDEF".contains(self))
    }
}
