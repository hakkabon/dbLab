import Foundation
import Testing
import DBLabNumeric
import NumericCoreSparse

@Test func preparedACNetworkMatchesAnalyticRCTransferAcrossSweep() throws {
    let resistance = 1_000.0
    let capacitance = 1e-6
    let frequencies = [100.0, 1_000.0, 10_000.0]
    let network = ACNetwork(
        referenceNode: 0,
        sourceNode: 1,
        sourceVoltage: ACComplex(real: 1),
        elements: [
            ACTwoTerminalElement(id: "R1", firstNode: 1, secondNode: 2, impedance: .resistance(resistance)),
            ACTwoTerminalElement(id: "C1", firstNode: 2, secondNode: 0, impedance: .capacitance(capacitance)),
        ]
    )

    let points = try PreparedACNetwork(network).solve(frequenciesHz: frequencies)
    #expect(points.count == frequencies.count)
    for point in points {
        let capacitor = ACComplex(real: 0, imaginary: -1 / (2 * .pi * point.frequencyHz * capacitance))
        let expectedInput = ACComplex(real: resistance) + capacitor
        let expectedOutput = capacitor / expectedInput
        let actualOutput = try #require(point.nodeVoltages[2])
        #expect(complexDistance(actualOutput, expectedOutput) < 1e-10)
        #expect(complexDistance(point.inputImpedance, expectedInput) < 1e-7)
        #expect(point.diagnostics.backendIdentifier == "numeric-core-sparse-lu")
        #expect(point.diagnostics.relativeResidual < 1e-10)
        #expect(point.diagnostics.originalNonZeroCount > 0)
    }
}

@Test func tabulatedImpedanceInterpolatesLogMagnitudeAndUnwrappedPhase() throws {
    let model = ACImpedanceModel.tabulated([
        .init(frequencyHz: 100, impedance: .polar(magnitude: 4, phaseRadians: 170 * .pi / 180)),
        .init(frequencyHz: 10_000, impedance: .polar(magnitude: 16, phaseRadians: -170 * .pi / 180)),
    ])
    let midpoint = try model.impedance(at: 1_000)

    #expect(abs(midpoint.magnitude - 8) < 1e-10)
    #expect(abs(abs(midpoint.phaseRadians) - .pi) < 1e-10)
    #expect(throws: ACAnalysisError.self) { try model.impedance(at: 20) }
}

@Test func reusableSparseLUConformsToRustNumericCoreDirectLU() throws {
    let matrix = try SparseMatrix<Double>(
        rows: 3, cols: 3,
        entries: [
            .init(row: 0, column: 0, value: 4), .init(row: 0, column: 1, value: -1),
            .init(row: 1, column: 0, value: -1), .init(row: 1, column: 1, value: 4),
            .init(row: 1, column: 2, value: -1), .init(row: 2, column: 1, value: -1),
            .init(row: 2, column: 2, value: 3),
        ]
    )
    let rhs = [15.0, 10.0, 10.0]
    let reusable = try SparseLUFactorization(matrix: matrix).solveRefined(rhs)
    let rust = try SparseLinearSolver.solveLU(matrix: matrix, rhs: rhs)

    #expect(zip(reusable.solution, rust.solution).allSatisfy { abs($0 - $1) < 1e-11 })
    #expect(reusable.relativeResidual < 1e-12)
    #expect(rust.relativeResidual < 1e-12)
}

private func complexDistance(_ lhs: ACComplex, _ rhs: ACComplex) -> Double {
    hypot(lhs.real - rhs.real, lhs.imaginary - rhs.imaginary)
}
