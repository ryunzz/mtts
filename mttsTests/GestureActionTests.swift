import CoreGraphics
import Testing
@testable import mtts

struct GestureActionTests {
    @Test func tabsUseControlTabAndControlShiftTab() {
        let next = GestureAction.tabs.keystroke(for: .right)
        let previous = GestureAction.tabs.keystroke(for: .left)
        #expect(next.key == 48 && previous.key == 48)
        #expect(next.flags == .maskControl)
        #expect(previous.flags == [.maskControl, .maskShift])
    }

    @Test func desktopsAndArrowsUseArrowKeys() {
        #expect(GestureAction.desktops.keystroke(for: .right).key == 124)
        #expect(GestureAction.desktops.keystroke(for: .left).key == 123)
        #expect(GestureAction.desktops.keystroke(for: .right).flags.contains(.maskControl))
        #expect(GestureAction.arrows.keystroke(for: .left).key == 123)
        #expect(!GestureAction.arrows.keystroke(for: .left).flags.contains(.maskControl))
    }

    @Test func persistsByRawValue() {
        for action in GestureAction.allCases {
            #expect(GestureAction(rawValue: action.rawValue) == action)
        }
    }
}
