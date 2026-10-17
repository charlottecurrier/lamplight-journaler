import Foundation
// Stand-ins for the few iOS APIs used by App/Support, so tools/typecheck_support.sh can type-check that code on Linux.
// They mirror the real signatures. They are never compiled into the app.
final class UIImage {
    var size: CGSize { .zero }
    var scale: CGFloat { 1 }
}
final class UIImpactFeedbackGenerator {
    enum FeedbackStyle { case soft }
    init(style: FeedbackStyle) {}
    func impactOccurred() {}
}
extension RangeReplaceableCollection {
    mutating func move(fromOffsets: IndexSet, toOffset: Int) {}
}
final class NSFileCoordinator {
    struct ReadingOptions: OptionSet { let rawValue: Int; init(rawValue: Int) { self.rawValue = rawValue } }
    struct WritingOptions: OptionSet { let rawValue: Int; init(rawValue: Int) { self.rawValue = rawValue }
        static let forReplacing = WritingOptions(rawValue: 1)
        static let forMoving = WritingOptions(rawValue: 2)
        static let forDeleting = WritingOptions(rawValue: 4) }
    init(filePresenter: AnyObject?) {}
    func coordinate(readingItemAt url: URL, options: ReadingOptions = [], error outError: UnsafeMutablePointer<NSError?>?, byAccessor reader: (URL) -> Void) { reader(url) }
    func coordinate(writingItemAt url: URL, options: WritingOptions = [], error outError: UnsafeMutablePointer<NSError?>?, byAccessor writer: (URL) -> Void) { writer(url) }
    func coordinate(writingItemAt url1: URL, options options1: WritingOptions = [], writingItemAt url2: URL, options options2: WritingOptions = [], error outError: UnsafeMutablePointer<NSError?>?, byAccessor writer: (URL, URL) -> Void) { writer(url1, url2) }
}
final class NSFileVersion {
    var url: URL { URL(fileURLWithPath: "/") }
    var modificationDate: Date? { nil }
    var isResolved: Bool = false
    class func unresolvedConflictVersionsOfItem(at url: URL) -> [NSFileVersion]? { nil }
    class func removeOtherVersionsOfItem(at url: URL) throws {}
}
extension FileManager {
    func startDownloadingUbiquitousItem(at url: URL) throws {}
}
enum ImageTools {
    struct Prepared { let data: Data; let width: Int; let height: Int }
    static func prepareForStorage(_ data: Data, maxPixel: Int = 2400, quality: CGFloat = 0.85) -> Prepared? { nil }
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? { nil }
}
enum ScenePhase { case active, inactive, background }
final class UIResponder { func resignFirstResponder() -> Bool { true } }
final class UIEvent {}
final class UIApplication { static let shared = UIApplication(); @discardableResult func sendAction(_ action: String, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool { true } }
enum LAPolicy { case deviceOwnerAuthentication }
enum LABiometryType { case none, touchID, faceID, opticID }
struct LAError: Error { enum Code { case userCancel, appCancel, systemCancel, other }; var code: Code }
final class LAContext {
    var biometryType: LABiometryType { .none }
    func canEvaluatePolicy(_ policy: LAPolicy, error: UnsafeMutablePointer<NSError?>?) -> Bool { true }
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool { true }
}
extension URL {
    struct BookmarkCreationOptions: OptionSet { let rawValue: Int; init(rawValue: Int) { self.rawValue = rawValue } }
    struct BookmarkResolutionOptions: OptionSet { let rawValue: Int; init(rawValue: Int) { self.rawValue = rawValue } }
    func startAccessingSecurityScopedResource() -> Bool { true }
    func stopAccessingSecurityScopedResource() {}
    func bookmarkData(options: BookmarkCreationOptions = [], includingResourceValuesForKeys keys: Set<URLResourceKey>? = nil, relativeTo relativeURL: URL? = nil) throws -> Data { Data() }
    init(resolvingBookmarkData data: Data, options: BookmarkResolutionOptions = [], relativeTo url: URL? = nil, bookmarkDataIsStale: inout Bool) throws { self = URL(fileURLWithPath: "/") }
}
