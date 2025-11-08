import Testing
@testable import SmartVestor

@Suite("Unicode Width Tests")
struct UnicodeWidthTests {
    @Test
    func cjk() {
        assertWidth("你好", expected: 4)
    }

    @Test
    func emoji_zwj_family() {
        assertWidth("👨‍👩‍👧‍👦", expected: 2)
    }

    @Test
    func flag() {
        assertWidth("🇺🇸", expected: 2)
    }

    @Test
    func combining_marks() {
        assertWidth("e\u{0301}", expected: 1)
    }

    @Test
    func emoji_skin_tone() {
        assertWidth("👋🏻", expected: 2)
    }

    @Test
    func mixed_cjk_ascii() {
        assertWidth("Hello 世界", expected: 12)
    }

    @Test
    func zero_width_joiner_sequence() {
        assertWidth("👨‍👩‍👧‍👦", expected: 2)
    }

    private func assertWidth(_ s: String, expected: Int) {
        let component = TextComponent(text: s)
        let measured = component.measure(in: Size(width: 1000, height: 100))
        #expect(measured.width == expected, "String '\(s)' should have width \(expected)")
    }
}
