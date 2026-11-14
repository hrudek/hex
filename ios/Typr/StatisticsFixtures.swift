import Foundation

/// Synthetic, in-memory presentation inputs. Never seed shared preferences or files.
enum StatisticsFixture: String {
    case empty, sparse, populated, unavailable

    static func launchFixture(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--snap-state"), index + 1 < arguments.count else { return nil }
        let prefix = "settings-statistics-"
        let scene = arguments[index + 1]
        guard scene.hasPrefix(prefix) else { return nil }
        return Self(rawValue: String(scene.dropFirst(prefix.count)))
    }

    @MainActor
    func snapshots() -> (UsageStatisticsSnapshot?, KeyboardLearningSnapshot?) {
        guard self != .unavailable else { return (nil, nil) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = UsageStatisticsSnapshot(now: date, timeZone: TimeZone(secondsFromGMT: 0)!)
        var state = PersonalTypingModel.State()
        if self != .empty {
            let layout = KeyboardLayout(width: 392)
            let signature = KeyboardLayoutSignature(layout)
            var keys: [String: PersonalTypingModel.TouchStats] = [:]
            for (index, letter) in "qwertyuiopasdfghjklzxcvbnm".enumerated() {
                if self == .sparse && letter != "a" { continue }
                keys[String(letter)] = .init(n: self == .sparse ? 3 : 64,
                    meanX: Double(index % 5 - 2) * 0.07, meanY: 0.08,
                    varianceX: 0.035, varianceY: 0.025, covarianceXY: 0.008)
            }
            state.layouts[signature.id] = .init(signature: signature, lastUpdated: date, keys: keys)
            var heat = UsageHeat(layout: signature, geometryVersion: 1,
                                 cells: Array(repeating: 0, count: UsageHeat.columns * UsageHeat.rows), updatedAt: date)
            for key in layout.keys where key.character != nil {
                guard self != .sparse || key.character == "a" else { continue }
                let x = Int(key.frame.midX / layout.width * CGFloat(UsageHeat.columns))
                let y = Int(key.frame.midY / layout.totalHeight * CGFloat(UsageHeat.rows))
                heat.cells[y * UsageHeat.columns + x] = self == .sparse ? 1 : 24
            }
            usage.heat = [heat]
        }
        let learning = KeyboardLearningSnapshot(model: PersonalTypingModel.summarize(state, physicalTouch: true),
            diagnostics: KeyboardDiagnostics(), learningFile: .init(bytes: nil, modifiedAt: nil),
            diagnosticsFile: .init(bytes: nil, modifiedAt: nil), isPersistent: true)
        return (usage, learning)
    }
}
