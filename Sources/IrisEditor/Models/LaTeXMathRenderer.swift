import Foundation

// MARK: - LaTeXMathRenderer

/// A deliberately tiny LaTeX → Unicode math renderer. The goal is *not* to compete with
/// MathJax or KaTeX; it is to turn common inline/display LaTeX into something readable
/// with zero third-party dependencies, so the preview still looks sane without a network
/// round-trip.
enum LaTeXMathRenderer {

    // MARK: - Public API

    static func render(_ latex: String) -> String {
        var s = latex

        // Remove leading/trailing $ delimiters someone may have left in.
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("$") { s.removeFirst() }
        if s.hasSuffix("$") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fractions \frac{a}{b} → a/b (with parens if multi-char).
        s = replaceRegex(in: s, pattern: #"\\frac\{([^{}]*)\}\{([^{}]*)\}"#) { match in
            let a = match.group(1).trimmingCharacters(in: .whitespaces)
            let b = match.group(2).trimmingCharacters(in: .whitespaces)
            let aStr = a.count > 1 ? "(\(a))" : a
            let bStr = b.count > 1 ? "(\(b))" : b
            return "\(aStr)/\(bStr)"
        }

        // \sqrt{x} → √x
        s = replaceRegex(in: s, pattern: #"\\sqrt\{([^{}]*)\}"#) { match in
            "√(\(match.group(1)))"
        }

        // Subscripts and superscripts — braces first, then single-char.
        s = replaceRegex(in: s, pattern: #"_\{([^{}]+)\}"#) { match in
            translate(match.group(1), using: subMap)
        }
        s = replaceRegex(in: s, pattern: #"\^\{([^{}]+)\}"#) { match in
            translate(match.group(1), using: superMap)
        }
        s = replaceRegex(in: s, pattern: #"_([a-zA-Z0-9])"#) { match in
            translate(match.group(1), using: subMap)
        }
        s = replaceRegex(in: s, pattern: #"\^([a-zA-Z0-9])"#) { match in
            translate(match.group(1), using: superMap)
        }

        // Common commands.
        let commands: [(String, String)] = [
            ("\\sum","∑"),("\\prod","∏"),("\\int","∫"),("\\infty","∞"),
            ("\\partial","∂"),("\\nabla","∇"),("\\pm","±"),("\\mp","∓"),
            ("\\cdot","·"),("\\times","×"),("\\div","÷"),("\\leq","≤"),
            ("\\geq","≥"),("\\neq","≠"),("\\approx","≈"),("\\equiv","≡"),
            ("\\propto","∝"),("\\rightarrow","→"),("\\leftarrow","←"),
            ("\\Rightarrow","⇒"),("\\Leftarrow","⇐"),("\\iff","⟺"),
            ("\\forall","∀"),("\\exists","∃"),("\\neg","¬"),("\\land","∧"),
            ("\\lor","∨"),("\\emptyset","∅"),("\\subset","⊂"),("\\supset","⊃"),
            ("\\subseteq","⊆"),("\\supseteq","⊇"),("\\in","∈"),("\\notin","∉"),
            ("\\cup","∪"),("\\cap","∩"),("\\hbar","ℏ"),("\\ell","ℓ"),
            ("\\Re","ℜ"),("\\Im","ℑ"),
        ]
        for (cmd, uni) in commands {
            s = s.replacingOccurrences(of: cmd, with: uni)
        }

        // Greek lower.
        let greekLower: [(String, String)] = [
            ("alpha","α"),("beta","β"),("gamma","γ"),("delta","δ"),("epsilon","ε"),
            ("zeta","ζ"),("eta","η"),("theta","θ"),("iota","ι"),("kappa","κ"),
            ("lambda","λ"),("mu","μ"),("nu","ν"),("xi","ξ"),("omicron","ο"),
            ("pi","π"),("rho","ρ"),("sigma","σ"),("tau","τ"),("upsilon","υ"),
            ("phi","φ"),("chi","χ"),("psi","ψ"),("omega","ω")
        ]
        for (name, uni) in greekLower {
            s = s.replacingOccurrences(of: "\\" + name, with: uni)
        }

        // Greek upper.
        let greekUpper: [(String, String)] = [
            ("Gamma","Γ"),("Delta","Δ"),("Theta","Θ"),("Lambda","Λ"),("Xi","Ξ"),
            ("Pi","Π"),("Sigma","Σ"),("Phi","Φ"),("Psi","Ψ"),("Omega","Ω")
        ]
        for (name, uni) in greekUpper {
            s = s.replacingOccurrences(of: "\\" + name, with: uni)
        }

        // Font commands → just strip them.
        s = replaceRegex(in: s, pattern: #"\\text\{([^{}]*)\}"#) { $0.group(1) }
        s = replaceRegex(in: s, pattern: #"\\mathrm\{([^{}]*)\}"#) { $0.group(1) }
        s = replaceRegex(in: s, pattern: #"\\mathit\{([^{}]*)\}"#) { $0.group(1) }
        s = replaceRegex(in: s, pattern: #"\\textbf\{([^{}]*)\}"#) { $0.group(1) }

        s = s.replacingOccurrences(of: #"\\left\("#, with: "(", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\right\)"#, with: ")", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\left\["#, with: "[", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\right\]"#, with: "]", options: .regularExpression)

        // Collapse whitespace that LaTeX would normally eat.
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #" *\\[ ,] *"#, with: "  ", options: .regularExpression)

        return s
    }

    // MARK: - Helpers

    /// Runs a regex repeatedly, calling the closure for each match with a 1-indexed capture-group API.
    private static func replaceRegex(
        in s: String,
        pattern: String,
        transform: (RegexMatch) -> String
    ) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out = s
        var offset = 0
        for match in matches.reversed() {
            let m = RegexMatch(ns: ns, match: match)
            let replacement = transform(m)
            let adjusted = NSRange(location: match.range.location + offset, length: match.range.length)
            out = (out as NSString).replacingCharacters(in: adjusted, with: replacement)
            offset += replacement.count - match.range.length
        }
        return out
    }

    /// A 1-indexed capture-group wrapper around NSTextCheckingResult.
    struct RegexMatch {
        let ns: NSString
        let match: NSTextCheckingResult

        func group(_ i: Int) -> String {
            let range = match.range(at: i)
            guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { return "" }
            return ns.substring(with: range)
        }
    }

    private static func translate(_ input: String, using map: [Character: Character]) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            out.append(map[ch] ?? ch)
        }
        return out
    }

    // MARK: - Character maps

    private static let subMap: [Character: Character] = {
        let digits: [Character] = ["₀","₁","₂","₃","₄","₅","₆","₇","₈","₉"]
        let lowerSource = "abcdefghijklmnopqrstuvwxyz"
        let lowerTarget: [Character] = Array("ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓᵧ_z")
        var map: [Character: Character] = [:]
        for (i, d) in "0123456789".enumerated() { map[d] = digits[i] }
        for (i, c) in lowerSource.enumerated() { map[c] = lowerTarget[i] }
        // Some uppercase letters have subscript forms.
        let upperPairs: [(Character, Character)] = [
            ("A","ₐ"),("E","ₑ"),("H","ₕ"),("I","ᵢ"),("J","ⱼ"),("K","ₖ"),
            ("L","ₗ"),("M","ₘ"),("N","ₙ"),("O","ₒ"),("P","ₚ"),("R","ᵣ"),
            ("S","ₛ"),("T","ₜ"),("U","ᵤ"),("V","ᵥ"),("X","ₓ"),("Y","ᵧ")
        ]
        for (k, v) in upperPairs { map[k] = v }
        return map
    }()

    private static let superMap: [Character: Character] = {
        let digits: [Character] = ["⁰","¹","²","³","⁴","⁵","⁶","⁷","⁸","⁹"]
        let upperSource = "ABDEGHIJKLMNOPRSTUVWXYZ"
        let upperTarget: [Character] = Array("ᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿˢᵀᵁⱽᵂˣʸᶻ")
        let lowerSource = "abcdefghijklmnopqrstuvwxyz"
        let lowerTarget: [Character] = Array("ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖᵠʳˢᵗᵘᵛʷˣʸᶻ")
        var map: [Character: Character] = [:]
        for (i, d) in "0123456789".enumerated() { map[d] = digits[i] }
        for (i, c) in upperSource.enumerated() { map[c] = upperTarget[i] }
        for (i, c) in lowerSource.enumerated() { map[c] = lowerTarget[i] }
        return map
    }()
}
