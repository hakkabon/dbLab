import Foundation

struct CrossoverSimulationResult {
    var response: [AcousticResponsePoint]
    var warnings: [String]
}

enum CrossoverNetworkSimulationError: LocalizedError {
    case missingGround
    case missingNode(String)
    case invalidNodeAssignment
    case missingComponent(String)
    case missingPin(String)
    case invalidParameter(String)
    case unsupportedComponent(String)
    case missingMeasurement(driver: String, kind: DriverMeasurementKind)
    case noFrequencyOverlap
    case singularNetwork(frequencyHz: Double)

    var errorDescription: String? {
        switch self {
        case .missingGround:
            "Connect a ground symbol to the crossover's common return before simulating."
        case .missingNode(let role):
            "Assign a schematic net to the \(role)."
        case .invalidNodeAssignment:
            "The input and driver output nodes must be distinct from ground; the woofer and tweeter outputs must also be distinct."
        case .missingComponent(let reference):
            "\(reference) does not have a supported component definition."
        case .missingPin(let reference):
            "\(reference) has an unconnected schematic pin."
        case .invalidParameter(let reference):
            "\(reference) has a missing, non-finite, or non-positive component value."
        case .unsupportedComponent(let reference):
            "\(reference) is not supported by the passive crossover solver."
        case .missingMeasurement(let driver, let kind):
            "\(driver) needs an imported \(kind.title.lowercased()) dataset for this simulation."
        case .noFrequencyOverlap:
            "The selected driver measurements have no common usable frequency range."
        case .singularNetwork(let frequency):
            "The passive network is floating or singular near \(frequency.formatted(.number.precision(.fractionLength(1)))) Hz. Check wiring, net assignments, and component connections."
        }
    }
}

@MainActor
enum CrossoverNetworkSimulator {
    private static let referenceVoltage = 2.83
    private static let pointsPerOctave = 24

    static func simulate(
        schematic: SchematicDocument,
        inputNetID: Int?,
        wooferOutputNetID: Int?,
        tweeterOutputNetID: Int?,
        woofer: AcousticBranchSettings,
        tweeter: AcousticBranchSettings,
        wooferFrequencyResponse: DriverMeasurement?,
        tweeterFrequencyResponse: DriverMeasurement?,
        wooferImpedance: DriverMeasurement?,
        tweeterImpedance: DriverMeasurement?
    ) throws -> CrossoverSimulationResult {
        guard let inputNetID else { throw CrossoverNetworkSimulationError.missingNode("input") }
        guard let wooferOutputNetID else { throw CrossoverNetworkSimulationError.missingNode("woofer output") }
        guard let tweeterOutputNetID else { throw CrossoverNetworkSimulationError.missingNode("tweeter output") }

        let nets = ConnectivityBuilder.build(symbols: schematic.symbols, wires: schematic.wires)
        guard let groundNet = nets.first(where: \.isGround) else {
            throw CrossoverNetworkSimulationError.missingGround
        }
        let groundNetIDs = Set(nets.filter(\.isGround).map(\.id))
        let validNodeIDs = Set(nets.map(\.id))
        guard validNodeIDs.contains(inputNetID),
              validNodeIDs.contains(wooferOutputNetID),
              validNodeIDs.contains(tweeterOutputNetID),
              !groundNetIDs.contains(inputNetID),
              !groundNetIDs.contains(wooferOutputNetID),
              !groundNetIDs.contains(tweeterOutputNetID),
              inputNetID != wooferOutputNetID,
              inputNetID != tweeterOutputNetID,
              wooferOutputNetID != tweeterOutputNetID else {
            throw CrossoverNetworkSimulationError.invalidNodeAssignment
        }

        try validateAcousticBranch(woofer, validateEnclosure: wooferFrequencyResponse == nil)
        try validateAcousticBranch(tweeter, validateEnclosure: tweeterFrequencyResponse == nil)
        try validateMeasurement(wooferFrequencyResponse, kind: .frequencyResponse, driver: woofer.driver)
        try validateMeasurement(tweeterFrequencyResponse, kind: .frequencyResponse, driver: tweeter.driver)
        try validateMeasurement(wooferImpedance, kind: .impedance, driver: woofer.driver)
        try validateMeasurement(tweeterImpedance, kind: .impedance, driver: tweeter.driver)

        let components = try componentBranches(schematic: schematic, nets: nets)
        let bounds = frequencyBounds(
            wooferFrequencyResponse: wooferFrequencyResponse,
            tweeterFrequencyResponse: tweeterFrequencyResponse,
            wooferImpedance: wooferImpedance,
            tweeterImpedance: tweeterImpedance
        )
        guard bounds.lowerBound < bounds.upperBound else {
            throw CrossoverNetworkSimulationError.noFrequencyOverlap
        }
        let frequencies = logFrequencies(
            start: bounds.lowerBound,
            stop: bounds.upperBound,
            pointsPerOctave: pointsPerOctave
        )
        let unknownNodeIDs = nets.map(\.id)
            .filter { !groundNetIDs.contains($0) && $0 != inputNetID }
            .sorted()
        var points: [AcousticResponsePoint] = []

        for frequency in frequencies {
            var branches = components.map {
                CircuitBranch(
                    firstNodeID: groundNetIDs.contains($0.firstNodeID) ? groundNet.id : $0.firstNodeID,
                    secondNodeID: groundNetIDs.contains($0.secondNodeID) ? groundNet.id : $0.secondNodeID,
                    impedance: $0.impedance(at: frequency)
                )
            }
            branches.append(CircuitBranch(
                firstNodeID: wooferOutputNetID,
                secondNodeID: groundNet.id,
                impedance: impedance(of: woofer.driver, measurement: wooferImpedance, frequencyHz: frequency)
            ))
            branches.append(CircuitBranch(
                firstNodeID: tweeterOutputNetID,
                secondNodeID: groundNet.id,
                impedance: impedance(of: tweeter.driver, measurement: tweeterImpedance, frequencyHz: frequency)
            ))

            let voltages = try solve(
                branches: branches,
                unknownNodeIDs: unknownNodeIDs,
                inputNodeID: inputNetID,
                groundNodeID: groundNet.id,
                inputVoltage: referenceVoltage,
                frequencyHz: frequency
            )
            guard let wooferVoltage = voltages[wooferOutputNetID],
                  let tweeterVoltage = voltages[tweeterOutputNetID] else {
                throw CrossoverNetworkSimulationError.invalidNodeAssignment
            }

            let wooferAcoustic = acousticResponse(
                branch: woofer,
                measurement: wooferFrequencyResponse,
                frequencyHz: frequency
            ) * (wooferVoltage / ComplexValue(real: referenceVoltage, imaginary: 0))
            let tweeterAcoustic = acousticResponse(
                branch: tweeter,
                measurement: tweeterFrequencyResponse,
                frequencyHz: frequency
            ) * (tweeterVoltage / ComplexValue(real: referenceVoltage, imaginary: 0))
            points.append(AcousticResponsePoint(
                frequencyHz: frequency,
                wooferDb: decibels(wooferAcoustic.magnitude),
                tweeterDb: decibels(tweeterAcoustic.magnitude),
                totalDb: decibels((wooferAcoustic + tweeterAcoustic).magnitude)
            ))
        }

        guard points.allSatisfy({
            $0.frequencyHz.isFinite && $0.wooferDb.isFinite
                && $0.tweeterDb.isFinite && $0.totalDb.isFinite
        }) else {
            throw CrossoverNetworkSimulationError.noFrequencyOverlap
        }

        var warnings: [String] = []
        if wooferFrequencyResponse == nil || tweeterFrequencyResponse == nil {
            warnings.append("A driver has no selected measured response; its enclosure model estimates acoustic output.")
        }
        if wooferImpedance == nil || tweeterImpedance == nil {
            warnings.append("A driver has no selected measured impedance; its Re + jωLe model estimates the load.")
        }
        if wooferImpedance?.hasPhaseData == false || tweeterImpedance?.hasPhaseData == false {
            warnings.append("A selected impedance dataset lacks phase; that driver's load is treated as purely resistive between samples.")
        }
        if wooferFrequencyResponse?.hasPhaseData == false || tweeterFrequencyResponse?.hasPhaseData == false {
            warnings.append("A selected response dataset lacks phase; acoustic summation uses zero phase for that driver.")
        }
        return CrossoverSimulationResult(response: points, warnings: warnings)
    }

    private static func validateMeasurement(
        _ measurement: DriverMeasurement?,
        kind: DriverMeasurementKind,
        driver: SpeakerDriver
    ) throws {
        guard let measurement else { return }
        guard measurement.kind == kind, measurement.validationMessage == nil else {
            throw CrossoverNetworkSimulationError.missingMeasurement(driver: driver.displayName, kind: kind)
        }
    }

    private static func validateAcousticBranch(
        _ branch: AcousticBranchSettings,
        validateEnclosure: Bool
    ) throws {
        guard branch.driver.validationMessage == nil else {
            throw CrossoverNetworkSimulationError.invalidParameter(branch.driver.displayName)
        }
        guard validateEnclosure else { return }
        switch branch.enclosure {
        case .openBaffle:
            guard branch.baffleWidthMeters.isFinite, branch.baffleWidthMeters > 0 else {
                throw CrossoverNetworkSimulationError.invalidParameter("Open-baffle width")
            }
        case .closedBox:
            guard branch.boxVolumeLiters.isFinite, branch.boxVolumeLiters > 0 else {
                throw CrossoverNetworkSimulationError.invalidParameter("Closed-box volume")
            }
        case .portedBox:
            guard PortedBoxDesign.portLengthCentimeters(
                volumeLiters: branch.boxVolumeLiters,
                tuningHz: branch.portTuningHz,
                diameterCentimeters: branch.portDiameterCentimeters
            ) != nil else {
                throw CrossoverNetworkSimulationError.invalidParameter("Ported-box dimensions")
            }
        }
    }

    private static func componentBranches(
        schematic: SchematicDocument,
        nets: [Net]
    ) throws -> [PassiveComponentBranch] {
        let nodeByPin = Dictionary(
            uniqueKeysWithValues: nets.flatMap { net in
                net.connectedPins.map { ($0, net.id) }
            }
        )
        var branches: [PassiveComponentBranch] = []

        for symbol in schematic.symbols {
            guard let descriptor = ComponentRegistry.shared.descriptor(for: symbol.descriptorId) else {
                throw CrossoverNetworkSimulationError.missingComponent(symbol.refDes)
            }
            if descriptor.symbol == .ground { continue }
            guard descriptor.symbol == .resistor || descriptor.symbol == .capacitor
                    || descriptor.symbol == .inductor || descriptor.symbol == .inductorSeries else {
                throw CrossoverNetworkSimulationError.unsupportedComponent(symbol.refDes)
            }
            guard descriptor.pins.count == 2,
                  let first = descriptor.pins.first,
                  let second = descriptor.pins.last,
                  let firstNode = nodeByPin[PinRef(symbolId: symbol.id, pinId: first.id)],
                  let secondNode = nodeByPin[PinRef(symbolId: symbol.id, pinId: second.id)] else {
                throw CrossoverNetworkSimulationError.missingPin(symbol.refDes)
            }

            let value: Double
            switch descriptor.symbol {
            case .resistor:
                value = try positiveParameter("resistance", in: symbol)
                branches.append(PassiveComponentBranch(
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .resistor,
                    value: value,
                    seriesResistance: 0
                ))
            case .capacitor:
                value = try positiveParameter("capacitance", in: symbol)
                branches.append(PassiveComponentBranch(
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .capacitor,
                    value: value,
                    seriesResistance: 0
                ))
            case .inductor:
                value = try positiveParameter("inductance", in: symbol)
                branches.append(PassiveComponentBranch(
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .inductor,
                    value: value,
                    seriesResistance: 0
                ))
            case .inductorSeries:
                value = try positiveParameter("inductance", in: symbol)
                guard let resistance = symbol.parameters["seriesResistance"],
                      resistance.isFinite, resistance >= 0 else {
                    throw CrossoverNetworkSimulationError.invalidParameter(symbol.refDes)
                }
                branches.append(PassiveComponentBranch(
                    firstNodeID: firstNode,
                    secondNodeID: secondNode,
                    type: .inductor,
                    value: value,
                    seriesResistance: resistance
                ))
            case .voltageSource, .currentSource, .ground:
                throw CrossoverNetworkSimulationError.unsupportedComponent(symbol.refDes)
            }
        }
        return branches
    }

    private static func positiveParameter(_ name: String, in symbol: SymbolInstance) throws -> Double {
        guard let value = symbol.parameters[name], value.isFinite, value > 0 else {
            throw CrossoverNetworkSimulationError.invalidParameter(symbol.refDes)
        }
        return value
    }

    private static func impedance(
        of driver: SpeakerDriver,
        measurement: DriverMeasurement?,
        frequencyHz: Double
    ) -> ComplexValue {
        if let measurement, let value = interpolatedComplex(measurement, frequencyHz: frequencyHz) {
            return value
        }
        return ComplexValue(
            real: driver.reOhms,
            imaginary: 2 * Double.pi * frequencyHz * driver.leMilliHenries / 1_000
        )
    }

    private static func acousticResponse(
        branch: AcousticBranchSettings,
        measurement: DriverMeasurement?,
        frequencyHz: Double
    ) -> ComplexValue {
        if let measurement, let response = interpolatedResponse(measurement, frequencyHz: frequencyHz) {
            return response
        }
        return AcousticSimulator.modeledAcousticResponse(branch, frequencyHz: frequencyHz)
    }

    private static func frequencyBounds(
        wooferFrequencyResponse: DriverMeasurement?,
        tweeterFrequencyResponse: DriverMeasurement?,
        wooferImpedance: DriverMeasurement?,
        tweeterImpedance: DriverMeasurement?
    ) -> ClosedRange<Double> {
        let measurements = [
            wooferFrequencyResponse, tweeterFrequencyResponse,
            wooferImpedance, tweeterImpedance
        ].compactMap { $0 }
        let lower = max(20, measurements.compactMap { $0.points.first?.frequencyHz }.max() ?? 20)
        let upper = min(20_000, measurements.compactMap { $0.points.last?.frequencyHz }.min() ?? 20_000)
        return lower...max(lower, upper)
    }

    private static func interpolatedComplex(
        _ measurement: DriverMeasurement,
        frequencyHz: Double
    ) -> ComplexValue? {
        guard measurement.points.count >= 2,
              let interval = interval(in: measurement.points, frequencyHz: frequencyHz) else {
            return nil
        }
        let (first, second, fraction) = interval
        let firstMagnitude = first.magnitude
        let secondMagnitude = second.magnitude
        let magnitude = exp(log(firstMagnitude) + fraction * (log(secondMagnitude) - log(firstMagnitude)))
        let phase = interpolatedPhase(
            first.phaseDegrees,
            second.phaseDegrees,
            fraction: fraction
        )
        return ComplexValue.polar(magnitude: magnitude, phaseRadians: phase * .pi / 180)
    }

    private static func interpolatedResponse(
        _ measurement: DriverMeasurement,
        frequencyHz: Double
    ) -> ComplexValue? {
        guard measurement.points.count >= 2,
              let interval = interval(in: measurement.points, frequencyHz: frequencyHz) else {
            return nil
        }
        let (first, second, fraction) = interval
        let magnitudeDb = first.magnitude + fraction * (second.magnitude - first.magnitude)
        let phase = interpolatedPhase(first.phaseDegrees, second.phaseDegrees, fraction: fraction)
        return ComplexValue.polar(
            magnitude: pow(10, magnitudeDb / 20),
            phaseRadians: phase * .pi / 180
        )
    }

    private static func interval(
        in points: [DriverMeasurementPoint],
        frequencyHz: Double
    ) -> (DriverMeasurementPoint, DriverMeasurementPoint, Double)? {
        guard let first = points.first, let last = points.last,
              frequencyHz >= first.frequencyHz, frequencyHz <= last.frequencyHz else {
            return nil
        }
        guard frequencyHz != first.frequencyHz else {
            return (first, points[1], 0)
        }
        guard frequencyHz != last.frequencyHz else {
            return (points[points.count - 2], last, 1)
        }
        guard let upperIndex = points.firstIndex(where: { $0.frequencyHz >= frequencyHz }),
              upperIndex > 0 else {
            return nil
        }
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let fraction = log(frequencyHz / lower.frequencyHz) / log(upper.frequencyHz / lower.frequencyHz)
        return (lower, upper, fraction)
    }

    private static func interpolatedPhase(_ first: Double, _ second: Double, fraction: Double) -> Double {
        var difference = second - first
        while difference > 180 { difference -= 360 }
        while difference < -180 { difference += 360 }
        return first + fraction * difference
    }

    private static func logFrequencies(start: Double, stop: Double, pointsPerOctave: Int) -> [Double] {
        let intervals = max(1, Int(ceil(log2(stop / start) * Double(pointsPerOctave))))
        return (0...intervals).map {
            start * pow(stop / start, Double($0) / Double(intervals))
        }
    }

    private static func decibels(_ magnitude: Double) -> Double {
        20 * log10(max(magnitude, 1e-12))
    }

    private static func solve(
        branches: [CircuitBranch],
        unknownNodeIDs: [Int],
        inputNodeID: Int,
        groundNodeID: Int,
        inputVoltage: Double,
        frequencyHz: Double
    ) throws -> [Int: ComplexValue] {
        let indexByNode = Dictionary(uniqueKeysWithValues: unknownNodeIDs.enumerated().map { ($0.element, $0.offset) })
        var matrix = Array(
            repeating: Array(repeating: ComplexValue(real: 0, imaginary: 0), count: unknownNodeIDs.count),
            count: unknownNodeIDs.count
        )
        var rhs = Array(repeating: ComplexValue(real: 0, imaginary: 0), count: unknownNodeIDs.count)

        for branch in branches {
            guard branch.impedance.magnitude.isFinite, branch.impedance.magnitude > 0 else {
                throw CrossoverNetworkSimulationError.singularNetwork(frequencyHz: frequencyHz)
            }
            let admittance = ComplexValue(real: 1, imaginary: 0) / branch.impedance
            let firstIndex = indexByNode[branch.firstNodeID]
            let secondIndex = indexByNode[branch.secondNodeID]

            if let firstIndex {
                matrix[firstIndex][firstIndex] = matrix[firstIndex][firstIndex] + admittance
            }
            if let secondIndex {
                matrix[secondIndex][secondIndex] = matrix[secondIndex][secondIndex] + admittance
            }
            if let firstIndex, let secondIndex {
                matrix[firstIndex][secondIndex] = matrix[firstIndex][secondIndex] - admittance
                matrix[secondIndex][firstIndex] = matrix[secondIndex][firstIndex] - admittance
            } else if branch.firstNodeID == inputNodeID, let secondIndex {
                rhs[secondIndex] = rhs[secondIndex] + admittance * inputVoltage
            } else if branch.secondNodeID == inputNodeID, let firstIndex {
                rhs[firstIndex] = rhs[firstIndex] + admittance * inputVoltage
            }
        }

        let solution = try gaussianSolve(matrix: matrix, rhs: rhs, frequencyHz: frequencyHz)
        var voltages = Dictionary(uniqueKeysWithValues: zip(unknownNodeIDs, solution))
        voltages[inputNodeID] = ComplexValue(real: inputVoltage, imaginary: 0)
        voltages[groundNodeID] = ComplexValue(real: 0, imaginary: 0)
        return voltages
    }

    private static func gaussianSolve(
        matrix: [[ComplexValue]],
        rhs: [ComplexValue],
        frequencyHz: Double
    ) throws -> [ComplexValue] {
        let size = rhs.count
        guard size > 0 else { return [] }
        var matrix = matrix
        var rhs = rhs
        let matrixScale = matrix.flatMap { $0 }.map(\.magnitude).max() ?? 0
        guard matrixScale.isFinite, matrixScale > 0 else {
            throw CrossoverNetworkSimulationError.singularNetwork(frequencyHz: frequencyHz)
        }
        let tolerance = matrixScale * 1e-12

        for column in 0..<size {
            guard let pivotRow = (column..<size).max(by: {
                matrix[$0][column].magnitude < matrix[$1][column].magnitude
            }), matrix[pivotRow][column].magnitude > tolerance else {
                throw CrossoverNetworkSimulationError.singularNetwork(frequencyHz: frequencyHz)
            }
            if pivotRow != column {
                matrix.swapAt(pivotRow, column)
                rhs.swapAt(pivotRow, column)
            }
            for row in (column + 1)..<size {
                let factor = matrix[row][column] / matrix[column][column]
                for index in column..<size {
                    matrix[row][index] = matrix[row][index] - factor * matrix[column][index]
                }
                rhs[row] = rhs[row] - factor * rhs[column]
            }
        }

        var solution = Array(repeating: ComplexValue(real: 0, imaginary: 0), count: size)
        for row in stride(from: size - 1, through: 0, by: -1) {
            var value = rhs[row]
            if row + 1 < size {
                for column in (row + 1)..<size {
                    value = value - matrix[row][column] * solution[column]
                }
            }
            solution[row] = value / matrix[row][row]
            guard solution[row].magnitude.isFinite else {
                throw CrossoverNetworkSimulationError.singularNetwork(frequencyHz: frequencyHz)
            }
        }
        return solution
    }
}

private struct PassiveComponentBranch {
    enum Kind {
        case resistor
        case capacitor
        case inductor
    }

    let firstNodeID: Int
    let secondNodeID: Int
    let type: Kind
    let value: Double
    let seriesResistance: Double

    func impedance(at frequencyHz: Double) -> ComplexValue {
        let angularFrequency = 2 * Double.pi * frequencyHz
        switch type {
        case .resistor:
            return ComplexValue(real: value, imaginary: 0)
        case .capacitor:
            return ComplexValue(real: 0, imaginary: -1 / (angularFrequency * value))
        case .inductor:
            return ComplexValue(real: seriesResistance, imaginary: angularFrequency * value)
        }
    }
}

private struct CircuitBranch {
    let firstNodeID: Int
    let secondNodeID: Int
    let impedance: ComplexValue
}
