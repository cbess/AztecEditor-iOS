import UIKit


/// Returns a specialised representation for a `<hr>` element.
///
class HRElementConverter: ElementConverter {

    func attachment(from representation: HTMLRepresentation, inheriting inheritedAttributes: [AttributedStringKey : Any]) -> NSTextAttachment? {
        return LineAttachment()
    }

    func specialString(for element: ElementNode) -> String {
        return .textAttachment
    }

    func extraAttributes(for representation: HTMLRepresentation) -> [AttributedStringKey : Any]? {
        return [.hrHtmlRepresentation: representation]
    }

    func supports(element: ElementNode) -> Bool {
        return element.standardName == .hr
    }
}
