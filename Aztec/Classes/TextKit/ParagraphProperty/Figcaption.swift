import Foundation
import UIKit

class Figcaption: ParagraphProperty {
    let defaultFont: UIFont
    
    public init(defaultFont: UIFont, storing representation: HTMLRepresentation? = nil) {
        self.defaultFont = defaultFont
        super.init(with: representation)
    }
    
    required public init?(coder aDecoder: NSCoder){
        defaultFont = aDecoder.decodeObject(of: UIFont.self, forKey: CodingKeys.defaultFont)!
        super.init(coder: aDecoder)
    }
    
    public override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(defaultFont, forKey: CodingKeys.defaultFont)
    }

    override open class var supportsSecureCoding: Bool { true }
}

private extension Figcaption {
    struct CodingKeys {
        static let defaultFont = "defaultFont"
    }
}
