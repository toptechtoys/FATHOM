import Testing
@testable import FathomKit

@Test func theReferenceMachineSplitsFourEfficiencyThenEightPerformance() {
    // Mac mini M4 Pro: 12 logical CPUs, hw.perflevel0.logicalcpu = 8.
    // FATHOM-DATA-SOURCES.md records the per-core load as E1-E4, P1-P8.
    let split = CoreClusterSplit(total: 12, performance: 8)!
    #expect(split.efficiency == 4)
    #expect((0...3).allSatisfy { !split.isPerformance(index: $0) })
    #expect((4...11).allSatisfy { split.isPerformance(index: $0) })
    #expect(split.label(index: 0) == "E1")
    #expect(split.label(index: 3) == "E4")
    #expect(split.label(index: 4) == "P1")
    #expect(split.label(index: 11) == "P8")
}

@Test func theBoundaryIsTheEfficiencyCountNotThePerformanceCount() {
    // The bug this type exists to prevent. On the reference machine, using the
    // performance count as the boundary would put it at index 8 rather than 4
    // and label two thirds of the cores backwards.
    let split = CoreClusterSplit(total: 12, performance: 8)!
    #expect(split.isPerformance(index: 4))
    #expect(!split.isPerformance(index: 3))
    // If the boundary were the performance count, index 4 would read as
    // efficiency and index 8 as the first performance core.
    #expect(split.label(index: 8) != "P1")
}

@Test func anEvenSplitStillPutsEfficiencyFirst() {
    // MacBook Air M2: 8 logical CPUs, 4 performance.
    let split = CoreClusterSplit(total: 8, performance: 4)!
    #expect(split.label(index: 0) == "E1")
    #expect(split.label(index: 3) == "E4")
    #expect(split.label(index: 4) == "P1")
    #expect(split.label(index: 7) == "P4")
}

@Test func readingsThatDisagreeProduceNoSplitRatherThanAPlausibleOne() {
    // More performance cores than cores reported: the two sysctls disagree.
    // Clamping would yield a split that looks right and is not.
    #expect(CoreClusterSplit(total: 8, performance: 12) == nil)
    #expect(CoreClusterSplit(total: 0, performance: 0) == nil)
    #expect(CoreClusterSplit(total: 8, performance: -1) == nil)
}

@Test func aMachineWithNoEfficiencyCoresLabelsEveryCorePerformance() {
    let split = CoreClusterSplit(total: 4, performance: 4)!
    #expect(split.efficiency == 0)
    #expect(split.label(index: 0) == "P1")
    #expect((0...3).allSatisfy { split.isPerformance(index: $0) })
}

@Test func aMachineWithNoPerformanceCoresLabelsEveryCoreEfficiency() {
    let split = CoreClusterSplit(total: 4, performance: 0)!
    #expect(split.efficiency == 4)
    #expect(split.label(index: 3) == "E4")
    #expect((0...3).allSatisfy { !split.isPerformance(index: $0) })
}

@Test func anIndexOutsideTheReportedCoresHasNoLabel() {
    let split = CoreClusterSplit(total: 8, performance: 4)!
    #expect(split.label(index: 8) == nil)
    #expect(split.label(index: -1) == nil)
    #expect(!split.isPerformance(index: 99))
}
