import Testing
import Foundation
@testable import SmartVestor

@Suite("Sparkline Renderer Tests")
struct SparklineRendererTests {

    @Test("SparklineRenderer should generate empty string for empty values")
    func testEmptyValues() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let result = renderer.render(values: [], width: 10)
        #expect(result.isEmpty)
    }

    @Test("SparklineRenderer should generate empty string for zero width")
    func testZeroWidth() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let result = renderer.render(values: [1.0, 2.0, 3.0], width: 0)
        #expect(result.isEmpty)
    }

    @Test("SparklineRenderer should render single value")
    func testSingleValue() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let result = renderer.render(values: [5.0], width: 5)
        #expect(result.count == 5)
        let allSame = result.allSatisfy { $0 == result.first }
        #expect(allSame)
    }

    @Test("SparklineRenderer should use Unicode characters when Unicode is supported")
    func testUnicodeCharacters() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]
        let result = renderer.render(values: values, width: 5)

        #expect(result.count == 5)
        let unicodeChars: Set<Character> = Set(["▂", "▅", "▇", "▆", "▃"])
        for char in result {
            #expect(unicodeChars.contains(char))
        }
    }

    @Test("SparklineRenderer should use ASCII characters when Unicode is not supported")
    func testASCIICharacters() {
        let renderer = SparklineRenderer(unicodeSupported: false)
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]
        let result = renderer.render(values: values, width: 5)

        #expect(result.count == 5)
        let asciiChars: Set<Character> = Set(["_", ".", "-", "=", "#"])
        for char in result {
            #expect(asciiChars.contains(char))
        }
    }

    @Test("SparklineRenderer should normalize values correctly")
    func testValueNormalization() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [10.0, 20.0, 30.0, 40.0, 50.0]
        let result = renderer.render(values: values, width: 5)

        #expect(result.count == 5)
        let firstChar = result.first!
        let lastChar = result.last!
        #expect(firstChar != lastChar)
    }

    @Test("SparklineRenderer should handle constant values")
    func testConstantValues() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [5.0, 5.0, 5.0, 5.0, 5.0]
        let result = renderer.render(values: values, width: 5)

        #expect(result.count == 5)
        let allSame = result.allSatisfy { $0 == result.first }
        #expect(allSame)
    }

    @Test("SparklineRenderer should sample large datasets correctly")
    func testSamplingLargeDataset() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = Array(stride(from: 1.0, through: 100.0, by: 1.0))
        let result = renderer.render(values: values, width: 10)

        #expect(result.count == 10)
    }

    @Test("SparklineRenderer should handle small datasets correctly")
    func testSmallDataset() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [1.0, 2.0]
        let result = renderer.render(values: values, width: 10)

        #expect(result.count == 10)
    }

    @Test("SparklineRenderer should respect width parameter")
    func testWidthParameter() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = Array(stride(from: 1.0, through: 50.0, by: 1.0))

        let result5 = renderer.render(values: values, width: 5)
        #expect(result5.count == 5)

        let result20 = renderer.render(values: values, width: 20)
        #expect(result20.count == 20)

        let result1 = renderer.render(values: values, width: 1)
        #expect(result1.count == 1)
    }

    @Test("SparklineRenderer should respect height range parameters")
    func testHeightRangeParameters() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]

        let resultMin1Max4 = renderer.render(values: values, width: 5, minHeight: 1, maxHeight: 4)
        #expect(resultMin1Max4.count == 5)

        let resultMin2Max5 = renderer.render(values: values, width: 5, minHeight: 2, maxHeight: 5)
        #expect(resultMin2Max5.count == 5)
    }

    @Test("SparklineRenderer should handle negative values")
    func testNegativeValues() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [-10.0, -5.0, 0.0, 5.0, 10.0]
        let result = renderer.render(values: values, width: 5)

        #expect(result.count == 5)
        let firstChar = result.first!
        let lastChar = result.last!
        #expect(firstChar != lastChar)
    }

    @Test("SparklineRenderer should interpolate values correctly")
    func testValueInterpolation() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [1.0, 10.0]
        let result = renderer.render(values: values, width: 10)

        #expect(result.count == 10)

        let firstLevel = getCharacterLevel(result.first!)
        let lastLevel = getCharacterLevel(result.last!)
        #expect(firstLevel < lastLevel)
    }

    @Test("SparklineRenderer should handle edge case with one data point and large width")
    func testOneDataPointLargeWidth() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [42.0]
        let result = renderer.render(values: values, width: 100)

        #expect(result.count == 100)
        let allSame = result.allSatisfy { $0 == result.first }
        #expect(allSame)
    }

    @Test("SparklineRenderer should produce consistent output for same input")
    func testConsistentOutput() {
        let renderer = SparklineRenderer(unicodeSupported: true)
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]

        let result1 = renderer.render(values: values, width: 10)
        let result2 = renderer.render(values: values, width: 10)

        #expect(result1 == result2)
    }

    private func getCharacterLevel(_ char: Character) -> Int {
        let unicodeLevels: [Character: Int] = ["▂": 1, "▅": 2, "▇": 3, "▆": 2, "▃": 1]
        return unicodeLevels[char] ?? 0
    }
}
