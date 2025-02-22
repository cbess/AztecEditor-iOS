import Foundation
import UIKit

fileprivate let DefaultUnorderedListMarkerText = "\u{2022}"

// MARK: - Text List
//
open class TextList: ParagraphProperty {

    // MARK: - Nested Types

    /// List Styles
    ///
    public enum Style: Int {
        case ordered
        case unordered

        func markerText(forItemNumber number: Int, indentLevel: Int? = nil) -> String {
            switch self {
            case .ordered:
                if indentLevel == nil {
                    return "\(number)."
                }
                
                switch indentLevel {
                case 1:
                    return "\(number)."
                case 2:
                    let text = getLetter(for: number)
                    return "\(text)."
                default:
                    // marker for all levels > 2
                    let text = getRomanNumeral(for: number)
                    return "\(text)."
                }
            case .unordered:
                if indentLevel == nil {
                    return DefaultUnorderedListMarkerText
                }
                
                switch indentLevel {
                case 1:
                    return DefaultUnorderedListMarkerText
                case 2:
                    return "\u{2E30}"
                default:
                    // marker for all levels > 2
                    return "\u{2B29}"
                }
            }
        }
    }

    /// List Indent Styles
    ///
    public enum IndentStyle: Int {
        /// A default single bullet style for each indentation level
        case `default`
        /// The standard bullet styles for each indentation level (i.e., HTML style)
        case standard
    }

    public let reversed: Bool

    public let start: Int?

    // MARK: - Properties

    /// Kind of List: Ordered / Unordered
    ///
    let style: Style

    init(style: Style, start: Int? = nil, reversed: Bool = false, with representation: HTMLRepresentation? = nil) {
        self.style = style

        if let representation = representation, case let .element( html ) = representation.kind {
            self.reversed = html.attribute(ofType: .reversed) != nil
            
            if let startAttribute = html.attribute(ofType: .start),
                case let .string( value ) = startAttribute.value,
                let start = Int(value)
            {
                self.start = start
            } else {
                self.start = nil
            }
        } else {
            self.start = start
            self.reversed = reversed
        }
        super.init(with: representation)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        if aDecoder.containsValue(forKey: String(describing: Style.self)),
            let decodedStyle = Style(rawValue:aDecoder.decodeInteger(forKey: String(describing: Style.self))) {
            style = decodedStyle
        } else {
            style = .ordered
        }
        if aDecoder.containsValue(forKey: AttributeType.start.rawValue) {
            let decodedStart = aDecoder.decodeInteger(forKey: AttributeType.start.rawValue)
            start = decodedStart
        } else {
            start = nil
        }

        if aDecoder.containsValue(forKey: AttributeType.reversed.rawValue) {
            let decodedReversed = aDecoder.decodeBool(forKey: AttributeType.reversed.rawValue)
            reversed = decodedReversed
        } else {
            reversed = false
        }

        super.init(coder: aDecoder)
    }

    public override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(style.rawValue, forKey: String(describing: Style.self))
        aCoder.encode(start, forKey: AttributeType.start.rawValue)
        aCoder.encode(reversed, forKey: AttributeType.reversed.rawValue)
    }

    override open class var supportsSecureCoding: Bool { true }

    public static func ==(lhs: TextList, rhs: TextList) -> Bool {
        return lhs.style == rhs.style && lhs.start == rhs.start && lhs.reversed == rhs.reversed
    }
}

/// Returns the letters to use as the ordered list marker text
fileprivate func getLetter(for number: Int) -> String {
    let listChars = "abcdefghijklmnopqrstuvwxyz"
    let charCount = listChars.count
    
    // for recursion
    func convert(_ value: Int) -> String {
        if value <= charCount {
            return String(listChars[listChars.index(listChars.startIndex, offsetBy: value - 1)])
        }
        
        let quotient = (value - 1) / charCount
        let remainder = (value - 1) % charCount
        return convert(quotient) + String(listChars[listChars.index(listChars.startIndex, offsetBy: remainder)])
    }
        
    return convert(number)
}

/// Returns the roman numeral to use as the ordered list marker text
fileprivate func getRomanNumeral(for number: Int) -> String {
    let romanValues = [
        1000: "m", 900: "cm", 500: "d", 400: "cd",
        100: "c", 90: "xc", 50: "l", 40: "xl",
        10: "x", 9: "ix", 5: "v", 4: "iv", 1: "i"
    ]
        
    // used for recursion
    func convert(_ value: Int) -> String {
        guard value > 0 else {
            return ""
        }
        
        if let numeral = romanValues[value] {
            return numeral
        }
        
        for (key, numeral) in romanValues.sorted(by: { $0.key > $1.key }) {
            if value >= key {
                // recursive
                return numeral + convert(value - key)
            }
        }
        
        return ""
    }
    
    return convert(number)
}
