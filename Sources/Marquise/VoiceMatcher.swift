import Foundation

/// Uma palavra do roteiro: onde ela está no texto e a forma usada para comparar com a fala.
struct ScriptWord: Equatable {
    let range: NSRange
    let normalized: String
}

enum SpeechText {
    private static let wordPattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’][\\p{L}]+)*")

    /// Minúsculas, sem acentos e sem pontuação: "Câmera," → "camera".
    static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func words(in text: String) -> [ScriptWord] {
        let ns = text as NSString
        return wordPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let normalized = normalize(ns.substring(with: match.range))
            return normalized.isEmpty ? nil : ScriptWord(range: match.range, normalized: normalized)
        }
    }
}

/// Descobre em que palavra do roteiro a pessoa está, a partir das últimas palavras ouvidas.
/// Tolera erros do reconhecimento, palavras puladas ou repetidas, e quem volta para reler.
struct VoiceMatcher {
    let words: [String]
    /// Índice da última palavra do roteiro já falada (-1 = ainda no começo).
    private(set) var current = -1

    init(words: [String]) { self.words = words }

    mutating func reset(to index: Int = -1) {
        current = min(max(index, -1), words.count - 1)
    }

    /// Recebe as palavras mais recentes da fala (já normalizadas) e devolve o novo índice, se mudou.
    @discardableResult
    mutating func update(heard rawHeard: [String]) -> Int? {
        let heard = Array(rawHeard.filter { !$0.isEmpty }.suffix(8))
        guard !heard.isEmpty, !words.isEmpty else { return nil }

        // 1) Perto de onde a pessoa está.
        let low = max(0, current - 6)
        let high = min(words.count - 1, current + 30)
        if let best = bestCandidate(heard, in: low...high), accept(best) {
            return move(to: best.index)
        }
        // 2) Perdeu o fio (pulou um trecho ou voltou muito): procura no roteiro inteiro, exigindo mais certeza.
        if let best = bestCandidate(heard, in: 0...(words.count - 1)), best.score >= 3.5 {
            return move(to: best.index)
        }
        return nil
    }

    private struct Candidate { let index: Int; let score: Double; let ranking: Double }

    private func bestCandidate(_ heard: [String], in range: ClosedRange<Int>) -> Candidate? {
        var best: Candidate?
        for end in range {
            guard Self.similar(heard[heard.count - 1], words[end]) else { continue }
            let score = alignmentScore(heard, endingAt: end)
            let ranking = score - 0.04 * Double(abs(end - (current + 1)))
            if best == nil || ranking > best!.ranking {
                best = Candidate(index: end, score: score, ranking: ranking)
            }
        }
        return best
    }

    private func accept(_ c: Candidate) -> Bool {
        if c.index > current {
            if c.score >= 1.8 { return true }
            // Uma palavra só basta se for a próxima (ou quase) e não for curtinha ("a", "de"...).
            return c.score >= 1 && c.index <= current + 2 && words[c.index].count >= 4
        }
        // Voltar exige mais certeza (a pessoa está relendo um trecho).
        return c.index < current - 1 && c.score >= 3
    }

    private mutating func move(to index: Int) -> Int? {
        guard index != current else { return nil }
        current = index
        return index
    }

    /// Compara as palavras ouvidas, de trás para frente, com o roteiro terminando em `end`.
    private func alignmentScore(_ heard: [String], endingAt end: Int) -> Double {
        var i = heard.count - 1, j = end
        var score = 0.0, misses = 0
        while i >= 0, j >= 0, j > end - 16, misses <= 3 {
            if Self.similar(heard[i], words[j]) {
                score += words[j].count <= 2 ? 0.5 : 1
                i -= 1
                j -= 1
            } else if i > 0, Self.similar(heard[i - 1], words[j]) {
                i -= 1  // palavra a mais na fala ("é... é")
                misses += 1
            } else if j > 0, Self.similar(heard[i], words[j - 1]) {
                j -= 1  // palavra do roteiro pulada
                misses += 1
            } else {
                i -= 1
                j -= 1
                misses += 1
            }
        }
        return score
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let la = a.count, lb = b.count
        if min(la, lb) >= 4, a.hasPrefix(b) || b.hasPrefix(a) { return true }
        guard max(la, lb) >= 5 else { return false }
        return levenshtein(a, b) <= max(la, lb) / 4
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }
}
