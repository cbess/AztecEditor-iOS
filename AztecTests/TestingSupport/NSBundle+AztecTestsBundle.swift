import Foundation

extension Bundle {
    @objc public class var aztecTestsBundle: Bundle {
#if SWIFT_PACKAGE
        return .module
#else
        return Bundle(for: TextViewStub.self)
#endif
    }
}
