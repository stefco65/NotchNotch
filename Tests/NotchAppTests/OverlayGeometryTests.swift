import AppKit
import XCTest
@testable import NotchNook

@MainActor
final class OverlayGeometryTests: XCTestCase {
    func testCollapsedSurfaceIsAnchoredToDisplayTopCenter() {
        let display = fixture(anchorRect: CGRect(x: 400, y: 974, width: 200, height: 26))
        let frame = NotchWindowController.frame(for: .collapsed, display: display)

        XCTAssertEqual(frame.midX, display.frame.midX)
        XCTAssertEqual(frame.maxY, display.frame.maxY)
        XCTAssertEqual(frame.width, 200)
        XCTAssertEqual(frame.height, 26)
    }

    func testNativeAndSwiftUISurfacesUseTheSameRadii() {
        XCTAssertEqual(NotchWindowController.surfaceRadii(for: .collapsed).bottom, 8)
        XCTAssertEqual(NotchWindowController.surfaceRadii(for: .collapsed).shoulder, 7)
        XCTAssertEqual(NotchWindowController.surfaceRadii(for: .musicPreview).bottom, 22)
        XCTAssertEqual(NotchWindowController.surfaceRadii(for: .musicPreview).shoulder, 16)
        XCTAssertEqual(NotchWindowController.surfaceRadii(for: .expanded).bottom, 30)
        XCTAssertEqual(NotchWindowController.surfaceRadii(for: .expanded).shoulder, 18)
    }

    func testNowPlayingExtendsCollapsedFrameSymmetrically() {
        let display = fixture(anchorRect: CGRect(x: 400, y: 974, width: 200, height: 26))
        let regular = NotchWindowController.frame(for: .collapsed, display: display)
        let playing = NotchWindowController.frame(
            for: .collapsed,
            display: display,
            showsNowPlaying: true
        )

        XCTAssertEqual(playing.width, regular.width + 100)
        XCTAssertEqual(playing.midX, regular.midX)
        XCTAssertEqual(playing.minX, regular.minX - 50)
        XCTAssertEqual(playing.maxX, regular.maxX + 50)
        XCTAssertEqual(
            playing.width * NotchWindowController.surfaceHorizontalScale(
                for: .collapsed,
                showsNowPlaying: true
            ),
            regular.width + 80
        )
    }

    func testExpandedSurfaceStaysOnScreenAndTopAnchored() {
        let display = fixture(anchorRect: CGRect(x: 410, y: 988, width: 180, height: 12))
        let frame = NotchWindowController.frame(for: .expanded, display: display)

        XCTAssertEqual(frame.midX, display.frame.midX)
        XCTAssertEqual(frame.maxY, display.frame.maxY)
        XCTAssertEqual(frame.width, 760)
        XCTAssertEqual(frame.height, 204)

        let customFrame = NotchWindowController.frame(
            for: .expanded,
            display: display,
            expandedWidth: 900
        )
        XCTAssertEqual(customFrame.midX, display.frame.midX)
        XCTAssertEqual(customFrame.maxY, display.frame.maxY)
        XCTAssertEqual(customFrame.width, 900)
    }

    func testHoveredSurfaceGrowsByRequestedInsetsAndStaysTopAnchored() {
        let display = fixture(anchorRect: CGRect(x: 400, y: 974, width: 200, height: 26))
        let collapsed = NotchWindowController.frame(for: .collapsed, display: display)
        let hovered = NotchWindowController.frame(for: .hovered, display: display)

        XCTAssertEqual(hovered.midX, collapsed.midX)
        XCTAssertEqual(hovered.maxY, collapsed.maxY)
        XCTAssertEqual(hovered.width, collapsed.width + 40)
        XCTAssertEqual(hovered.height, collapsed.height + 20)
    }

    func testMusicHoverGrowsWithoutJumpingBeforeArtworkPreview() {
        let display = fixture(anchorRect: CGRect(x: 400, y: 974, width: 200, height: 26))
        let collapsed = NotchWindowController.frame(
            for: .collapsed,
            display: display,
            showsNowPlaying: true
        )
        let hovered = NotchWindowController.frame(
            for: .hovered,
            display: display,
            showsNowPlaying: true
        )
        let preview = NotchWindowController.frame(
            for: .musicPreview,
            display: display,
            showsNowPlaying: true
        )

        XCTAssertEqual(hovered.width, collapsed.width)
        XCTAssertEqual(hovered.height, collapsed.height + 20)
        XCTAssertEqual(hovered.width, preview.width)
        XCTAssertEqual(hovered.midX, collapsed.midX)
        XCTAssertEqual(hovered.maxY, collapsed.maxY)

        let collapsedArtworkX = collapsed.minX + NowPlayingLayout.artworkCenterX(
            isPreviewExpanded: false
        )
        let hoveredArtworkX = hovered.minX + NowPlayingLayout.artworkCenterX(
            isPreviewExpanded: false
        )
        let collapsedPlaybackX = collapsed.maxX - NowPlayingLayout.playbackRightInset
        let hoveredPlaybackX = hovered.maxX - NowPlayingLayout.playbackRightInset

        XCTAssertEqual(collapsedArtworkX, hoveredArtworkX)
        XCTAssertEqual(collapsedPlaybackX, hoveredPlaybackX)
        XCTAssertEqual(
            collapsed.width * NotchWindowController.surfaceHorizontalScale(
                for: .collapsed,
                showsNowPlaying: true
            ) + 20,
            hovered.width
        )
    }

    func testMusicPreviewDescendsAndExpandsFromNowPlayingSide() {
        let display = fixture(anchorRect: CGRect(x: 400, y: 974, width: 200, height: 26))
        let collapsed = NotchWindowController.frame(
            for: .collapsed,
            display: display,
            showsNowPlaying: true
        )
        let preview = NotchWindowController.frame(
            for: .musicPreview,
            display: display,
            showsNowPlaying: true
        )

        XCTAssertEqual(preview.maxY, collapsed.maxY)
        XCTAssertEqual(preview.width, 300)
        XCTAssertEqual(preview.height, 90)
        XCTAssertEqual(preview.width, collapsed.width)
        XCTAssertGreaterThan(preview.height, collapsed.height)
    }

    func testOnlyArtworkRegionTriggersMusicPreview() {
        let collapsed = CGRect(x: 350, y: 974, width: 300, height: 26)
        let artwork = NotchWindowController.musicArtworkHoverFrame(in: collapsed)

        XCTAssertEqual(artwork, CGRect(x: 350, y: 966, width: 46, height: 40))
        XCTAssertTrue(artwork.contains(CGPoint(x: 377, y: 982)))
        XCTAssertFalse(artwork.contains(CGPoint(x: 500, y: 982)))
        XCTAssertFalse(artwork.contains(CGPoint(x: 623, y: 982)))
    }

    func testMusicTickerWaitsOneSecondAndLoopsSeamlessly() {
        XCTAssertEqual(
            MarqueeMetrics.offset(
                elapsed: 0.9,
                contentWidth: 300,
                viewportWidth: 200
            ),
            0
        )
        XCTAssertEqual(
            MarqueeMetrics.offset(
                elapsed: 2,
                contentWidth: 300,
                viewportWidth: 200
            ),
            -24
        )
        XCTAssertEqual(
            MarqueeMetrics.offset(
                elapsed: 2,
                contentWidth: 120,
                viewportWidth: 240
            ),
            -24
        )
        XCTAssertEqual(
            MarqueeMetrics.loopSpacing(
                contentWidth: 120,
                viewportWidth: 240
            ),
            154
        )

        let completeCycle = MarqueeMetrics.delay
            + TimeInterval((300 + MarqueeMetrics.gap) / MarqueeMetrics.speed)
        XCTAssertEqual(
            MarqueeMetrics.offset(
                elapsed: completeCycle,
                contentWidth: 300,
                viewportWidth: 200
            ),
            0,
            accuracy: 0.001
        )
    }

    func testPlaybackControlDoesNotOpenFullNotch() {
        let panel = CGRect(x: 350, y: 910, width: 300, height: 90)
        let playbackControl = CGRect(x: 604, y: 964, width: 46, height: 36)

        XCTAssertTrue(
            NotchWindowController.shouldExpand(
                state: .musicPreview,
                panelFrame: panel,
                excludedControlFrame: playbackControl,
                pointerLocation: CGPoint(x: 480, y: 940)
            )
        )
        XCTAssertFalse(
            NotchWindowController.shouldExpand(
                state: .musicPreview,
                panelFrame: panel,
                excludedControlFrame: playbackControl,
                pointerLocation: CGPoint(x: 630, y: 980)
            )
        )
        XCTAssertFalse(
            NotchWindowController.shouldExpand(
                state: .expanded,
                panelFrame: panel,
                pointerLocation: CGPoint(x: 480, y: 940)
            )
        )
    }

    func testExpandedSurfaceClosesOnlyForOutsidePointerDown() {
        let frame = CGRect(x: 120, y: 796, width: 760, height: 204)

        XCTAssertTrue(
            NotchWindowController.shouldCollapse(
                state: .expanded,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 40, y: 400)
            )
        )
        XCTAssertFalse(
            NotchWindowController.shouldCollapse(
                state: .expanded,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 500, y: 900)
            )
        )
        XCTAssertFalse(
            NotchWindowController.shouldCollapse(
                state: .hovered,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 40, y: 400)
            )
        )
        XCTAssertFalse(
            NotchWindowController.shouldCollapse(
                state: .expanded,
                isTrayMode: true,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 40, y: 400)
            )
        )
    }

    private func fixture(anchorRect: CGRect) -> DisplayDescriptor {
        DisplayDescriptor(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 975),
            safeAreaInsets: .init(top: 26, left: 0, bottom: 0, right: 0),
            scaleFactor: 2,
            anchor: .virtualHandler(.init(rect: anchorRect))
        )
    }
}
