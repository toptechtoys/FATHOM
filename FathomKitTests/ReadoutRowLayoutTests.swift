import CoreGraphics
import Testing
@testable import FathomKit

private let minimum: CGFloat = 190
private let gap: CGFloat = 1

private func columns(_ width: CGFloat, _ count: Int) -> Int {
    ReadoutRowLayout.columnCount(
        width: width,
        itemCount: count,
        minimum: minimum,
        gap: gap
    )
}

@Test func fourReadoutsAcrossAWideColumnTakeFourColumns() {
    // auto-fill would answer 11 here and leave two thirds of the row empty.
    // This is the case that shipped wrong: 2,184pt is the content column on a
    // 16-inch display at its default scaling.
    #expect(columns(2_184, 4) == 4)
}

@Test func columnsNeverExceedTheNumberOfReadouts() {
    for count in 1...6 {
        #expect(columns(2_184, count) == count)
    }
}

@Test func aNarrowColumnFallsBackToWhatActuallyFits() {
    // 3 tracks of 190 plus 2 gaps is 572; a fourth needs 763.
    #expect(columns(600, 4) == 3)
    #expect(columns(763, 4) == 4)
    #expect(columns(762, 4) == 3)
}

@Test func oneColumnIsTheFloorHoweverNarrowItGets() {
    #expect(columns(40, 4) == 1)
    #expect(columns(0, 4) == 1)
    #expect(columns(-100, 4) == 1)
}

@Test func noReadoutsMeansNoColumns() {
    #expect(columns(2_184, 0) == 0)
}

@Test func cellsAndGapsAccountForTheWholeWidth() {
    for count in 1...6 {
        let n = columns(2_184, count)
        let cell = ReadoutRowLayout.cellWidth(width: 2_184, columns: n, gap: gap)
        let total = cell * CGFloat(n) + gap * CGFloat(n - 1)
        // The row has to reach the far edge: a cell strokes its own boundary,
        // so width left on the table is a hairline that stops short.
        #expect(abs(total - 2_184) < 0.001)
    }
}

@Test func everyReadoutLandsInExactlyOneRow() {
    let rows = ReadoutRowLayout.rows(itemCount: 7, columns: 3)
    #expect(rows.map(Array.init) == [[0, 1, 2], [3, 4, 5], [6]])
    #expect(ReadoutRowLayout.rows(itemCount: 0, columns: 3).isEmpty)
    #expect(ReadoutRowLayout.rows(itemCount: 4, columns: 0).isEmpty)
}

@Test func anUnboundedProposalDoesNotTakeTheAppDown() {
    // SwiftUI proposes an infinite width while it sizes a Layout, and
    // `Int(Double.infinity)` traps. The first draft of ReadoutRowLayout did
    // exactly that and took the app down at launch -- no window, no crash
    // report. Only running it found this, so only a test will keep it found.
    #expect(columns(.infinity, 4) == 4)
    #expect(columns(.infinity, 1) == 1)
    #expect(ReadoutRowLayout.cellWidth(width: .infinity, columns: 4, gap: gap) == 0)
}

@Test func aMinimumOfZeroDoesNotDivideByIt() {
    #expect(
        ReadoutRowLayout.columnCount(
            width: 2_184,
            itemCount: 4,
            minimum: 0,
            gap: gap
        ) == 4
    )
}
