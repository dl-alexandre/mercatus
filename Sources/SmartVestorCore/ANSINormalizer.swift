import Foundation

public enum ANSINormalizer {
    public static func strip(_ s: String) -> String {
        var result = s

        result = result.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"\u{001B}\][0-9;]*\u{0007}"#,
            with: "",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"\u{001B}\][0-9;]*\u{001B}\\"#,
            with: "",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"\u{001B}P[^\u{001B}]*(\u{001B}\\)?"#,
            with: "",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"\u{009B}[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"\u{001B}"#,
            with: "",
            options: .regularExpression
        )

        return result
    }

    public static func normalize(_ s: String) -> String {
        strip(s)
    }
}
