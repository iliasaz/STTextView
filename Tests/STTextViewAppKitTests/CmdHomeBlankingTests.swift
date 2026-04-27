#if os(macOS)
import XCTest
import AppKit
@testable import STTextViewAppKit

/// Reproduces and tracks an STTextView regression: after `moveToEndOfDocument`
/// followed by `moveToBeginningOfDocument` on a document taller than the
/// visible viewport, only the first line is laid out — `viewportRange`
/// collapses to that single line and `STContentView`'s frame shrinks to
/// ~one line height. Visible symptom in a host app: editor renders blank
/// except for line 1 after Cmd-End → Cmd-Home.
///
/// What we know (from earlier diagnosis):
/// - `textContainer.size.width` stays stable; wrap state isn't flipping.
/// - The wrapped first line stays wrapped (multiple textLineFragments).
/// - `textLayoutManager.textViewportLayoutController.viewportRange` shrinks
///   from `{0, 1316}` (initial top-of-doc viewport) to `{0, 52}` (one line).
/// - Calling `textView.layoutViewport()` *or* setting `needsLayout = true`
///   followed by another display cycle recovers the viewport to `{0, 1316}`.
/// - Naively observing the clip view's `boundsDidChangeNotification` and
///   triggering `layoutViewport()` from the observer produced an even worse
///   state: `STContentView`'s frame was resized to 16pt, indicating a
///   feedback loop with `updateContentSizeIfNeeded()`.
///
/// The root cause appears to be that NSTextViewportLayoutController's
/// `layoutViewport()` returns a small, single-line range on the first call
/// after a large scroll, and a second call is needed for it to converge —
/// but STTextView's natural layout pass after a programmatic scroll only
/// runs `layoutViewport()` once.
@MainActor
final class CmdHomeBlankingTests: XCTestCase {

    // MARK: - Currently failing — tracks the open regression.

    /// The viewport range after Cmd-End → Cmd-Home should match the initial
    /// top-of-doc viewport range (both should cover the same visible area).
    /// This currently fails: post-Home returns ~52 chars (one line) vs
    /// the ~1316 chars the visible 400pt-tall viewport should hold.
    func testViewportRangeCoversVisibleTopAfterHome() throws {
        let host = makeHost(wordWrap: true, viewportSize: CGSize(width: 600, height: 400))
        let textView = host.textView
        textView.setString(Self.longText(lineCount: 500))
        host.displayIfNeeded()
        // Force the viewport to be measured at the top of the doc, not at
        // wherever `setString` left it.
        textView.scroll(.zero)
        textView.layoutViewport()

        let initialViewportRange = try XCTUnwrap(
            textView.textLayoutManager.textViewportLayoutController.viewportRange
        )
        let initialNSRange = NSRange(initialViewportRange, in: textView.textContentManager)
        XCTAssertEqual(initialNSRange.location, 0, "initial viewport should start at the top of the document")
        XCTAssertGreaterThan(
            initialNSRange.length, 100,
            "initial viewport over a 500-line wrapped doc should cover much more than a single short line"
        )

        textView.moveToEndOfDocument(nil)
        host.displayIfNeeded()

        textView.moveToBeginningOfDocument(nil)
        host.displayIfNeeded()

        let homeViewportRange = try XCTUnwrap(
            textView.textLayoutManager.textViewportLayoutController.viewportRange
        )
        let homeNSRange = NSRange(homeViewportRange, in: textView.textContentManager)
        XCTAssertEqual(homeNSRange.location, 0, "after Cmd-Home the viewport should start at the top again")
        XCTAssertEqual(
            homeNSRange.length, initialNSRange.length, accuracy: 4,
            "after Cmd-Home the viewport span should match the initial top-of-doc viewport span"
        )
    }

    // MARK: - Currently passing — narrows the cause.

    /// Confirms the wrap state isn't flipping. `isHorizontallyResizable` and
    /// `textContainer.size.width` remain stable through Cmd-End / Cmd-Home.
    func testTextContainerWidthStableAfterEndThenHome() throws {
        let host = makeHost(wordWrap: true, viewportSize: CGSize(width: 600, height: 400))
        let textView = host.textView
        textView.setString(Self.longText(lineCount: 500))
        host.displayIfNeeded()

        let initialContainerWidth = textView.textContainer.size.width
        let initialResizable = textView.isHorizontallyResizable
        XCTAssertFalse(initialResizable)
        XCTAssertGreaterThan(initialContainerWidth, 0)
        XCTAssertLessThan(initialContainerWidth, 10_000)

        textView.moveToEndOfDocument(nil)
        host.displayIfNeeded()
        XCTAssertEqual(textView.isHorizontallyResizable, initialResizable)
        XCTAssertEqual(textView.textContainer.size.width, initialContainerWidth, accuracy: 1.0)

        textView.moveToBeginningOfDocument(nil)
        host.displayIfNeeded()
        XCTAssertEqual(textView.isHorizontallyResizable, initialResizable)
        XCTAssertEqual(textView.textContainer.size.width, initialContainerWidth, accuracy: 1.0)
    }

    /// Confirms a wrapped first line stays wrapped after Cmd-End / Cmd-Home —
    /// the layout fragment for paragraph 0 still has multiple line fragments.
    func testFirstLineStaysWrappedAfterHome() throws {
        let host = makeHost(wordWrap: true, viewportSize: CGSize(width: 600, height: 400))
        let textView = host.textView

        let longFirst = String(repeating: "lorem ipsum dolor sit amet ", count: 20)
        let restLines = (1...500).map { "line \($0)" }.joined(separator: "\n")
        textView.setString("\(longFirst)\n\(restLines)")
        host.displayIfNeeded()

        let initialFirstFragmentCount = lineFragmentCount(forFirstParagraphIn: textView)
        XCTAssertGreaterThan(initialFirstFragmentCount, 1)

        textView.moveToEndOfDocument(nil)
        host.displayIfNeeded()

        textView.moveToBeginningOfDocument(nil)
        host.displayIfNeeded()

        let postHomeFirstFragmentCount = lineFragmentCount(forFirstParagraphIn: textView)
        XCTAssertEqual(
            postHomeFirstFragmentCount, initialFirstFragmentCount,
            "first line must still wrap into the same number of fragments after Cmd-Home"
        )
    }

    // MARK: - Diagnostic — never asserts; prints state for inspection while
    //         iterating on a fix.

    func testCaptureViewportStateAroundEndThenHome() throws {
        let host = makeHost(wordWrap: true, viewportSize: CGSize(width: 600, height: 400))
        let textView = host.textView
        textView.setString(Self.longText(lineCount: 500))
        host.displayIfNeeded()
        textView.scroll(.zero)
        textView.layoutViewport()
        dump(stage: "initial top", textView: textView, host: host)

        textView.moveToEndOfDocument(nil)
        host.displayIfNeeded()
        dump(stage: "after Cmd-End", textView: textView, host: host)

        textView.moveToBeginningOfDocument(nil)
        host.displayIfNeeded()
        dump(stage: "after Cmd-Home", textView: textView, host: host)

        textView.layoutViewport()
        dump(stage: "after Cmd-Home + layoutViewport()", textView: textView, host: host)
    }

    // MARK: - Helpers

    private func dump(stage: String, textView: STTextView, host: Host) {
        let cm = textView.textContentManager
        let lm = textView.textLayoutManager
        let viewport = lm.textViewportLayoutController.viewportRange
        let viewportNS = viewport.map { NSRange($0, in: cm) } ?? NSRange(location: -1, length: -1)
        let asked = textView.viewportBounds(for: lm.textViewportLayoutController)
        let stContent = textView.subviews.first { String(describing: type(of: $0)).contains("STContentView") }

        print("[diag stage=\(stage)]")
        print("  viewportRange (NSRange)      = \(viewportNS)")
        print("  viewportBounds(for:)         = \(asked)")
        print("  STContentView.frame          = \(stContent?.frame ?? .zero)")
        print("  STContentView.visibleRect    = \(stContent?.visibleRect ?? .zero)")
        print("  scrollView.contentView.bounds = \(host.scrollView.contentView.bounds)")
        print("  textView.frame               = \(textView.frame)")
        print("  textContainer.size           = \(textView.textContainer.size)")
        print("  usageBoundsForContainer      = \(lm.usageBoundsForTextContainer)")
    }

    /// Counts line fragments in the layout fragment that owns the document's
    /// first paragraph. If the line wraps to N visual rows, returns N.
    private func lineFragmentCount(forFirstParagraphIn textView: STTextView) -> Int {
        var count = 0
        textView.textLayoutManager.enumerateTextLayoutFragments(
            from: textView.textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            count = fragment.textLineFragments.count
            return false // first fragment only
        }
        return count
    }

    private static func longText(lineCount: Int) -> String {
        (1...lineCount).map { "line \($0): the quick brown fox jumps over the lazy dog" }
            .joined(separator: "\n")
    }

    private func makeHost(wordWrap: Bool, viewportSize: CGSize) -> Host {
        let scrollView = STTextView.scrollableTextView()
        scrollView.frame = CGRect(origin: .zero, size: viewportSize)
        scrollView.hasVerticalScroller = true

        let textView = scrollView.documentView as! STTextView
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isHorizontallyResizable = !wordWrap
        textView.isVerticallyResizable = true

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewportSize),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(scrollView)
        scrollView.frame = window.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        window.layoutIfNeeded()

        return Host(window: window, scrollView: scrollView, textView: textView)
    }

    @MainActor
    private struct Host {
        let window: NSWindow
        let scrollView: NSScrollView
        let textView: STTextView

        func displayIfNeeded() {
            window.layoutIfNeeded()
            window.displayIfNeeded()
        }
    }
}
#endif
