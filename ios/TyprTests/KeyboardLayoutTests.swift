import CoreGraphics
import XCTest
@testable import Typr

final class KeyboardLayoutTests: XCTestCase {
    private let portraitWidths: [CGFloat] = [320, 375, 393, 402, 430, 440]
    private let layers: [KeyboardLayer] = [.letters, .numbers, .symbols]
    private let fields: [KeyboardFieldKind] = [.text, .url, .email]

    private func everyPortraitLayout(showsStrip: Bool = true) -> [KeyboardLayout] {
        var layouts: [KeyboardLayout] = []
        for width in portraitWidths {
            for layer in layers {
                for field in fields {
                    for globe in [false, true] {
                        layouts.append(KeyboardLayout(
                            width: width, layer: layer, field: field, showsGlobe: globe, showsStrip: showsStrip
                        ))
                    }
                }
            }
        }
        return layouts
    }

    /// Every layout, with and without the suggestion bar.
    private func everyLayout() -> [KeyboardLayout] {
        everyPortraitLayout() + everyPortraitLayout(showsStrip: false) + landscapeLayouts()
            + landscapeLayouts().map {
                KeyboardLayout(
                    width: $0.width, orientation: .landscape, layer: $0.layer, field: $0.field,
                    horizontalInset: $0.horizontalInset, showsStrip: false
                )
            }
    }

    func testPortraitIs253PointsAndLandscapeIs176Points() {
        for width in portraitWidths {
            XCTAssertEqual(KeyboardLayout(width: width).totalHeight, 253, "width \(width)")
        }
        XCTAssertEqual(KeyboardLayout.height(for: .portrait), 253)
        XCTAssertEqual(KeyboardLayout.height(for: .landscape), 176)
    }

    /// Typr: without the suggestion bar the keys move up to a small top margin.
    func testWithoutTheBarTheKeyboardIsShorterAndKeysMoveUp() {
        for width in portraitWidths {
            let layout = KeyboardLayout(width: width, showsStrip: false)
            XCTAssertEqual(layout.totalHeight, 224, "width \(width)")
            XCTAssertEqual(layout.key(.character("q"))!.frame.minY, 6, accuracy: 0.001)
            XCTAssertEqual(layout.stripFrame.height, 0)
            XCTAssertEqual(layout.key(.character("q"))!.hitFrame.minY, 0, "the top margin still types")
        }
        XCTAssertEqual(KeyboardLayout.height(for: .portrait, showsStrip: false), 224)
        XCTAssertEqual(KeyboardLayout.height(for: .landscape, showsStrip: false), 141)
        // Same keys, same sizes.
        let with = KeyboardLayout(width: 393)
        let without = KeyboardLayout(width: 393, showsStrip: false)
        XCTAssertEqual(with.keys.map(\.frame.size), without.keys.map(\.frame.size))
        XCTAssertEqual(with.keys.map(\.frame.minX), without.keys.map(\.frame.minX))
    }

    func testTopRowBalloonsWidenTheKeyInPlaceWithoutTheBar() {
        for layout in everyPortraitLayout(showsStrip: false) {
            let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.totalHeight)
            for key in layout.keys where key.character != nil {
                let balloon = layout.balloon(for: key)!
                XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(balloon.bounds), describe(layout))
                XCTAssertEqual(balloon.isInline, key.row == 0, "\(describe(layout)) \(key.label)")
                if balloon.isInline {
                    XCTAssertEqual(balloon.bubble.maxY, key.frame.maxY, accuracy: 0.001)
                    XCTAssertLessThan(balloon.bubble.minY, key.frame.minY)
                }
            }
        }
        // With the bar every balloon floats above its key, as before.
        for layout in everyPortraitLayout() {
            for key in layout.keys where key.character != nil {
                XCTAssertFalse(layout.balloon(for: key)!.isInline, "\(describe(layout)) \(key.label)")
            }
        }
    }

    func testPortraitMetricsMatchAppleIOS26() {
        let proMax = KeyboardLayout(width: 440)
        XCTAssertEqual(proMax.letterWidth, (440 - 13 - 54) / 10, accuracy: 0.001)
        let q = proMax.key(.character("q"))!
        XCTAssertEqual(q.frame.minX, 6.5, accuracy: 0.001)
        XCTAssertEqual(q.frame.minY, 35, accuracy: 0.001)
        XCTAssertEqual(q.frame.height, 45)
        let shift = proMax.key(.shift)!
        XCTAssertEqual(shift.frame.width, proMax.letterWidth * 1.34, accuracy: 0.001)
    }

    func testHitTargetsTileTheKeyAreaWithNoDeadZonesOrOverlaps() {
        var generator = SystemRandomNumberGenerator()
        for layout in everyLayout() {
            let area = layout.keysAreaFrame
            var rowTop = area.minY
            for row in 0..<4 {
                let targets = layout.keys.filter { $0.row == row }.map(\.hitFrame).sorted { $0.minX < $1.minX }
                XCTAssertEqual(targets.first?.minX, 0, describe(layout))
                XCTAssertEqual(targets.last?.maxX, layout.width, describe(layout))
                for target in targets {
                    XCTAssertEqual(target.minY, rowTop, accuracy: 0.0001, "\(describe(layout)) row \(row)")
                }
                for (a, b) in zip(targets, targets.dropFirst()) {
                    XCTAssertEqual(a.maxX, b.minX, accuracy: 0.0001, "\(describe(layout)) row \(row)")
                }
                rowTop = targets[0].maxY
            }
            XCTAssertEqual(rowTop, area.maxY, accuracy: 0.0001, describe(layout))

            for _ in 0..<400 {
                let point = CGPoint(
                    x: CGFloat.random(in: 0..<layout.width, using: &generator),
                    y: CGFloat.random(in: area.minY..<area.maxY, using: &generator)
                )
                let hits = layout.keys.filter { $0.hitFrame.contains(point) }
                XCTAssertEqual(hits.count, 1, "\(describe(layout)) at \(point): \(hits.map(\.label))")
            }
            if layout.showsStrip {
                XCTAssertNil(layout.hitTest(CGPoint(x: 20, y: layout.stripFrame.midY)), "strip is not a key")
            } else {
                XCTAssertEqual(area.minY, 0, "without the bar the keys reach the top edge")
            }
        }
    }

    func testKeycapsSitInsideTheirTargetsAndNeverOverlap() {
        for layout in everyLayout() {
            let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.totalHeight)
            for key in layout.keys {
                XCTAssertTrue(key.hitFrame.contains(key.frame), "\(describe(layout)) \(key.label)")
                XCTAssertTrue(bounds.contains(key.frame), "\(describe(layout)) \(key.label)")
                XCTAssertGreaterThan(key.frame.width, 20, "\(describe(layout)) \(key.label)")
            }
            for (i, a) in layout.keys.enumerated() {
                for b in layout.keys[(i + 1)...] {
                    XCTAssertFalse(a.frame.intersects(b.frame), "\(describe(layout)) \(a.label) × \(b.label)")
                }
            }
        }
    }

    func testBalloonsStayInsideThe253PointKeyboard() {
        for layout in everyPortraitLayout() {
            let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.totalHeight)
            for key in layout.keys where key.character != nil {
                guard let balloon = layout.balloon(for: key) else {
                    return XCTFail("\(describe(layout)) \(key.label) has no balloon")
                }
                XCTAssertTrue(
                    bounds.insetBy(dx: -0.001, dy: -0.001).contains(balloon.bounds),
                    "\(describe(layout)) \(key.label): \(balloon.bubble)"
                )
                XCTAssertGreaterThanOrEqual(balloon.bubble.width, key.frame.width)
            }
        }
    }

    func testAccentMenusClampInwardAcrossEveryWidth() {
        for width in portraitWidths {
            let layout = KeyboardLayout(width: width)
            let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.totalHeight)
            for ch in ["e", "a", "i", "o", "u", "n", "c", "s", "z"] {
                let key = layout.key(.character(ch))!
                let options = AccentCatalog.options(for: ch, uppercase: false)!
                let menu = AccentMenu.build(for: key.frame, rawOptions: options, in: layout.width)
                XCTAssertTrue(
                    bounds.insetBy(dx: -0.01, dy: -0.01).contains(menu.bubbleFrame),
                    "width \(width) key \(ch): \(menu.bubbleFrame)"
                )
                XCTAssertEqual(menu.selectedOption, ch)
            }
        }
    }

    func testEdgeBalloonsArePushedInward() {
        let layout = KeyboardLayout(width: 375)
        let q = layout.balloon(for: layout.key(.character("q"))!)!
        let p = layout.balloon(for: layout.key(.character("p"))!)!
        let g = layout.balloon(for: layout.key(.character("g"))!)!
        XCTAssertGreaterThan(q.offsetX, 0)
        XCTAssertLessThan(p.offsetX, 0)
        XCTAssertEqual(g.offsetX, 0, accuracy: 0.001)
        XCTAssertEqual(q.bubble.minY, 0, accuracy: 0.001)
    }

    func testNoBalloonsForModifiersOrInLandscape() {
        let portrait = KeyboardLayout(width: 393)
        XCTAssertNil(portrait.balloon(for: portrait.key(.space)!))
        XCTAssertNil(portrait.balloon(for: portrait.key(.shift)!))
        let landscape = KeyboardLayout(width: 852, orientation: .landscape)
        XCTAssertNil(landscape.balloon(for: landscape.key(.character("a"))!))
    }

    func testBottomRowMatchesIOS26EmailAndURLRightOfSpace() {
        XCTAssertEqual(bottomRow(KeyboardLayout(width: 393)), [.layerSwitch(.numbers), .space, .typr, .returnKey])
        XCTAssertEqual(
            bottomRow(KeyboardLayout(width: 375, showsGlobe: true)),
            [.layerSwitch(.numbers), .globe, .space, .typr, .returnKey]
        )
        XCTAssertEqual(
            bottomRow(KeyboardLayout(width: 393, layer: .numbers, field: .email)),
            [.layerSwitch(.letters), .space, .character("@"), .character("."), .typr, .returnKey]
        )
        XCTAssertEqual(
            bottomRow(KeyboardLayout(width: 393, field: .url)),
            [.layerSwitch(.numbers), .space, .character("."), .character("/"), .typr, .returnKey]
        )
    }

    func testRowThreeModifiersFollowTheLayer() {
        XCTAssertNotNil(KeyboardLayout(width: 393).key(.shift))
        XCTAssertEqual(KeyboardLayout(width: 393, layer: .numbers).key(.layerSwitch(.symbols))?.row, 2)
        XCTAssertEqual(KeyboardLayout(width: 393, layer: .symbols).key(.layerSwitch(.numbers))?.row, 2)
        let numbers = KeyboardLayout(width: 393, layer: .numbers)
        XCTAssertEqual(numbers.keys.filter { $0.row == 2 }.compactMap(\.character), [".", ",", "?", "!", "'"])
    }

    func testRowTwoIsCentred() {
        let layout = KeyboardLayout(width: 402)
        let a = layout.key(.character("a"))!.frame
        let l = layout.key(.character("l"))!.frame
        XCTAssertEqual(a.minX, layout.width - l.maxX, accuracy: 0.001)
        XCTAssertEqual(layout.key(.character("a"))!.hitFrame.minX, 0)
        XCTAssertEqual(layout.key(.character("l"))!.hitFrame.maxX, layout.width)
    }

    func testLandscapeKeepsInsetsAndHeight() {
        let layout = KeyboardLayout(width: 932, orientation: .landscape, horizontalInset: 60)
        XCTAssertEqual(layout.totalHeight, 176)
        XCTAssertEqual(layout.key(.character("q"))!.frame.minX, 64, accuracy: 0.001)
        XCTAssertEqual(layout.key(.character("q"))!.hitFrame.minX, 0)
    }

    // MARK: - Helpers

    private func landscapeLayouts() -> [KeyboardLayout] {
        [
            KeyboardLayout(width: 667, orientation: .landscape),
            KeyboardLayout(width: 852, orientation: .landscape, layer: .numbers),
            KeyboardLayout(width: 956, orientation: .landscape, field: .email, horizontalInset: 60),
        ]
    }

    private func bottomRow(_ layout: KeyboardLayout) -> [KeyKind] {
        layout.keys.filter { $0.row == 3 }.sorted { $0.frame.minX < $1.frame.minX }.map(\.kind)
    }

    private func describe(_ layout: KeyboardLayout) -> String {
        "\(layout.width)pt \(layout.orientation) \(layout.layer) \(layout.field) globe=\(layout.showsGlobe) strip=\(layout.showsStrip)"
    }
}

@MainActor
final class FullKeyboardSettingsTests: XCTestCase {
    func testFullKeyboardIsOffAndAutocorrectOnByDefault() throws {
        let suite = "FullKeyboardSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = FullKeyboardSettings(defaults: defaults)

        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.autocorrect)

        settings.applyLaunchArguments(["Typr"])
        XCTAssertFalse(settings.isEnabled)
        settings.applyLaunchArguments(["Typr", FullKeyboardSettings.launchArgument])
        XCTAssertTrue(settings.isEnabled)

        settings.autocorrect = false
        XCTAssertFalse(FullKeyboardSettings(defaults: defaults).autocorrect)
    }

    func testNoAppGroupReadsAsOff() {
        XCTAssertFalse(FullKeyboardSettings(defaults: nil).isEnabled)
    }
}
