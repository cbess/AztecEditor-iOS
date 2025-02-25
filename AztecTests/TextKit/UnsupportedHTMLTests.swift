import XCTest
@testable import Aztec


// MARK: - UnsupportedHTMLTests
//
class UnsupportedHTMLTests: XCTestCase {

    /// Verifies that a UnsupportedHTML Instance can get properly serialized back and forth
    ///
    func testSnippetsGetProperlyEncodedAndDecoded() throws {
        let unsupported = UnsupportedHTML(representations: [sampleRepresentation, sampleRepresentation])

        let data = try NSKeyedArchiver.archivedData(withRootObject: unsupported, requiringSecureCoding: false)
        guard let restored = try NSKeyedUnarchiver.unarchivedObject(ofClass: UnsupportedHTML.self, from: data) else {
            XCTFail()
            return
        }

        XCTAssert(restored.representations.count == 2)

        for representation in restored.representations {
            XCTAssert(representation == sampleRepresentation)
        }
    }
}


// MARK: - Helpers
//
private extension UnsupportedHTMLTests {
    var sampleCSS: CSSAttribute {
        return CSSAttribute(name: "text", value: "bold")
    }

    var sampleAttributes: [Attribute] {
        return [
            Attribute(name: "someBoolAttribute", value: .none),
            Attribute(name: "someStringAttribute", value: .string("value")),
            Attribute(type: .style, value: .inlineCss([self.sampleCSS]))
        ]
    }

    var sampleChildren: [Node] {
        return [
            TextNode(text: "Some Text"),
            CommentNode(text: "Some Comment"),
        ]
    }

    var sampleElement: ElementNode {
        return ElementNode(name: "Test", attributes: self.sampleAttributes, children: self.sampleChildren)
    }

    var sampleRepresentation: HTMLElementRepresentation {
        return HTMLElementRepresentation(self.sampleElement)
    }
}
