import Foundation
import NumericCore
import NumericCoreSparse

/// A deliberately small complex scalar at dbLab's NumericCore boundary.
/// NumericCore remains responsible for factorization; this type only models AC quantities.
public struct ACComplex: Sendable, Hashable, Codable {
    public var real: Double
    public var imaginary: Double

    public init(real: Double, imaginary: Double = 0) {
        self.real = real
        self.imaginary = imaginary
    }

    public var magnitude: Double { hypot(real, imaginary) }
    public var phaseRadians: Double { atan2(imaginary, real) }
    public var isFinite: Bool { real.isFinite && imaginary.isFinite }

    public static func polar(magnitude: Double, phaseRadians: Double) -> Self {
        Self(real: magnitude * cos(phaseRadians), imaginary: magnitude * sin(phaseRadians))
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(real: lhs.real + rhs.real, imaginary: lhs.imaginary + rhs.imaginary)
    }
    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(real: lhs.real - rhs.real, imaginary: lhs.imaginary - rhs.imaginary)
    }
    public static prefix func - (value: Self) -> Self {
        Self(real: -value.real, imaginary: -value.imaginary)
    }
    public static func * (lhs: Self, rhs: Self) -> Self {
        Self(
            real: lhs.real * rhs.real - lhs.imaginary * rhs.imaginary,
            imaginary: lhs.real * rhs.imaginary + lhs.imaginary * rhs.real
        )
    }
    public static func * (lhs: Self, rhs: Double) -> Self {
        Self(real: lhs.real * rhs, imaginary: lhs.imaginary * rhs)
    }
    public static func / (lhs: Self, rhs: Self) -> Self {
        let denominator = rhs.real * rhs.real + rhs.imaginary * rhs.imaginary
        return Self(
            real: (lhs.real * rhs.real + lhs.imaginary * rhs.imaginary) / denominator,
            imaginary: (lhs.imaginary * rhs.real - lhs.real * rhs.imaginary) / denominator
        )
    }
}

public struct ACImpedanceSample: Sendable, Hashable, Codable {
    public let frequencyHz: Double
    public let impedance: ACComplex

    public init(frequencyHz: Double, impedance: ACComplex) {
        self.frequencyHz = frequencyHz
        self.impedance = impedance
    }
}

public enum ACImpedanceModel: Sendable, Hashable, Codable {
    case resistance(Double)
    case capacitance(Double)
    case inductance(henries: Double, seriesResistance: Double)
    case tabulated([ACImpedanceSample])

    public func impedance(at frequencyHz: Double) throws -> ACComplex {
        guard frequencyHz.isFinite, frequencyHz > 0 else { throw ACAnalysisError.invalidFrequency(frequencyHz) }
        let value: ACComplex
        switch self {
        case .resistance(let ohms):
            value = ACComplex(real: ohms)
        case .capacitance(let farads):
            value = ACComplex(real: 0, imaginary: -1 / (2 * .pi * frequencyHz * farads))
        case .inductance(let henries, let seriesResistance):
            value = ACComplex(real: seriesResistance, imaginary: 2 * .pi * frequencyHz * henries)
        case .tabulated(let samples):
            value = try Self.interpolate(samples: samples, frequencyHz: frequencyHz)
        }
        guard value.isFinite, value.magnitude > 0 else { throw ACAnalysisError.invalidImpedance(frequencyHz) }
        return value
    }

    private static func interpolate(samples: [ACImpedanceSample], frequencyHz: Double) throws -> ACComplex {
        guard samples.count >= 2,
              samples.allSatisfy({ $0.frequencyHz.isFinite && $0.frequencyHz > 0 && $0.impedance.isFinite && $0.impedance.magnitude > 0 }),
              zip(samples, samples.dropFirst()).allSatisfy({ $0.frequencyHz < $1.frequencyHz }),
              let first = samples.first, let last = samples.last,
              frequencyHz >= first.frequencyHz, frequencyHz <= last.frequencyHz else {
            throw ACAnalysisError.frequencyOutsideImpedanceTable(frequencyHz)
        }
        if frequencyHz == first.frequencyHz { return first.impedance }
        if frequencyHz == last.frequencyHz { return last.impedance }
        guard let upper = samples.firstIndex(where: { $0.frequencyHz >= frequencyHz }), upper > 0 else {
            throw ACAnalysisError.frequencyOutsideImpedanceTable(frequencyHz)
        }
        let lowerSample = samples[upper - 1]
        let upperSample = samples[upper]
        let fraction = log(frequencyHz / lowerSample.frequencyHz) / log(upperSample.frequencyHz / lowerSample.frequencyHz)
        let magnitude = exp(log(lowerSample.impedance.magnitude) + fraction * log(upperSample.impedance.magnitude / lowerSample.impedance.magnitude))
        var phaseDelta = upperSample.impedance.phaseRadians - lowerSample.impedance.phaseRadians
        while phaseDelta > .pi { phaseDelta -= 2 * .pi }
        while phaseDelta < -.pi { phaseDelta += 2 * .pi }
        return .polar(magnitude: magnitude, phaseRadians: lowerSample.impedance.phaseRadians + fraction * phaseDelta)
    }
}

public struct ACTwoTerminalElement: Sendable, Hashable, Codable {
    public let id: String
    public let firstNode: Int
    public let secondNode: Int
    public let impedance: ACImpedanceModel

    public init(id: String, firstNode: Int, secondNode: Int, impedance: ACImpedanceModel) {
        self.id = id
        self.firstNode = firstNode
        self.secondNode = secondNode
        self.impedance = impedance
    }
}

public struct ACNetwork: Sendable, Hashable, Codable {
    public let referenceNode: Int
    public let sourceNode: Int
    public let sourceVoltage: ACComplex
    public let elements: [ACTwoTerminalElement]

    public init(referenceNode: Int, sourceNode: Int, sourceVoltage: ACComplex, elements: [ACTwoTerminalElement]) {
        self.referenceNode = referenceNode
        self.sourceNode = sourceNode
        self.sourceVoltage = sourceVoltage
        self.elements = elements
    }
}

public struct ACSolverDiagnostics: Sendable, Hashable {
    public let backendIdentifier: String
    public let residualNorm: Double
    public let relativeResidual: Double
    public let backwardError: Double
    public let refinementSteps: Int
    public let originalNonZeroCount: Int
    public let factorNonZeroCount: Int
    public let fillRatio: Double
    public let minimumAbsolutePivot: Double
    public let pivotGrowth: Double
}

public struct ACSolutionPoint: Sendable, Hashable {
    public let frequencyHz: Double
    public let nodeVoltages: [Int: ACComplex]
    public let elementCurrents: [String: ACComplex]
    public let inputImpedance: ACComplex
    public let diagnostics: ACSolverDiagnostics
}

public enum ACAnalysisError: Error, LocalizedError, Equatable {
    case invalidTopology(String)
    case invalidFrequency(Double)
    case invalidImpedance(Double)
    case frequencyOutsideImpedanceTable(Double)
    case singularNetwork(Double)

    public var errorDescription: String? {
        switch self {
        case .invalidTopology(let reason): "Invalid AC topology: \(reason)"
        case .invalidFrequency(let value): "Invalid AC frequency \(value)."
        case .invalidImpedance(let frequency): "Invalid impedance at \(frequency) Hz."
        case .frequencyOutsideImpedanceTable(let frequency): "No tabulated impedance covers \(frequency) Hz."
        case .singularNetwork(let frequency): "The AC network is singular at \(frequency) Hz."
        }
    }
}

/// Prepared nodal analysis. The complex matrix is mapped to a real 2N sparse
/// block system. Its structural analysis is computed once and reused for each
/// numerical refactorization in a frequency sweep.
public struct PreparedACNetwork: Sendable {
    public let network: ACNetwork
    public let unknownNodes: [Int]
    private let indexByNode: [Int: Int]
    private let rowPointers: [Int]
    private let columnIndices: [Int]
    private let symbolicAnalysis: SparseSymbolicAnalysis

    public init(_ network: ACNetwork) throws {
        guard network.referenceNode != network.sourceNode else {
            throw ACAnalysisError.invalidTopology("source and reference nodes must differ")
        }
        guard network.sourceVoltage.isFinite, network.sourceVoltage.magnitude > 0 else {
            throw ACAnalysisError.invalidTopology("source voltage must be finite and non-zero")
        }
        guard !network.elements.isEmpty else { throw ACAnalysisError.invalidTopology("network has no elements") }
        let allNodes = Set(network.elements.flatMap { [$0.firstNode, $0.secondNode] })
        guard allNodes.contains(network.referenceNode), allNodes.contains(network.sourceNode) else {
            throw ACAnalysisError.invalidTopology("source and reference must be connected")
        }
        let unknownNodes = allNodes.filter { $0 != network.referenceNode && $0 != network.sourceNode }.sorted()
        self.network = network
        self.unknownNodes = unknownNodes
        indexByNode = Dictionary(uniqueKeysWithValues: unknownNodes.enumerated().map { ($0.element, $0.offset) })

        let size = unknownNodes.count
        var pattern = Set<Coordinate>()
        for element in network.elements {
            let first = indexByNode[element.firstNode]
            let second = indexByNode[element.secondNode]
            if let first { pattern.insert(.init(row: first, column: first)) }
            if let second { pattern.insert(.init(row: second, column: second)) }
            if let first, let second {
                pattern.insert(.init(row: first, column: second))
                pattern.insert(.init(row: second, column: first))
            }
        }
        guard size == 0 || (0..<size).allSatisfy({ row in pattern.contains(where: { $0.row == row }) }) else {
            throw ACAnalysisError.invalidTopology("an unknown node is disconnected")
        }
        let realPattern = Self.realBlockPattern(pattern, complexSize: size)
        let storage = Self.csrStorage(size: 2 * size, coordinates: realPattern)
        rowPointers = storage.rowPointers
        columnIndices = storage.columnIndices
        let structural = try SparseMatrix<Double>(
            rows: 2 * size, cols: 2 * size,
            rowPointers: rowPointers, columnIndices: columnIndices,
            values: [Double](repeating: 1, count: columnIndices.count)
        )
        symbolicAnalysis = try SparseSymbolicAnalysis(matrix: structural, ordering: .minimumDegree)
    }

    public func solve(frequenciesHz: [Double]) throws -> [ACSolutionPoint] {
        guard !frequenciesHz.isEmpty else { return [] }
        if unknownNodes.isEmpty {
            return try frequenciesHz.map { try trivialSolution(frequencyHz: $0) }
        }
        var factorization: SparseLUFactorization?
        var output: [ACSolutionPoint] = []
        output.reserveCapacity(frequenciesHz.count)
        for frequency in frequenciesHz {
            try Task.checkCancellation()
            let assembled = try assemble(frequencyHz: frequency)
            do {
                if let factorization {
                    try factorization.refactor(with: assembled.matrix)
                } else {
                    factorization = try SparseLUFactorization(
                        matrix: assembled.matrix,
                        analysis: symbolicAnalysis,
                        options: .init(refinementSteps: 3, refinementTolerance: 1e-12)
                    )
                }
                guard let factorization else { throw ACAnalysisError.singularNetwork(frequency) }
                let solved = try factorization.solveRefined(assembled.rhs)
                output.append(try makeSolution(frequencyHz: frequency, realSolution: solved.solution, report: solved))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ACAnalysisError.singularNetwork(frequency)
            }
        }
        return output
    }

    private func assemble(frequencyHz: Double) throws -> (matrix: SparseMatrix<Double>, rhs: [Double]) {
        let n = unknownNodes.count
        var complexValues: [Coordinate: ACComplex] = [:]
        var rhs = [ACComplex](repeating: .init(real: 0), count: n)
        for element in network.elements {
            let admittance = ACComplex(real: 1) / (try element.impedance.impedance(at: frequencyHz))
            let first = indexByNode[element.firstNode]
            let second = indexByNode[element.secondNode]
            if let first { complexValues[.init(row: first, column: first), default: .init(real: 0)] = complexValues[.init(row: first, column: first), default: .init(real: 0)] + admittance }
            if let second { complexValues[.init(row: second, column: second), default: .init(real: 0)] = complexValues[.init(row: second, column: second), default: .init(real: 0)] + admittance }
            if let first, let second {
                complexValues[.init(row: first, column: second), default: .init(real: 0)] = complexValues[.init(row: first, column: second), default: .init(real: 0)] - admittance
                complexValues[.init(row: second, column: first), default: .init(real: 0)] = complexValues[.init(row: second, column: first), default: .init(real: 0)] - admittance
            } else if element.firstNode == network.sourceNode, let second {
                rhs[second] = rhs[second] + admittance * network.sourceVoltage
            } else if element.secondNode == network.sourceNode, let first {
                rhs[first] = rhs[first] + admittance * network.sourceVoltage
            }
        }
        let values = Self.realBlockValues(
            rowPointers: rowPointers, columnIndices: columnIndices,
            complexValues: complexValues, complexSize: n
        )
        return (
            try SparseMatrix(rows: 2 * n, cols: 2 * n, rowPointers: rowPointers, columnIndices: columnIndices, values: values),
            rhs.map(\.real) + rhs.map(\.imaginary)
        )
    }

    private func makeSolution(frequencyHz: Double, realSolution: [Double], report: SparseRefinedResult) throws -> ACSolutionPoint {
        let n = unknownNodes.count
        var voltages = Dictionary(uniqueKeysWithValues: unknownNodes.enumerated().map {
            ($0.element, ACComplex(real: realSolution[$0.offset], imaginary: realSolution[$0.offset + n]))
        })
        voltages[network.referenceNode] = .init(real: 0)
        voltages[network.sourceNode] = network.sourceVoltage
        return try solutionPoint(frequencyHz: frequencyHz, voltages: voltages, report: report)
    }

    private func trivialSolution(frequencyHz: Double) throws -> ACSolutionPoint {
        let voltages = [network.referenceNode: ACComplex(real: 0), network.sourceNode: network.sourceVoltage]
        var currents: [String: ACComplex] = [:]
        var inputCurrent = ACComplex(real: 0)
        for element in network.elements {
            let impedance = try element.impedance.impedance(at: frequencyHz)
            let current = ((voltages[element.firstNode] ?? .init(real: 0)) - (voltages[element.secondNode] ?? .init(real: 0))) / impedance
            currents[element.id] = current
            if element.firstNode == network.sourceNode { inputCurrent = inputCurrent + current }
            if element.secondNode == network.sourceNode { inputCurrent = inputCurrent - current }
        }
        guard inputCurrent.magnitude > 0 else { throw ACAnalysisError.singularNetwork(frequencyHz) }
        return ACSolutionPoint(
            frequencyHz: frequencyHz, nodeVoltages: voltages, elementCurrents: currents,
            inputImpedance: network.sourceVoltage / inputCurrent,
            diagnostics: .init(
                backendIdentifier: "numeric-core-sparse-lu", residualNorm: 0, relativeResidual: 0,
                backwardError: 0, refinementSteps: 0, originalNonZeroCount: 0,
                factorNonZeroCount: 0, fillRatio: 0, minimumAbsolutePivot: .infinity, pivotGrowth: 0
            )
        )
    }

    private func solutionPoint(frequencyHz: Double, voltages: [Int: ACComplex], report: SparseRefinedResult) throws -> ACSolutionPoint {
        var currents: [String: ACComplex] = [:]
        var inputCurrent = ACComplex(real: 0)
        for element in network.elements {
            let impedance = try element.impedance.impedance(at: frequencyHz)
            let firstVoltage = voltages[element.firstNode] ?? .init(real: 0)
            let secondVoltage = voltages[element.secondNode] ?? .init(real: 0)
            let current = (firstVoltage - secondVoltage) / impedance
            currents[element.id] = current
            if element.firstNode == network.sourceNode { inputCurrent = inputCurrent + current }
            if element.secondNode == network.sourceNode { inputCurrent = inputCurrent - current }
        }
        guard inputCurrent.isFinite, inputCurrent.magnitude > 0 else { throw ACAnalysisError.singularNetwork(frequencyHz) }
        let d = report.diagnostics
        return ACSolutionPoint(
            frequencyHz: frequencyHz,
            nodeVoltages: voltages,
            elementCurrents: currents,
            inputImpedance: network.sourceVoltage / inputCurrent,
            diagnostics: .init(
                backendIdentifier: "numeric-core-sparse-lu",
                residualNorm: report.residualNorm,
                relativeResidual: report.relativeResidual,
                backwardError: report.backwardError,
                refinementSteps: report.refinementSteps,
                originalNonZeroCount: d.originalNonZeroCount,
                factorNonZeroCount: d.factorNonZeroCount,
                fillRatio: d.fillRatio,
                minimumAbsolutePivot: d.minimumAbsolutePivot,
                pivotGrowth: d.pivotGrowth
            )
        )
    }

    private struct Coordinate: Hashable, Sendable { let row: Int; let column: Int }

    private static func realBlockPattern(_ complex: Set<Coordinate>, complexSize n: Int) -> [Coordinate] {
        complex.flatMap { coordinate in
            [
                Coordinate(row: coordinate.row, column: coordinate.column),
                Coordinate(row: coordinate.row, column: coordinate.column + n),
                Coordinate(row: coordinate.row + n, column: coordinate.column),
                Coordinate(row: coordinate.row + n, column: coordinate.column + n),
            ]
        }
    }

    private static func csrStorage(size: Int, coordinates: [Coordinate]) -> (rowPointers: [Int], columnIndices: [Int]) {
        let sorted = Set(coordinates).sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        var rows = [Int](repeating: 0, count: size + 1)
        for coordinate in sorted { rows[coordinate.row + 1] += 1 }
        for row in 0..<size { rows[row + 1] += rows[row] }
        return (rows, sorted.map(\.column))
    }

    private static func realBlockValues(
        rowPointers: [Int], columnIndices: [Int], complexValues: [Coordinate: ACComplex], complexSize n: Int
    ) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(columnIndices.count)
        for row in 0..<(2 * n) {
            for index in rowPointers[row]..<rowPointers[row + 1] {
                let column = columnIndices[index]
                let complexRow = row % n
                let complexColumn = column % n
                let value = complexValues[.init(row: complexRow, column: complexColumn)] ?? .init(real: 0)
                switch (row < n, column < n) {
                case (true, true), (false, false): result.append(value.real)
                case (true, false): result.append(-value.imaginary)
                case (false, true): result.append(value.imaginary)
                }
            }
        }
        return result
    }
}
