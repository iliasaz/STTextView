//  Created by Marcin Krzyzanowski
//  https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md


import AppKit

extension STTextView {

    override open func scroll(_ point: NSPoint) {
        contentView.scroll(point.applying(.init(translationX: -(gutterView?.frame.width ?? 0), y: 0)))
    }

    @discardableResult
    func scrollToVisible(_ textRange: NSTextRange, type: NSTextLayoutManager.SegmentType) -> Bool {
        let viewportLayoutController = textLayoutManager.textViewportLayoutController

        cmdHomeLogger.notice("scrollToVisible enter range=\(NSRange(textRange, in: self.textContentManager).debugDescription, privacy: .public) frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public) viewportRange=\(viewportLayoutController.viewportRange.map { NSRange($0, in: self.textContentManager).debugDescription } ?? "nil", privacy: .public)")

        // Ensure layout for the target range before computing its rect
        textLayoutManager.ensureLayout(for: textRange)

        // If the range is outside the current viewport, relocate the viewport anchor
        // so that TextKit2 lays out around the target location (O(1) jump)
        let isInViewport: Bool
        if let viewportRange = viewportLayoutController.viewportRange {
            if textRange.isEmpty {
                isInViewport = viewportRange.contains(textRange.location)
            } else {
                isInViewport = viewportRange.intersects(textRange)
            }
        } else {
            isInViewport = false
        }

        cmdHomeLogger.notice("scrollToVisible isInViewport=\(isInViewport, privacy: .public)")

        if !isInViewport {
            // `relocateViewport(to:)` shrinks the textView's frame to the
            // bottom of the relocation anchor's line. When relocating to the
            // top of the document (e.g. Cmd-Home from the end), that's just
            // ~one line high — and the immediately-following `layoutViewport()`
            // would otherwise run against that one-line-tall frame, producing
            // a viewport range covering only the first fragment. Restore the
            // full-document frame via `updateContentSizeIfNeeded()` first, so
            // the subsequent `layoutViewport()` runs against the correct
            // height and lays out the entire visible area.
            relocateViewport(to: textRange.location)
            cmdHomeLogger.notice("scrollToVisible after relocateViewport frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public)")
            updateContentSizeIfNeeded()
            cmdHomeLogger.notice("scrollToVisible after updateContentSize frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public)")
            layoutViewport()
            cmdHomeLogger.notice("scrollToVisible after layoutViewport viewportRange=\(viewportLayoutController.viewportRange.map { NSRange($0, in: self.textContentManager).debugDescription } ?? "nil", privacy: .public) frame=\(self.frame.debugDescription, privacy: .public)")
        } else {
            updateContentSizeIfNeeded()
        }

        guard var rect = textLayoutManager.textSegmentFrame(in: textRange, type: type) else {
            cmdHomeLogger.notice("scrollToVisible textSegmentFrame returned nil — abort")
            return false
        }

        if rect.width.isZero {
            // add padding around the point to ensure the visibility the segment
            // since the width of the segment is 0 for a selection
            rect = rect.inset(by: .init(top: 0, left: -textContainer.lineFragmentPadding, bottom: 0, right: -textContainer.lineFragmentPadding))
        }

        // scroll to visible IN clip view (ignoring gutter view overlay)
        // adjust rect to mimick it's size to include gutter overlay
        rect.origin.x -= gutterView?.frame.width ?? 0
        rect.size.width += gutterView?.frame.width ?? 0
        let result = contentView.scrollToVisible(rect)
        cmdHomeLogger.notice("scrollToVisible exit scrolled=\(result, privacy: .public) targetRect=\(rect.debugDescription, privacy: .public) frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public) viewportRange=\(viewportLayoutController.viewportRange.map { NSRange($0, in: self.textContentManager).debugDescription } ?? "nil", privacy: .public)")
        return result
    }

    override open func centerSelectionInVisibleArea(_ sender: Any?) {
        guard let selectionTextRange = textLayoutManager.textSelections.last?.textRanges.last,
              var rect = textLayoutManager.textSegmentFrame(in: selectionTextRange, type: .selection) else {
            return
        }

        if rect.width.isZero {
            // add padding around the point to ensure the visibility the segment
            // since the width of the segment is 0 for a selection
            rect = rect.inset(by: .init(top: 0, left: -textContainer.lineFragmentPadding, bottom: 0, right: -textContainer.lineFragmentPadding))
        }

        // scroll to visible IN clip view (ignoring gutter view overlay)
        // adjust rect to mimick it's size to include gutter overlay
        rect.origin.x -= gutterView?.frame.width ?? 0
        rect.size.width += gutterView?.frame.width ?? 0

        // put rect origin in the center
        contentView.scroll(rect.origin.applying(.init(translationX: 0, y: -visibleRect.height / 2)))
    }

    override open func pageUp(_ sender: Any?) {
        scrollPageUp(sender)
    }

    override open func pageUpAndModifySelection(_ sender: Any?) {
        pageUp(sender)
    }

    override open func pageDown(_ sender: Any?) {
        scrollPageDown(sender)
    }

    override open func pageDownAndModifySelection(_ sender: Any?) {
        pageDown(sender)
    }

    override open func scrollPageDown(_ sender: Any?) {
        scroll(visibleRect.moved(dy: visibleRect.height).origin)
    }

    override open func scrollPageUp(_ sender: Any?) {
        scroll(visibleRect.moved(dy: -visibleRect.height).origin)
    }

    override open func scrollToBeginningOfDocument(_ sender: Any?) {
        cmdHomeLogger.notice("scrollToBeginningOfDocument enter frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public)")
        relocateViewport(to: textLayoutManager.documentRange.location)
        cmdHomeLogger.notice("scrollToBeginningOfDocument after relocateViewport frame=\(self.frame.debugDescription, privacy: .public)")
        layoutViewport()
        cmdHomeLogger.notice("scrollToBeginningOfDocument after layoutViewport frame=\(self.frame.debugDescription, privacy: .public) viewportRange=\(self.textLayoutManager.textViewportLayoutController.viewportRange.map { NSRange($0, in: self.textContentManager).debugDescription } ?? "nil", privacy: .public)")
        scroll(CGPoint(x: visibleRect.origin.x, y: frame.minY))
        cmdHomeLogger.notice("scrollToBeginningOfDocument exit frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public)")
    }

    override open func scrollToEndOfDocument(_ sender: Any?) {
        cmdHomeLogger.notice("scrollToEndOfDocument enter frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public)")
        relocateViewport(to: textLayoutManager.documentRange.endLocation)
        layoutViewport()
        updateContentSizeIfNeeded()
        scroll(CGPoint(x: visibleRect.origin.x, y: frame.maxY))
        cmdHomeLogger.notice("scrollToEndOfDocument exit frame=\(self.frame.debugDescription, privacy: .public) visible=\(self.visibleRect.debugDescription, privacy: .public)")
    }
}
