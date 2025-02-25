import Foundation
import UIKit


/// Implemented by a class taking care of handling attachments for the storage.
///
protocol TextStorageAttachmentsDelegate: AnyObject {

    /// Provides images for attachments that are part of the storage
    ///
    /// - Parameters:
    ///     - storage: The storage that is requesting the image.
    ///     - attachment: The attachment that is requesting the image.
    ///     - url: url for the image.
    ///     - success: Callback block to be invoked with the image fetched from the url.
    ///     - failure: Callback block to be invoked when an error occurs when fetching the image.
    ///
    func storage(
        _ storage: TextStorage,
        attachment: NSTextAttachment,
        imageFor url: URL,
        onSuccess success: @escaping (UIImage) -> (),
        onFailure failure: @escaping () -> ())

    /// Provides an image placeholder for a specified attachment.
    ///
    /// - Parameters:
    ///     - storage: The storage that is requesting the image.
    ///     - attachment: The attachment that is requesting the image.
    ///
    /// - Returns: An Image placeholder to be rendered onscreen.
    ///
    func storage(_ storage: TextStorage, placeholderFor attachment: NSTextAttachment) -> UIImage
    
    /// Called when an image is about to be added to the storage as an attachment, so that the
    /// delegate can specify an URL where that image is available.
    ///
    /// - Parameters:
    ///     - storage: The storage that is requesting the image.
    ///     - imageAttachment: The image that was added to the storage.
    ///
    /// - Returns: the requested `URL` where the image is stored, or nil if it's not yet available.
    ///
    func storage(_ storage: TextStorage, urlFor imageAttachment: ImageAttachment) -> URL?

    /// Called when a attachment is removed from the storage.
    ///
    /// - Parameters:
    ///   - textView: The textView where the attachment was removed.
    ///   - attachment: The media attachment that was removed.
    ///
    func storage(_ storage: TextStorage, deletedAttachment: MediaAttachment)

    /// Provides the Bounds required to represent a given attachment, within a specified line fragment.
    ///
    /// - Parameters:
    ///     - storage: The storage that is requesting the bounds.
    ///     - attachment: NSTextAttachment about to be rendered.
    ///     - lineFragment: Line Fragment in which the glyph would be rendered.
    ///
    /// - Returns: Rect specifying the Bounds for the attachment
    ///
    func storage(_ storage: TextStorage, boundsFor attachment: NSTextAttachment, with lineFragment: CGRect) -> CGRect

    /// Provides the (Optional) Image Representation of the specified size, for a given Attachment.
    ///
    /// - Parameters:
    ///     - storage: The storage that is requesting the bounds.
    ///     - attachment: NSTextAttachment about to be rendered.
    ///     - size: Expected Image Size
    ///
    /// - Returns: (Optional) UIImage representation of the attachment.
    ///
    func storage(_ storage: TextStorage, imageFor attachment: NSTextAttachment, with size: CGSize) -> UIImage?
}


/// Custom NSTextStorage
///
open class TextStorage: NSTextStorage {
    
    // MARK: - HTML Conversion
    
    public let htmlConverter = HTMLConverter()
    
    // MARK: - PluginManager
    
    var pluginManager: PluginManager {
        get {
            return htmlConverter.pluginManager
        }
    }
    
    // MARK: - Storage

    fileprivate var textStore = NSMutableAttributedString(string: "", attributes: nil)
    fileprivate var textStoreString = ""

    // MARK: - Delegates

    /// NOTE:
    /// `attachmentsDelegate` is an optional property. On purpose. During a Drag and Drop OP, the
    /// LayoutManager may instantiate an entire TextKit stack. Since there is absolutely no entry point
    /// in which we may set this delegate, we need to set it as optional.
    ///
    /// Ref. https://github.com/wordpress-mobile/AztecEditor-iOS/issues/727
    ///
    weak var attachmentsDelegate: TextStorageAttachmentsDelegate?


    // MARK: - Calculated Properties

    override open var string: String {
        return textStoreString
    }

    open var mediaAttachments: [MediaAttachment] {
        let range = NSMakeRange(0, length)
        var attachments = [MediaAttachment]()
        enumerateAttribute(.attachment, in: range, options: []) { (object, range, stop) in
            if let attachment = object as? MediaAttachment {
                attachments.append(attachment)
            }
        }

        return attachments
    }
    
    // MARK: - Range Methods

    func range<T : NSTextAttachment>(for attachment: T) -> NSRange? {
        var range: NSRange?

        textStore.enumerateAttachmentsOfType(T.self) { (currentAttachment, currentRange, stop) in
            if attachment == currentAttachment {
                range = currentRange
                stop.pointee = true
            }
        }

        return range
    }
    
    // MARK: - NSAttributedString preprocessing

    private func preprocessAttributesForInsertion(_ attributedString: NSAttributedString, _ range: NSRange) -> NSAttributedString {
        let stringWithAttachments = preprocessAttachmentsForInsertion(attributedString)
        let stringWithHeadings = preprocessHeadingsForInsertion(stringWithAttachments)

        return stringWithHeadings
    }

    /// Preprocesses an attributed string's attachments for insertion in the storage.
    ///
    /// - Important: This method takes care of removing any non-image attachments too.  This may
    ///         change in future versions.
    ///
    /// - Parameters:
    ///     - attributedString: the string we need to preprocess.
    ///
    /// - Returns: the preprocessed string.
    ///
    fileprivate func preprocessAttachmentsForInsertion(_ attributedString: NSAttributedString) -> NSAttributedString {
        // Ref. https://github.com/wordpress-mobile/AztecEditor-iOS/issues/727:
        // If the delegate is not set, we *Explicitly* do not want to crash here.
        //
        guard let delegate = attachmentsDelegate else {
            return attributedString
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        let finalString = NSMutableAttributedString(attributedString: attributedString)
        
        attributedString.enumerateAttribute(.attachment, in: fullRange, options: []) { (object, range, stop) in
            guard let object = object else {
                return
            }

            guard let textAttachment = object as? NSTextAttachment else {
                assertionFailure("We expected a text attachment object.")
                return
            }

            switch textAttachment {
            case _ as LineAttachment:
                break
            case let attachment as MediaAttachment:
                attachment.delegate = self
            case let attachment as RenderableAttachment:
                attachment.delegate = self
            default:
                guard let image = textAttachment.image else {
                    // We only suppot image attachments for now. All other attachment types are
                    // stripped for safety.
                    //
                    finalString.removeAttribute(.attachment, range: range)
                    return
                }

                let replacementAttachment = ImageAttachment(identifier: NSUUID().uuidString)
                replacementAttachment.delegate = self
                replacementAttachment.image = image
                replacementAttachment.size = .full

                let imageURL = delegate.storage(self, urlFor: replacementAttachment)
                replacementAttachment.updateURL(imageURL)

                finalString.addAttribute(.attachment, value: replacementAttachment, range: range)
            }
        }

        return finalString
    }

    /// Preprocesses an attributed string that is missing a `headingRepresentation` attribute for insertion in the storage.
    ///
    /// - Important: This method adds the `headingRepresentation` attribute if it determines the string should contain it.
    ///  This works around a problem where autocorrected text didn't contain the attribute. This may change in future versions.
    ///
    /// - Parameters:
    ///     - attributedString: the string we need to preprocess.
    ///
    /// - Returns: the preprocessed string.
    ///
    fileprivate func preprocessHeadingsForInsertion(_ attributedString: NSAttributedString) -> NSAttributedString {
        // Ref. https://github.com/wordpress-mobile/AztecEditor-iOS/pull/1334

        guard textStore.length > 0, attributedString.length > 0 else {
            return attributedString
        }

        // Get the attributes of the start of the current string in storage.
        let currentAttrs = attributes(at: 0, effectiveRange: nil)

        guard
            // the text currently in storage has a headingRepresentation key
            let headerSize = currentAttrs[.headingRepresentation],
            // the text coming in doesn't have a headingRepresentation key
            attributedString.attribute(.headingRepresentation, at: 0, effectiveRange: nil) == nil,
            // the text coming in has a paragraph style attribute
            let paragraphStyle = attributedString.attributes(at: 0, effectiveRange: nil)[.paragraphStyle] as? ParagraphStyle,
            // the paragraph style contains a property that's a Header type
            paragraphStyle.properties.contains(where: { $0 is Header })
        else {
            // Either the heading attribute wasn't present in the existing string,
            // or the attributed string already had it.
            return attributedString
        }

        let processedString = NSMutableAttributedString(attributedString: attributedString)
        processedString.addAttribute(.headingRepresentation, value: headerSize, range: attributedString.rangeOfEntireString)

        return processedString
    }

    /// Preprocesses an attributed string that is missing a `markHtmlRepresentation` attribute for insertion in the storage.
    /// This method ensures that the `markHtmlRepresentation` attribute, if present in the current text storage,
    /// is applied to the new attributed string being inserted. This is particularly useful for maintaining
    /// mark formatting in scenarios like autocorrection or predictive text input.
    ///
    /// - Important: This method adds the `markHtmlRepresentation` attribute to the new string if it's determined
    ///   that the string should contain it, based on existing attributes in the text storage.
    ///   This helps to overcome issues where autocorrected text does not carry over the `markHtmlRepresentation` attribute.
    ///
    /// - Parameters:
    ///   - attributedString: The new string to be inserted.
    ///   - range: The range in the current text storage where the new string is to be inserted. This is used to determine
    ///     if `markHtmlRepresentation` should be applied to the new string.
    ///
    /// - Returns: The preprocessed attributed string with `markHtmlRepresentation` applied if necessary.
    ///
    fileprivate func preprocessMarkForInsertion(_ attributedString: NSAttributedString, _ range: NSRange) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)

        if range.location < textStore.length && range.length > 0 {
            let currentAttrs = textStore.attributes(at: range.location, effectiveRange: nil)

            if let markAttribute = currentAttrs[.markHtmlRepresentation] {
                mutableAttributedString.addAttribute(.markHtmlRepresentation, value: markAttribute, range: NSRange(location: 0, length: mutableAttributedString.length))
            }
        }
        return mutableAttributedString
    }

    fileprivate func detectAttachmentRemoved(in range: NSRange) {
        // Ref. https://github.com/wordpress-mobile/AztecEditor-iOS/issues/727:
        // If the delegate is not set, we *Explicitly* do not want to crash here.
        //
        guard let delegate = attachmentsDelegate else {
            return
        }

        textStore.enumerateAttachmentsOfType(MediaAttachment.self, range: range) { (attachment, range, stop) in
            delegate.storage(self, deletedAttachment: attachment)
        }
    }

    // MARK: - Overriden Methods

    /// Retrieves the attributes for the requested character location.
    ///
    /// - Important: please note that this method returns the style at the character location, and
    ///     NOT at the caret location.  For N characters we always have N+1 character locations.
    ///
    override open func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {

        guard textStore.length > 0 else {
            return [:]
        }

        return textStore.attributes(at: location, effectiveRange: range)
    }

    private func replaceTextStoreString(_ range: NSRange, with string: String) {
        let utf16String = textStoreString.utf16
        let startIndex = utf16String.index(utf16String.startIndex, offsetBy: range.location)
        let endIndex = utf16String.index(startIndex, offsetBy: range.length)
        textStoreString.replaceSubrange(startIndex..<endIndex, with: string)
    }
 
    override open func replaceCharacters(in range: NSRange, with str: String) {

        beginEditing()

        detectAttachmentRemoved(in: range)
        textStore.replaceCharacters(in: range, with: str)

        replaceTextStoreString(range, with: str)

        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        
        endEditing()
    }

    override open func replaceCharacters(in range: NSRange, with attrString: NSAttributedString) {
        let preprocessedString = preprocessAttributesForInsertion(attrString, range)

        beginEditing()

        detectAttachmentRemoved(in: range)

        // Apply mark formatting to the replacement string
        let markFormattedString = preprocessMarkForInsertion(preprocessedString, range)

        textStore.replaceCharacters(in: range, with: markFormattedString)
        replaceTextStoreString(range, with: attrString.string)

        edited([.editedAttributes, .editedCharacters], range: range, changeInLength: attrString.length - range.length)

        endEditing()
    }

    override open func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()

        // Ensure matching styles for the font and paragraph headers
        let fixedAttributes = ensureMatchingFontAndParagraphHeaderStyles(beforeApplying: attrs ?? [:], at: range)

        // Adjust attributes for 'mark' formatting logic
        let adjustedAttributes = adjustAttributesForMark(fixedAttributes, range: range)

        textStore.setAttributes(adjustedAttributes, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)

        endEditing()
    }

    // MARK: - Styles: Toggling

    @discardableResult
    func toggle(formatter: AttributeFormatter, at range: NSRange) -> NSRange {
        let applicationRange = formatter.applicationRange(for: range, in: self)
        
        guard applicationRange.length > 0 else {
            return applicationRange
        }

        return formatter.toggle(in: self, at: applicationRange)
    }

    // MARK: - Attachments

    /// Return the attachment, if any, corresponding to the id provided
    ///
    /// - Parameter id: the unique id of the attachment
    /// - Returns: the attachment object
    ///
    func attachment(withId id: String) -> MediaAttachment? {
        var foundAttachment: MediaAttachment? = nil
        enumerateAttachmentsOfType(MediaAttachment.self) { (attachment, range, stop) in
            if attachment.identifier == id {
                foundAttachment = attachment
                stop.pointee = true
            }
        }
        return foundAttachment
    }

    /// Return the range of an attachment with the specified identifier if any
    ///
    /// - Parameter attachmentID: the id of the attachment
    /// - Returns: the range of the attachment
    ///
    open func rangeFor(attachmentID: String) -> NSRange? {
        var foundRange: NSRange?
        enumerateAttachmentsOfType(MediaAttachment.self) { (attachment, range, stop) in
            if attachment.identifier == attachmentID {
                foundRange = range
                stop.pointee = true
            }
        }
        return foundRange
    }

    /// Removes all of the MediaAttachments from the storage
    ///
    open func removeMediaAttachments() {
        var ranges = [NSRange]()
        enumerateAttachmentsOfType(MediaAttachment.self) { (attachment, range, _) in
            ranges.append(range)
        }

        var delta = 0
        for range in ranges {
            let corrected = NSRange(location: range.location - delta, length: range.length)
            replaceCharacters(in: corrected, with: NSAttributedString(string: ""))
            delta += range.length
        }
    }

    private func enumerateRenderableAttachments(in text: NSAttributedString, range: NSRange? = nil, block: ((RenderableAttachment, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void)) {
        let range = range ?? NSMakeRange(0, length)
        text.enumerateAttribute(.attachment, in: range, options: []) { (object, range, stop) in
            if let object = object as? RenderableAttachment {
                block(object, range, stop)
            }
        }
    }

    // MARK: – Plain Text Interaction
    open func getPlainText(range: NSRange) -> String {
        self.attributedSubstring(from: range).string
    }

    // MARK: - HTML Interaction

    open func getHTML(prettify: Bool = false) -> String {
        return htmlConverter.html(from: self, prettify: prettify)
    }

    open func getHTML(prettify: Bool = false, range: NSRange) -> String {
        return htmlConverter.html(from: self.attributedSubstring(from: range), prettify: prettify)
    }

    open func getHTML(prettify: Bool = false, from attributedString: NSAttributedString) -> String {
        return htmlConverter.html(from: attributedString, prettify: prettify)
    }
    
    func setHTML(_ html: String, defaultAttributes: [NSAttributedString.Key: Any]) {
        let originalLength = length
        let attrString = htmlConverter.attributedString(from: html, defaultAttributes: defaultAttributes)

        textStore = NSMutableAttributedString(attributedString: attrString)
        textStoreString = textStore.string
        
        setupAttachmentDelegates()

        edited([.editedAttributes, .editedCharacters], range: NSRange(location: 0, length: originalLength), changeInLength: textStore.length - originalLength)
    }
    
    private func setupAttachmentDelegates() {
        textStore.enumerateAttachmentsOfType(MediaAttachment.self) { [weak self] (attachment, _, _) in
            attachment.delegate = self
        }
        
        enumerateRenderableAttachments(in: textStore, block: { [weak self] (attachment, _, _) in
            attachment.delegate = self
        })
                
    }
}


// MARK: - Header Font Attribute Fixes
//
private extension TextStorage {

    /// Ensures the font style is consistent with the paragraph header style that's about to be applied.
    ///
    /// - Parameters:
    ///   - attrs: NSAttributedString attributes that are about to be applied.
    ///   - range: Range that's about to be affected by the new Attributes collection.
    ///
    /// - Returns: Collection of attributes with the Font Attribute corrected, if needed.
    ///
    func ensureMatchingFontAndParagraphHeaderStyles(beforeApplying attrs: [NSAttributedString.Key: Any], at range: NSRange) -> [NSAttributedString.Key: Any] {
        let newStyle = attrs[.paragraphStyle] as? ParagraphStyle
        let oldStyle = textStore.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? ParagraphStyle

        let newLevel = newStyle?.headers.last?.level ?? .none
        let oldLevel = oldStyle?.headers.last?.level ?? .none

        guard oldLevel != newLevel && newLevel != .none else {
            return attrs
        }
        
        return fixFontAttribute(in: attrs, headerLevel: newLevel)
    }

    /// This helper re-applies the HeaderFormatter to the specified collection of attributes, so that the Font Attribute is explicitly set,
    /// and it matches the target HeaderLevel.
    ///
    /// - Parameters:
    ///   - attrs: NSAttributedString attributes that are about to be applied.
    ///   - headerLevel: HeaderLevel specified by the ParagraphStyle, associated to the application range.
    ///
    /// - Returns: Collection of attributes with the Font Attribute corrected, so that it matches the specified HeaderLevel.
    ///
    private func fixFontAttribute(in attrs: [NSAttributedString.Key: Any], headerLevel: Header.HeaderType) ->  [NSAttributedString.Key: Any] {
        let formatter = HeaderFormatter(headerLevel: headerLevel)
        return formatter.apply(to: attrs)
    }
}

// MARK: - Mark Formatting Attribute Fixes
//
private extension TextStorage {
    /// Adjusts text attributes to preserve the color of text marked with 'markHtmlRepresentation'.
    ///
    /// This method checks if the specified range of text has the 'markHtmlRepresentation' attribute.
    /// If it does, the method retains the existing color attribute to preserve the 'mark' formatting.
    ///
    /// - Parameters:
    ///   - attrs: NSAttributedString attributes that are about to be applied.
    ///   - range: Range of the text being modified.
    ///
    /// - Returns: Adjusted collection of attributes, preserving color for 'mark' formatted text.
    ///
    private func adjustAttributesForMark(_ attrs: [NSAttributedString.Key: Any], range: NSRange) -> [NSAttributedString.Key: Any] {
        var adjustedAttributes = attrs

        // Check if the range has the 'markHtmlRepresentation' attribute
        let hasMarkAttribute = attribute(.markHtmlRepresentation, at: range.location, effectiveRange: nil) != nil

        // If the 'markHtmlRepresentation' attribute is present, retain the existing color
        if hasMarkAttribute, let existingColor = textStore.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor {
            adjustedAttributes[.foregroundColor] = existingColor
        }

        return adjustedAttributes
    }
}

// MARK: - TextStorage: MediaAttachmentDelegate Methods
//
extension TextStorage: MediaAttachmentDelegate {

    func mediaAttachmentPlaceholder(for attachment: MediaAttachment) -> UIImage {
        guard let delegate = attachmentsDelegate else {
            fatalError()
        }

        return delegate.storage(self, placeholderFor: attachment)
    }

    func mediaAttachment(
        _ mediaAttachment: MediaAttachment,
        imageFor url: URL,
        onSuccess success: @escaping (UIImage) -> (),
        onFailure failure: @escaping () -> ())
    {
        guard let delegate = attachmentsDelegate else {
            fatalError()
        }

        delegate.storage(self, attachment: mediaAttachment, imageFor: url, onSuccess: success, onFailure: failure)
    }
}

// MARK: - TextStorage: RenderableAttachmentDelegate Methods
//
extension TextStorage: RenderableAttachmentDelegate {

    public func attachment(_ attachment: NSTextAttachment, imageForSize size: CGSize) -> UIImage? {
        guard let delegate = attachmentsDelegate else {
            fatalError()
        }

        return delegate.storage(self, imageFor: attachment, with: size)
    }

    public func attachment(_ attachment: NSTextAttachment, boundsForLineFragment fragment: CGRect) -> CGRect {
        guard let delegate = attachmentsDelegate else {
            fatalError()
        }

        return delegate.storage(self, boundsFor: attachment, with: fragment)
    }
}
