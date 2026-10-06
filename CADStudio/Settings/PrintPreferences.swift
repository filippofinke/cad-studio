import SwiftUI

enum MeasurementUnit: String, CaseIterable {
    case millimeters
    case centimeters
    case meters
    case inches

    static var regionDefault: MeasurementUnit {
        Locale.current.measurementSystem == .us ? .inches : .millimeters
    }

    var title: LocalizedStringKey {
        switch self {
        case .millimeters: "Millimetri (mm)"
        case .centimeters: "Centimetri (cm)"
        case .meters: "Metri (m)"
        case .inches: "Pollici (in)"
        }
    }

    var symbol: String {
        switch self {
        case .millimeters: "mm"
        case .centimeters: "cm"
        case .meters: "m"
        case .inches: "in"
        }
    }

    var millimetersPerUnit: Float {
        switch self {
        case .millimeters: 1
        case .centimeters: 10
        case .meters: 1000
        case .inches: 25.4
        }
    }

    var fractionDigits: Int {
        switch self {
        case .millimeters: 1
        case .centimeters, .inches: 2
        case .meters: 3
        }
    }

    var promptName: String {
        switch self {
        case .millimeters: "millimeters (mm)"
        case .centimeters: "centimeters (cm)"
        case .meters: "meters (m)"
        case .inches: "inches (in)"
        }
    }
}

enum PrinterType: String, CaseIterable {
    case fdm
    case fdmMultiMaterial
    case resin
    case sls

    var title: LocalizedStringKey {
        switch self {
        case .fdm: "FDM (filamento)"
        case .fdmMultiMaterial: "FDM multimateriale (AMS, MMU)"
        case .resin: "Resina (SLA, DLP, MSLA)"
        case .sls: "SLS (polvere)"
        }
    }

    var promptGuidelines: String {
        switch self {
        case .fdm:
            """
            Single-filament FDM. Unless told otherwise: walls ≥ 1.2 mm, fit \
            clearance 0.2 mm, overhangs ≤ 45°, short bridges, fillets or chamfers \
            on sharp edges where they do not affect function, a flat base for bed \
            adhesion, teardrop or controlled-overhang horizontal holes. Multiple \
            colors need manual filament changes.
            """
        case .fdmMultiMaterial:
            """
            Multi-material FDM (AMS, MMU): several colors or materials are \
            possible, one per 3MF part. Unless told otherwise: walls ≥ 1.2 mm, fit \
            clearance 0.2 mm, overhangs ≤ 45°, fillets or chamfers on sharp edges, \
            a flat base for bed adhesion. Keep color changes per layer low when \
            possible.
            """
        case .resin:
            """
            Resin printing (SLA, DLP, MSLA). Unless told otherwise: walls ≥ 0.8 mm \
            (≥ 1.5 mm for load-bearing parts), fit clearance 0.1-0.15 mm, fine \
            details down to 0.2 mm, hollow parts with drain holes ≥ 3 mm, avoid \
            large flat areas parallel to the plate, plan for a tilted orientation \
            and supports. The build volume is usually small: flag large parts.
            """
        case .sls:
            """
            SLS powder printing: no supports needed and overhangs are free. Unless \
            told otherwise: walls ≥ 0.8 mm, fit clearance 0.3-0.5 mm, closed \
            cavities with powder escape holes ≥ 5 mm, avoid strongly varying \
            thicknesses that warp. Colors cannot be printed: use them only to tell \
            parts apart.
            """
        }
    }
}

struct PrintPreferencesSection: View {
    @AppStorage(AppSettings.printerTypeKey) private var printerType = PrinterType.fdm.rawValue
    @AppStorage(AppSettings.printerModelKey) private var printerModel = ""
    @AppStorage(AppSettings.measurementUnitKey) private var unit = MeasurementUnit.regionDefault.rawValue

    var body: some View {
        Section {
            Picker("Tipo di stampante:", selection: $printerType) {
                ForEach(PrinterType.allCases, id: \.self) { type in
                    Text(type.title).tag(type.rawValue)
                }
            }
            TextField("Modello:", text: $printerModel, prompt: Text("Facoltativo, ad esempio Bambu Lab P1S"))
            Picker("Unità di misura:", selection: $unit) {
                ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                    Text(unit.title).tag(unit.rawValue)
                }
            }
        } footer: {
            Text("L’agente adatta spessori, giochi e consigli di stampa alla tua stampante e usa l’unità scelta nelle risposte e nella tavola. I file STL e 3MF restano sempre in millimetri.")
                .foregroundStyle(.secondary)
        }
    }
}
