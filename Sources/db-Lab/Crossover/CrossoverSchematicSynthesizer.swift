import Foundation
import DBLabSynthesis

struct SynthesizedSchematic {
    let symbols: [SymbolInstance]
    let wires: [WireSegment]
    let inputReference: PinRef
    let wooferOutputReference: PinRef
    let tweeterOutputReference: PinRef
}

enum CrossoverSchematicSynthesizer {
    static func makeSchematic(from result: CrossoverSynthesisResult) -> SynthesizedSchematic {
        var symbols: [SymbolInstance] = []
        var wires: [WireSegment] = []
        var inductorIndex = 1
        var capacitorIndex = 1
        let inputX = -2
        let groundY = 20
        var maximumX = inputX

        func makeBranch(_ branch: SynthesizedBranch, y: Int) -> (input: PinRef, output: PinRef) {
            var nodeX = inputX
            var input: PinRef?
            var output: PinRef?
            for component in branch.components {
                let isSeries: Bool
                let descriptor: String
                let parameter: String
                let reference: String
                switch component.kind {
                case .seriesInductor:
                    isSeries = true; descriptor = "inductor"; parameter = "inductance"
                    reference = "L\(inductorIndex)"; inductorIndex += 1
                case .shuntInductor:
                    isSeries = false; descriptor = "inductor"; parameter = "inductance"
                    reference = "L\(inductorIndex)"; inductorIndex += 1
                case .seriesCapacitor:
                    isSeries = true; descriptor = "capacitor"; parameter = "capacitance"
                    reference = "C\(capacitorIndex)"; capacitorIndex += 1
                case .shuntCapacitor:
                    isSeries = false; descriptor = "capacitor"; parameter = "capacitance"
                    reference = "C\(capacitorIndex)"; capacitorIndex += 1
                }
                if isSeries {
                    let symbol = SymbolInstance(
                        descriptorId: descriptor, refDes: reference,
                        position: GridPoint(nodeX + 2, y), parameters: [parameter: component.value]
                    )
                    symbols.append(symbol)
                    let first = PinRef(symbolId: symbol.id, pinId: "1")
                    let second = PinRef(symbolId: symbol.id, pinId: "2")
                    input = input ?? first
                    output = second
                    nodeX += 4
                    maximumX = max(maximumX, nodeX)
                } else {
                    let symbol = SymbolInstance(
                        descriptorId: descriptor, refDes: reference,
                        position: GridPoint(nodeX, y + 2), rotation: 90,
                        parameters: [parameter: component.value]
                    )
                    symbols.append(symbol)
                    let signalPin = PinRef(symbolId: symbol.id, pinId: "1")
                    output = signalPin
                    wires.append(WireSegment(points: [GridPoint(nodeX, y + 4), GridPoint(nodeX, groundY)]))
                }
            }
            return (input!, output!)
        }

        let low = makeBranch(result.lowPass, y: 0)
        let high = makeBranch(result.highPass, y: 10)
        wires.append(WireSegment(points: [GridPoint(inputX, 0), GridPoint(inputX, 10)]))
        let ground = SymbolInstance(descriptorId: "ground", refDes: "GND1", position: GridPoint(-6, 21))
        symbols.append(ground)
        wires.append(WireSegment(points: [GridPoint(-6, groundY), GridPoint(maximumX, groundY)]))
        return SynthesizedSchematic(
            symbols: symbols, wires: wires,
            inputReference: low.input,
            wooferOutputReference: low.output,
            tweeterOutputReference: high.output
        )
    }
}
