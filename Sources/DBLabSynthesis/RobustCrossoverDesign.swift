import Foundation
import DBLabNumeric
import NumericCore

public struct RobustDesignOptions: Sendable, Hashable, Codable {
    public var componentTolerancePercent: Double
    public var loadMagnitudeTolerancePercent: Double
    public var loadPhaseToleranceDegrees: Double
    public var allowedMagnitudeErrorDecibels: Double
    public var sampleCount: Int
    public var seed: UInt64

    public init(
        componentTolerancePercent: Double = 5,
        loadMagnitudeTolerancePercent: Double = 5,
        loadPhaseToleranceDegrees: Double = 3,
        allowedMagnitudeErrorDecibels: Double = 2,
        sampleCount: Int = 200,
        seed: UInt64 = 0xDB1AB2026
    ) {
        self.componentTolerancePercent = componentTolerancePercent
        self.loadMagnitudeTolerancePercent = loadMagnitudeTolerancePercent
        self.loadPhaseToleranceDegrees = loadPhaseToleranceDegrees
        self.allowedMagnitudeErrorDecibels = allowedMagnitudeErrorDecibels
        self.sampleCount = sampleCount
        self.seed = seed
    }
}

public struct RobustResponseEnvelopePoint: Sendable, Hashable, Codable {
    public let frequencyHz: Double
    public let lowPassP05Decibels: Double
    public let lowPassMedianDecibels: Double
    public let lowPassP95Decibels: Double
    public let highPassP05Decibels: Double
    public let highPassMedianDecibels: Double
    public let highPassP95Decibels: Double
    public let minimumInputImpedanceOhms: Double
}

public struct ComponentSensitivity: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let componentID: String
    public let band: SynthesisBand
    public let worstCaseMagnitudeShiftDecibels: Double
}

public struct RobustDesignResult: Sendable, Hashable {
    public let recommendedDesign: CrossoverSynthesisResult
    public let envelope: [RobustResponseEnvelopePoint]
    public let yieldPercent: Double
    public let worstCaseMagnitudeErrorDecibels: Double
    public let worstCaseMinimumImpedanceOhms: Double
    public let sensitivities: [ComponentSensitivity]
    public let sampleCount: Int
    public let seed: UInt64
    public let changedComponentCount: Int
    public let backendIdentifier: String
}

public enum RobustCrossoverDesigner {
    public static func analyzeAndRefine(
        request: CrossoverSynthesisRequest,
        nominal: CrossoverSynthesisResult,
        options: RobustDesignOptions = .init()
    ) throws -> RobustDesignResult {
        try validate(options)
        let frequencies = nominal.response.map(\.frequencyHz)
        let lowLoad = try resample(request.lowPassLoad, frequencies)
        let highLoad = try resample(request.highPassLoad, frequencies)
        let lowCount = nominal.lowPass.components.count
        let original = (nominal.lowPass.components + nominal.highPass.components).map(\.value)
        let tolerance = options.componentTolerancePercent / 100

        func evaluate(
            _ values: [Double], lowLoad: [ACImpedanceSample], highLoad: [ACImpedanceSample]
        ) throws -> (points: [SynthesisResponsePoint], score: Double, maxError: Double, minimumZ: Double) {
            let low = try PassiveCrossoverSynthesizer.branchResponse(
                band: .lowPass, components: Array(values[..<lowCount]),
                load: lowLoad, frequencies: frequencies
            )
            let high = try PassiveCrossoverSynthesizer.branchResponse(
                band: .highPass, components: Array(values[lowCount...]),
                load: highLoad, frequencies: frequencies
            )
            var maxError = 0.0
            var score = 0.0
            let points = zip(zip(frequencies, low), high).map { pair, highPoint in
                let (frequency, lowPoint) = pair
                let target = PassiveCrossoverSynthesizer.targetMagnitudes(
                    frequency / request.crossoverFrequencyHz,
                    order: request.order, alignment: request.alignment
                )
                let lowError = abs(db(lowPoint.outputMagnitude) - db(target.low))
                let highError = abs(db(highPoint.outputMagnitude) - db(target.high))
                maxError = max(maxError, lowError, highError)
                score += lowError * lowError + highError * highError
                return SynthesisResponsePoint(
                    frequencyHz: frequency,
                    lowPassMagnitude: lowPoint.outputMagnitude,
                    highPassMagnitude: highPoint.outputMagnitude,
                    targetLowPassMagnitude: target.low,
                    targetHighPassMagnitude: target.high,
                    systemInputImpedanceOhms: parallelMagnitude(lowPoint.inputImpedance, highPoint.inputImpedance)
                )
            }
            let minimumZ = points.map(\.systemInputImpedanceOhms).min() ?? 0
            let impedanceDeficit = max(0, request.minimumInputImpedanceOhms - minimumZ)
            score = score / Double(points.count * 2) + 25 * impedanceDeficit * impedanceDeficit
            return (points, score, maxError, minimumZ)
        }

        // Discrete coordinate search over adjacent preferred values. Each
        // candidate is scored at nominal and at coordinated tolerance
        // corners, which avoids a fragile nominal optimum without exploding
        // into a full combinatorial enumeration.
        func robustScore(_ values: [Double]) throws -> Double {
            var worst = try evaluate(values, lowLoad: lowLoad, highLoad: highLoad).score
            let corners = [
                values.map { $0 * (1 - tolerance) },
                values.map { $0 * (1 + tolerance) },
                values.enumerated().map { $0.offset.isMultiple(of: 2) ? $0.element * (1 - tolerance) : $0.element * (1 + tolerance) },
                values.enumerated().map { $0.offset.isMultiple(of: 2) ? $0.element * (1 + tolerance) : $0.element * (1 - tolerance) },
            ]
            for corner in corners {
                worst = max(worst, try evaluate(corner, lowLoad: lowLoad, highLoad: highLoad).score)
            }
            return worst
        }
        var recommended = original
        for _ in 0..<2 {
            var changed = false
            for index in recommended.indices {
                let neighbors = preferredNeighbors(recommended[index])
                let choice = try neighbors.min { try robustScore(replacing(recommended, index, $0))
                    < robustScore(replacing(recommended, index, $1)) }!
                if choice != recommended[index] { recommended[index] = choice; changed = true }
            }
            if !changed { break }
        }

        var generator = SplitMix64Generator(seed: options.seed)
        var lowDB = [[Double]](repeating: [], count: frequencies.count)
        var highDB = [[Double]](repeating: [], count: frequencies.count)
        var impedanceByFrequency = [[Double]](repeating: [], count: frequencies.count)
        var minimumImpedances = [Double]()
        var passing = 0
        var worstError = 0.0
        for sample in 0..<options.sampleCount {
            try Task.checkCancellation()
            let values = try recommended.enumerated().map { index, value in
                let u = try StratifiedSampling.unitInterval(
                    sample: sample, count: options.sampleCount, dimension: index,
                    generator: &generator
                )
                return value * (1 + tolerance * (2 * u - 1))
            }
            let perturbedLow = try perturbLoad(lowLoad, sample: sample, dimension: values.count, options: options, generator: &generator)
            let perturbedHigh = try perturbLoad(highLoad, sample: sample, dimension: values.count + 2, options: options, generator: &generator)
            let run = try evaluate(values, lowLoad: perturbedLow, highLoad: perturbedHigh)
            for (index, point) in run.points.enumerated() {
                lowDB[index].append(db(point.lowPassMagnitude))
                highDB[index].append(db(point.highPassMagnitude))
                impedanceByFrequency[index].append(point.systemInputImpedanceOhms)
            }
            minimumImpedances.append(run.minimumZ)
            worstError = max(worstError, run.maxError)
            if run.maxError <= options.allowedMagnitudeErrorDecibels,
               run.minimumZ >= request.minimumInputImpedanceOhms { passing += 1 }
        }

        let envelope = try frequencies.indices.map { index in
            let low = lowDB[index]
            let high = highDB[index]
            return RobustResponseEnvelopePoint(
                frequencyHz: frequencies[index],
                lowPassP05Decibels: try DescriptiveStatistics.quantile(low, probability: 0.05),
                lowPassMedianDecibels: try DescriptiveStatistics.quantile(low, probability: 0.5),
                lowPassP95Decibels: try DescriptiveStatistics.quantile(low, probability: 0.95),
                highPassP05Decibels: try DescriptiveStatistics.quantile(high, probability: 0.05),
                highPassMedianDecibels: try DescriptiveStatistics.quantile(high, probability: 0.5),
                highPassP95Decibels: try DescriptiveStatistics.quantile(high, probability: 0.95),
                minimumInputImpedanceOhms: impedanceByFrequency[index].min() ?? .nan
            )
        }
        let sensitivities = try sensitivity(
            values: recommended, lowCount: lowCount,
            nominal: nominal, tolerance: tolerance,
            lowLoad: lowLoad, highLoad: highLoad, evaluate: evaluate
        )
        let finalRun = try evaluate(recommended, lowLoad: lowLoad, highLoad: highLoad)
        let recommendedDesign = replacementDesign(
            nominal, values: recommended, lowCount: lowCount,
            response: finalRun.points, objective: finalRun.score
        )
        return RobustDesignResult(
            recommendedDesign: recommendedDesign,
            envelope: envelope,
            yieldPercent: 100 * Double(passing) / Double(options.sampleCount),
            worstCaseMagnitudeErrorDecibels: worstError,
            worstCaseMinimumImpedanceOhms: minimumImpedances.min() ?? .nan,
            sensitivities: sensitivities.sorted { $0.worstCaseMagnitudeShiftDecibels > $1.worstCaseMagnitudeShiftDecibels },
            sampleCount: options.sampleCount,
            seed: options.seed,
            changedComponentCount: zip(original, recommended).filter(!=).count,
            backendIdentifier: "numeric-core-sparse-ac+deterministic-stratified"
        )
    }

    private static func sensitivity(
        values: [Double], lowCount: Int, nominal: CrossoverSynthesisResult,
        tolerance: Double, lowLoad: [ACImpedanceSample], highLoad: [ACImpedanceSample],
        evaluate: ([Double], [ACImpedanceSample], [ACImpedanceSample]) throws -> (points: [SynthesisResponsePoint], score: Double, maxError: Double, minimumZ: Double)
    ) throws -> [ComponentSensitivity] {
        let components = nominal.lowPass.components + nominal.highPass.components
        return try values.indices.map { index in
            let low = try evaluate(replacing(values, index, values[index] * (1 - tolerance)), lowLoad, highLoad)
            let high = try evaluate(replacing(values, index, values[index] * (1 + tolerance)), lowLoad, highLoad)
            var shift = 0.0
            for frequencyIndex in low.points.indices {
                shift = max(
                    shift,
                    abs(db(low.points[frequencyIndex].lowPassMagnitude) - db(high.points[frequencyIndex].lowPassMagnitude)),
                    abs(db(low.points[frequencyIndex].highPassMagnitude) - db(high.points[frequencyIndex].highPassMagnitude))
                )
            }
            return ComponentSensitivity(
                id: components[index].id, componentID: components[index].id,
                band: index < lowCount ? .lowPass : .highPass,
                worstCaseMagnitudeShiftDecibels: shift
            )
        }
    }

    private static func replacementDesign(
        _ nominal: CrossoverSynthesisResult, values: [Double], lowCount: Int,
        response: [SynthesisResponsePoint], objective: Double
    ) -> CrossoverSynthesisResult {
        func branch(_ source: SynthesizedBranch, offset: Int) -> SynthesizedBranch {
            .init(band: source.band, components: source.components.enumerated().map { index, component in
                .init(
                    id: component.id, kind: component.kind, value: values[offset + index],
                    continuousOptimizedValue: component.continuousOptimizedValue,
                    initialValue: component.initialValue
                )
            })
        }
        let squared = response.reduce(0.0) {
            $0 + pow(db($1.lowPassMagnitude) - db($1.targetLowPassMagnitude), 2)
                + pow(db($1.highPassMagnitude) - db($1.targetHighPassMagnitude), 2)
        }
        return .init(
            lowPass: branch(nominal.lowPass, offset: 0),
            highPass: branch(nominal.highPass, offset: lowCount),
            response: response,
            rmsMagnitudeErrorDecibels: sqrt(squared / Double(response.count * 2)),
            minimumInputImpedanceOhms: response.map(\.systemInputImpedanceOhms).min() ?? .nan,
            objective: objective, iterations: nominal.iterations, evaluations: nominal.evaluations,
            termination: nominal.termination,
            backendIdentifier: nominal.backendIdentifier + "+robust-e24",
            preferredValueSeries: nominal.preferredValueSeries
        )
    }

    private static func perturbLoad(
        _ samples: [ACImpedanceSample], sample: Int, dimension: Int,
        options: RobustDesignOptions, generator: inout SplitMix64Generator
    ) throws -> [ACImpedanceSample] {
        let magnitudeU = try StratifiedSampling.unitInterval(
            sample: sample, count: options.sampleCount, dimension: dimension, generator: &generator
        )
        let phaseU = try StratifiedSampling.unitInterval(
            sample: sample, count: options.sampleCount, dimension: dimension + 1, generator: &generator
        )
        let magnitudeFactor = 1 + options.loadMagnitudeTolerancePercent / 100 * (2 * magnitudeU - 1)
        let phaseDelta = options.loadPhaseToleranceDegrees * .pi / 180 * (2 * phaseU - 1)
        return samples.map {
            .init(
                frequencyHz: $0.frequencyHz,
                impedance: .polar(
                    magnitude: $0.impedance.magnitude * magnitudeFactor,
                    phaseRadians: $0.impedance.phaseRadians + phaseDelta
                )
            )
        }
    }

    private static func resample(_ samples: [ACImpedanceSample], _ frequencies: [Double]) throws -> [ACImpedanceSample] {
        let model = ACImpedanceModel.tabulated(samples)
        return try frequencies.map { .init(frequencyHz: $0, impedance: try model.impedance(at: $0)) }
    }

    private static func preferredNeighbors(_ value: Double) -> [Double] {
        let e24 = [1.0, 1.1, 1.2, 1.3, 1.5, 1.6, 1.8, 2.0, 2.2, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.3, 4.7, 5.1, 5.6, 6.2, 6.8, 7.5, 8.2, 9.1]
        let decade = pow(10, floor(log10(value)))
        let candidates = ([e24.last! / 10] + e24 + [10, 11]).map { $0 * decade }.sorted()
        let closest = candidates.indices.min { abs(candidates[$0] - value) < abs(candidates[$1] - value) }!
        return Array(Set([
            candidates[max(0, closest - 1)], candidates[closest],
            candidates[min(candidates.count - 1, closest + 1)],
        ])).sorted()
    }

    private static func replacing(_ values: [Double], _ index: Int, _ value: Double) -> [Double] {
        var result = values; result[index] = value; return result
    }

    private static func parallelMagnitude(_ lhs: ACComplex, _ rhs: ACComplex) -> Double {
        ((lhs * rhs) / (lhs + rhs)).magnitude
    }

    private static func db(_ value: Double) -> Double { 20 * log10(max(value, 1e-9)) }

    private static func validate(_ options: RobustDesignOptions) throws {
        guard options.componentTolerancePercent.isFinite, (0...25).contains(options.componentTolerancePercent),
              options.loadMagnitudeTolerancePercent.isFinite, (0...25).contains(options.loadMagnitudeTolerancePercent),
              options.loadPhaseToleranceDegrees.isFinite, (0...45).contains(options.loadPhaseToleranceDegrees),
              options.allowedMagnitudeErrorDecibels.isFinite, options.allowedMagnitudeErrorDecibels > 0,
              (20...2_000).contains(options.sampleCount) else {
            throw CrossoverSynthesisError.invalidRequest("robust-design tolerances or sample count")
        }
    }
}
