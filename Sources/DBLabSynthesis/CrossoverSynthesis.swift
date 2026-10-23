import Foundation
import DBLabNumeric
import NumericCoreOptimization
import NumericCore

public enum SynthesisAlignment: String, Codable, Sendable, Hashable {
    case butterworth
    case linkwitzRiley
}

public enum SynthesisBand: String, Codable, Sendable, Hashable {
    case lowPass
    case highPass
}

public enum SynthesizedComponentKind: String, Codable, Sendable, Hashable {
    case seriesInductor
    case shuntCapacitor
    case seriesCapacitor
    case shuntInductor

    public var isInductor: Bool {
        self == .seriesInductor || self == .shuntInductor
    }
}

public struct SynthesizedComponent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: SynthesizedComponentKind
    /// Henries for inductors and farads for capacitors.
    public let value: Double
    public let continuousOptimizedValue: Double
    public let initialValue: Double

    public init(
        id: String, kind: SynthesizedComponentKind, value: Double,
        continuousOptimizedValue: Double, initialValue: Double
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.continuousOptimizedValue = continuousOptimizedValue
        self.initialValue = initialValue
    }
}

public struct SynthesizedBranch: Codable, Sendable, Hashable {
    public let band: SynthesisBand
    public let components: [SynthesizedComponent]
}

public struct SynthesisResponsePoint: Codable, Sendable, Hashable {
    public let frequencyHz: Double
    public let lowPassMagnitude: Double
    public let highPassMagnitude: Double
    public let targetLowPassMagnitude: Double
    public let targetHighPassMagnitude: Double
    public let systemInputImpedanceOhms: Double
}

public struct CrossoverSynthesisRequest: Sendable, Hashable {
    public let crossoverFrequencyHz: Double
    public let alignment: SynthesisAlignment
    public let order: Int
    public let lowPassLoad: [ACImpedanceSample]
    public let highPassLoad: [ACImpedanceSample]
    public let minimumInputImpedanceOhms: Double
    public let pointsPerOctave: Int

    public init(
        crossoverFrequencyHz: Double, alignment: SynthesisAlignment, order: Int,
        lowPassLoad: [ACImpedanceSample], highPassLoad: [ACImpedanceSample],
        minimumInputImpedanceOhms: Double = 3.2, pointsPerOctave: Int = 8
    ) {
        self.crossoverFrequencyHz = crossoverFrequencyHz
        self.alignment = alignment
        self.order = order
        self.lowPassLoad = lowPassLoad
        self.highPassLoad = highPassLoad
        self.minimumInputImpedanceOhms = minimumInputImpedanceOhms
        self.pointsPerOctave = pointsPerOctave
    }
}

public struct CrossoverSynthesisResult: Sendable, Hashable {
    public let lowPass: SynthesizedBranch
    public let highPass: SynthesizedBranch
    public let response: [SynthesisResponsePoint]
    public let rmsMagnitudeErrorDecibels: Double
    public let minimumInputImpedanceOhms: Double
    public let objective: Double
    public let iterations: Int
    public let evaluations: Int
    public let termination: NonlinearTermination
    public let backendIdentifier: String
    public let preferredValueSeries: String
}

public enum CrossoverSynthesisError: Error, LocalizedError, Equatable {
    case invalidRequest(String)
    case numericalFailure

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason): "Invalid crossover synthesis request: \(reason)"
        case .numericalFailure: "NumericCore could not synthesize a stable crossover for these loads."
        }
    }
}

public enum PassiveCrossoverSynthesizer {
    public static func synthesize(_ request: CrossoverSynthesisRequest) throws -> CrossoverSynthesisResult {
        try validate(request)
        let frequencies = logFrequencies(
            start: request.crossoverFrequencyHz / 4,
            stop: request.crossoverFrequencyHz * 4,
            pointsPerOctave: request.pointsPerOctave
        )
        let lowLoad = try resample(request.lowPassLoad, at: frequencies)
        let highLoad = try resample(request.highPassLoad, at: frequencies)
        let lowNominal = nominalComponents(
            band: .lowPass, order: request.order, alignment: request.alignment,
            resistance: nominalResistance(lowLoad), frequency: request.crossoverFrequencyHz
        )
        let highNominal = nominalComponents(
            band: .highPass, order: request.order, alignment: request.alignment,
            resistance: nominalResistance(highLoad), frequency: request.crossoverFrequencyHz
        )
        let nominal = lowNominal + highNominal
        let initial = nominal.map { log($0.value) }
        let span = log(12.0)
        let bounds = initial.map { ParameterBound(lower: $0 - span, upper: $0 + span) }

        func objective(_ parameters: [Double]) throws -> Double {
            let values = parameters.map(exp)
            let low = try branchResponse(
                band: .lowPass, components: Array(values[..<lowNominal.count]),
                load: lowLoad, frequencies: frequencies
            )
            let high = try branchResponse(
                band: .highPass, components: Array(values[lowNominal.count...]),
                load: highLoad, frequencies: frequencies
            )
            return score(low: low, high: high, frequencies: frequencies, request: request)
        }

        let optimized = try LBFGSB.minimize(
            initial: initial,
            bounds: bounds,
            options: .init(
                maxIterations: 80, historySize: 8, gradientTolerance: 2e-5,
                stepTolerance: 1e-8, objectiveTolerance: 1e-10,
                maxLineSearchIterations: 20
            )
        ) { point in
            try Task.checkCancellation()
            let value = try objective(point)
            let gradient = try FiniteDifference.centralGradient(
                at: point, relativeStep: 2e-4, objective: objective
            )
            return (value, gradient.gradient)
        }
        let continuousValues = optimized.point.map(exp)
        let values = continuousValues.map(preferredE24)
        let lowValues = Array(values[..<lowNominal.count])
        let highValues = Array(values[lowNominal.count...])
        let low = try branchResponse(band: .lowPass, components: lowValues, load: lowLoad, frequencies: frequencies)
        let high = try branchResponse(band: .highPass, components: highValues, load: highLoad, frequencies: frequencies)
        let response = zip(zip(frequencies, low), high).map { pair, highPoint in
            let (frequency, lowPoint) = pair
            let targets = targetMagnitudes(
                frequency / request.crossoverFrequencyHz,
                order: request.order, alignment: request.alignment
            )
            return SynthesisResponsePoint(
                frequencyHz: frequency,
                lowPassMagnitude: lowPoint.outputMagnitude,
                highPassMagnitude: highPoint.outputMagnitude,
                targetLowPassMagnitude: targets.low,
                targetHighPassMagnitude: targets.high,
                systemInputImpedanceOhms: parallelMagnitude(lowPoint.inputImpedance, highPoint.inputImpedance)
            )
        }
        let squaredDBError = response.reduce(0.0) { partial, point in
            partial + pow(db(point.lowPassMagnitude) - db(point.targetLowPassMagnitude), 2)
                + pow(db(point.highPassMagnitude) - db(point.targetHighPassMagnitude), 2)
        }
        return .init(
            lowPass: makeBranch(
                .lowPass, nominal: lowNominal, values: lowValues,
                continuousValues: Array(continuousValues[..<lowNominal.count])
            ),
            highPass: makeBranch(
                .highPass, nominal: highNominal, values: highValues,
                continuousValues: Array(continuousValues[lowNominal.count...])
            ),
            response: response,
            rmsMagnitudeErrorDecibels: sqrt(squaredDBError / Double(response.count * 2)),
            minimumInputImpedanceOhms: response.map(\.systemInputImpedanceOhms).min() ?? .nan,
            objective: try objective(values.map(log)),
            iterations: optimized.iterations,
            evaluations: optimized.evaluations,
            termination: optimized.termination,
            backendIdentifier: "numeric-core-lbfgsb+sparse-ac",
            preferredValueSeries: "E24"
        )
    }

    struct BranchPoint {
        let outputMagnitude: Double
        let inputImpedance: ACComplex
    }

    static func branchResponse(
        band: SynthesisBand, components: [Double],
        load: [ACImpedanceSample], frequencies: [Double]
    ) throws -> [BranchPoint] {
        let reference = -1
        let source = 0
        var node = source
        var nextNode = 1
        var elements: [ACTwoTerminalElement] = []
        for (index, value) in components.enumerated() {
            let stage = index + 1
            let series = stage.isMultiple(of: 2) == false
            if series {
                let newNode = nextNode
                nextNode += 1
                elements.append(.init(
                    id: "X\(stage)", firstNode: node, secondNode: newNode,
                    impedance: impedanceModel(band: band, series: true, value: value)
                ))
                node = newNode
            } else {
                elements.append(.init(
                    id: "X\(stage)", firstNode: node, secondNode: reference,
                    impedance: impedanceModel(band: band, series: false, value: value)
                ))
            }
        }
        elements.append(.init(id: "LOAD", firstNode: node, secondNode: reference, impedance: .tabulated(load)))
        let result = try PreparedACNetwork(.init(
            referenceNode: reference, sourceNode: source,
            sourceVoltage: .init(real: 1), elements: elements
        )).solve(frequenciesHz: frequencies)
        return result.map {
            BranchPoint(
                outputMagnitude: $0.nodeVoltages[node]?.magnitude ?? 0,
                inputImpedance: $0.inputImpedance
            )
        }
    }

    private static func impedanceModel(band: SynthesisBand, series: Bool, value: Double) -> ACImpedanceModel {
        switch (band, series) {
        case (.lowPass, true), (.highPass, false): .inductance(henries: value, seriesResistance: 0)
        case (.lowPass, false), (.highPass, true): .capacitance(value)
        }
    }

    private static func nominalComponents(
        band: SynthesisBand, order: Int, alignment: SynthesisAlignment,
        resistance: Double, frequency: Double
    ) -> [(kind: SynthesizedComponentKind, value: Double)] {
        let omega = 2 * Double.pi * frequency
        let g: [Double]
        switch alignment {
        case .butterworth:
            g = (1...order).map { 2 * sin(Double(2 * $0 - 1) * .pi / Double(2 * order)) }
        case .linkwitzRiley:
            // These are stable equal-termination seeds. NumericCore then fits
            // the actual complex loads rather than treating the seed as final.
            g = (1...order).map { index in
                let base = 2 * sin(Double(2 * index - 1) * .pi / Double(2 * order))
                return base * pow(2, 1 / Double(order))
            }
        }
        return g.enumerated().map { index, coefficient in
            let series = index.isMultiple(of: 2)
            switch (band, series) {
            case (.lowPass, true): return (.seriesInductor, resistance * coefficient / omega)
            case (.lowPass, false): return (.shuntCapacitor, coefficient / (resistance * omega))
            case (.highPass, true): return (.seriesCapacitor, 1 / (resistance * omega * coefficient))
            case (.highPass, false): return (.shuntInductor, resistance / (omega * coefficient))
            }
        }
    }

    private static func makeBranch(
        _ band: SynthesisBand, nominal: [(kind: SynthesizedComponentKind, value: Double)],
        values: [Double], continuousValues: [Double]
    ) -> SynthesizedBranch {
        SynthesizedBranch(band: band, components: zip(zip(nominal, values), continuousValues).enumerated().map { index, pair in
            SynthesizedComponent(
                id: "\(band.rawValue)-\(index + 1)", kind: pair.0.0.kind,
                value: pair.0.1, continuousOptimizedValue: pair.1,
                initialValue: pair.0.0.value
            )
        })
    }

    private static func preferredE24(_ value: Double) -> Double {
        let series = [
            1.0, 1.1, 1.2, 1.3, 1.5, 1.6, 1.8, 2.0,
            2.2, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.3,
            4.7, 5.1, 5.6, 6.2, 6.8, 7.5, 8.2, 9.1,
        ]
        let decade = pow(10, floor(log10(value)))
        let normalized = value / decade
        let candidates = series + [10]
        return candidates.min(by: { abs($0 - normalized) < abs($1 - normalized) })! * decade
    }

    private static func score(
        low: [BranchPoint], high: [BranchPoint], frequencies: [Double],
        request: CrossoverSynthesisRequest
    ) -> Double {
        zip(zip(frequencies, low), high).reduce(0) { total, item in
            let ((frequency, lowPoint), highPoint) = item
            let target = targetMagnitudes(
                frequency / request.crossoverFrequencyHz,
                order: request.order, alignment: request.alignment
            )
            let lowError = db(lowPoint.outputMagnitude) - db(target.low)
            let highError = db(highPoint.outputMagnitude) - db(target.high)
            let impedance = parallelMagnitude(lowPoint.inputImpedance, highPoint.inputImpedance)
            let impedancePenalty = max(0, request.minimumInputImpedanceOhms - impedance)
                / request.minimumInputImpedanceOhms
            return total + lowError * lowError + highError * highError + 100 * impedancePenalty * impedancePenalty
        } / Double(frequencies.count)
    }

    static func targetMagnitudes(
        _ ratio: Double, order: Int, alignment: SynthesisAlignment
    ) -> (low: Double, high: Double) {
        switch alignment {
        case .butterworth:
            let power = pow(ratio, Double(2 * order))
            return (1 / sqrt(1 + power), sqrt(power / (1 + power)))
        case .linkwitzRiley:
            let power = pow(ratio, Double(order))
            return (1 / (1 + power), power / (1 + power))
        }
    }

    private static func resample(_ samples: [ACImpedanceSample], at frequencies: [Double]) throws -> [ACImpedanceSample] {
        let model = ACImpedanceModel.tabulated(samples)
        return try frequencies.map { .init(frequencyHz: $0, impedance: try model.impedance(at: $0)) }
    }

    private static func nominalResistance(_ samples: [ACImpedanceSample]) -> Double {
        let middle = samples[samples.count / 2].impedance.magnitude
        return min(max(middle, 1), 64)
    }

    private static func parallelMagnitude(_ lhs: ACComplex, _ rhs: ACComplex) -> Double {
        ((lhs * rhs) / (lhs + rhs)).magnitude
    }

    private static func db(_ value: Double) -> Double { 20 * log10(max(value, 1e-9)) }

    private static func logFrequencies(start: Double, stop: Double, pointsPerOctave: Int) -> [Double] {
        (try? NumericalGrid.logarithmic(
            from: start, through: stop, pointsPerOctave: pointsPerOctave
        )) ?? []
    }

    private static func validate(_ request: CrossoverSynthesisRequest) throws {
        guard request.crossoverFrequencyHz.isFinite, request.crossoverFrequencyHz > 0,
              (1...4).contains(request.order), request.pointsPerOctave >= 2,
              request.minimumInputImpedanceOhms.isFinite, request.minimumInputImpedanceOhms > 0,
              request.alignment != .linkwitzRiley || request.order == 2 || request.order == 4,
              request.lowPassLoad.count >= 2, request.highPassLoad.count >= 2 else {
            throw CrossoverSynthesisError.invalidRequest("frequency, order, alignment, impedance floor, or load table")
        }
        let lower = request.crossoverFrequencyHz / 4
        let upper = request.crossoverFrequencyHz * 4
        guard request.lowPassLoad.first!.frequencyHz <= lower,
              request.highPassLoad.first!.frequencyHz <= lower,
              request.lowPassLoad.last!.frequencyHz >= upper,
              request.highPassLoad.last!.frequencyHz >= upper else {
            throw CrossoverSynthesisError.invalidRequest("load tables must cover two octaves around crossover")
        }
    }
}
