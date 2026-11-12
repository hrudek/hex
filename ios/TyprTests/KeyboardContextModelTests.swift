import Foundation
import XCTest
@testable import Typr

final class KeyboardContextModelTests: XCTestCase {
    nonisolated static let model: KeyboardContextModel? = {
        let packs = ["de", "en"].map { lang in
            Bundle.main.url(forResource: "keyboard-\(lang)", withExtension: "tbg", subdirectory: "WordData")
                .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }.flatMap(KeyboardContextModel.Pack.init)
        }
        return KeyboardContextModel(de: packs[0], en: packs[1])
    }()

    func testAllD3bReferenceVectors() throws {
        let model = try XCTUnwrap(Self.model)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "swift-reference-vectors", withExtension: "json", subdirectory: "WordData"))
        let spec = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        XCTAssertEqual(model.unionSize, spec.union_size)
        var state = KeyboardContextModel.State(), sequence: [String] = []
        for v in spec.vectors {
            if v.sequence != sequence { state = .init(); sequence = v.sequence }
            if let word = v.consumed {
                XCTAssertEqual(model.evidence(word), try XCTUnwrap(v.evidence), accuracy: 1e-12)
                state.consume(word, model: model)
            } else { state.sentenceBoundary() }
            XCTAssertEqual(state.value, v.state, accuracy: 1e-12)
            XCTAssertEqual(state.weightDE, v.weight_de, accuracy: 1e-12)
            for (suppress, expected) in [(Set<String>(), v.top3), (KeyboardContextModel.suppressed, v.top3_suppressed)] {
                let got = model.suggestions(after: v.context, weightDE: state.weightDE, suppress: suppress)
                XCTAssertEqual(got.map(\.key), expected.map(\.key), "\(v.sequence), \(v.context)")
                for (a, b) in zip(got, expected) { XCTAssertEqual(a.probability, b.probability, accuracy: 1e-12) }
            }
        }
        print("EVAL context_reference vectors=\(spec.vectors.count) tolerance=1e-12 union=\(model.unionSize)")
    }

    func testCorruptTruncatedAndHostileFormat() throws {
        let data = try XCTUnwrap(Self.model?.de?.data)
        for length in [0, 1, 63, 64, 65, data.count - 1] {
            XCTAssertNil(KeyboardContextModel.Pack(data: Data(data.prefix(length))))
        }
        // Header counts, offsets, flags, discount, checksum and reserved fields.
        for offset in [0, 4, 6, 8, 10, 12, 16, 20, 24, 28, 32, 36, 44, 48, 52, 54, 56, 60] {
            var bad = data; bad[offset] ^= 0xff
            XCTAssertNil(KeyboardContextModel.Pack(data: bad), "header \(offset)")
        }
        // Repair CRC to reach the structural validator, not just the integrity check.
        for (offset, value) in [(64, UInt8(255)), (64 + 12, 1), (64 + 20 + 8, 0),
                                (try XCTUnwrap(Self.model?.de?.edgeOffset) + 1, 255),
                                (try XCTUnwrap(Self.model?.de?.edgeOffset) + 2, 1),
                                (try XCTUnwrap(Self.model?.de?.stringOffset), 255)] {
            var bad = data; bad[offset] = value
            repairCRC(&bad)
            XCTAssertFalse(KeyboardContextModel.Pack(data: bad) != nil, "record \(offset)")
        }
        XCTAssertNil(KeyboardContextModel.Pack(data: Data(repeating: 0, count: 1_048_577)))
    }

    func testNormalizedBackoffAndSingleLanguageSelection() throws {
        let model = try XCTUnwrap(Self.model), de = try XCTUnwrap(model.de), en = try XCTUnwrap(model.en)
        for pack in [de, en] {
            for h: String? in [nil, "unseenxyz", "<s>", "ich", "i", "tom"] {
                let distribution = pack.distribution(h)
                let sum = (1..<pack.wordCount).reduce(0.0) { $0 + pack.probability(pack.word($1), distribution: distribution) }
                XCTAssertEqual(sum, 1, accuracy: 1e-12)
            }
        }
        XCTAssertEqual(de.probability("ich", after: nil), de.probability("ich", after: "unseenxyz"))
        XCTAssertNotEqual(de.probability("ich", after: nil), de.probability("ich", after: "<s>"))
        XCTAssertEqual(KeyboardContextModel.key("STRAẞE"), "straße")
        XCTAssertEqual(KeyboardContextModel.key("A\u{308}PFEL"), "äpfel")
        XCTAssertNotEqual(KeyboardContextModel.key("Maße"), KeyboardContextModel.key("Masse"))
        let single = try XCTUnwrap(KeyboardContextModel(de: de, en: nil))
        XCTAssertTrue(single.suggestions(after: "ich", weightDE: 0.5).isEmpty)
        XCTAssertEqual(single.suggestions(after: "ich", weightDE: 0, german: true, english: false),
                       model.suggestions(after: "ich", weightDE: 1, german: true, english: false))
        XCTAssertTrue(model.suggestions(after: "ich", weightDE: 0.5, german: false, english: false).isEmpty)
        for weight in [0.0, 0.05, 0.5, 0.95, 1.0] {
            XCTAssertEqual(model.suggestions(after: "tom", weightDE: weight).count, 3)
        }
    }

    func testSuffixRetokenizationBarriersAndReset() throws {
        let model = try XCTUnwrap(Self.model)
        let c = model.context(before: "ich habe ein meeting morgen ", currentToken: nil)
        var state = KeyboardContextModel.State()
        for w in ["ich", "habe", "ein", "meeting", "morgen"] { state.consume(w, model: model) }
        XCTAssertEqual(c.state.value, state.value)
        XCTAssertEqual(c.previous, "morgen")
        XCTAssertEqual(model.context(before: "ich habe ein meeting mor", currentToken: "mor").previous, "meeting")
        XCTAssertEqual(model.context(before: "ich habe. ", currentToken: nil).previous, "<s>")
        XCTAssertEqual(model.context(before: "ich habe...!? ", currentToken: nil).state.value,
                       model.context(before: "ich habe. ", currentToken: nil).state.value)
        for input: String? in [nil, "", "   ", "123 ", "ich 123 ", "https://example.com ", "x@y.com ", "camel_case "] {
            XCTAssertFalse(model.context(before: input, currentToken: nil).canPredict, "\(input ?? "nil")")
        }
        let long = String(repeating: "english ", count: 1000) + "ich habe "
        XCTAssertEqual(model.context(before: long, currentToken: nil).previous, "habe")
        XCTAssertEqual(model.context(before: nil, currentToken: nil).state.value, 0)
        XCTAssertEqual(model.context(before: "ich habe ", currentToken: nil).state.value,
                       model.context(before: "ich habe ", currentToken: nil).state.value)
        let ranked = model.rerank(["glaube", "bin", "habe"], context: model.context(before: "ich ", currentToken: nil), german: true, english: false)
        XCTAssertEqual(ranked, ["bin", "habe", "glaube"])
        XCTAssertEqual(model.rerank(Array(repeating: "word", count: 100), context: c, german: true, english: true).count, 32)
    }

    private func repairCRC(_ data: inout Data) {
        var crc: UInt32 = 0xffffffff
        for b in data.dropFirst(64) {
            crc ^= UInt32(b)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
        }
        crc ^= 0xffffffff
        for i in 0..<4 { data[56 + i] = UInt8(truncatingIfNeeded: crc >> (8 * i)) }
    }

    private struct Vectors: Decodable {
        let union_size: Int
        let vectors: [Vector]
    }
    private struct Vector: Decodable {
        let sequence: [String]
        let consumed: String?
        let evidence: Double?
        let state: Double
        let weight_de: Double
        let context: String
        let top3: [Pair]
        let top3_suppressed: [Pair]
    }
    private struct Pair: Decodable {
        let key: String
        let probability: Double
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            key = try container.decode(String.self); probability = try container.decode(Double.self)
        }
    }
}
