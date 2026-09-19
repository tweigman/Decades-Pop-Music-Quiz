// A faithful port of the parts of Python's difflib.SequenceMatcher that
// grading uses: SequenceMatcher(None, a, b).ratio(). The match thresholds in
// Settings were tuned against Python's scores, so this must agree with it
// exactly, including the "autojunk" heuristic for sequences of 200+ items.

enum SequenceMatcher {
    /// 2 * matches / (len(a) + len(b)), as difflib computes it.
    static func ratio(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let total = a.count + b.count
        guard total > 0 else { return 1.0 }
        return 2.0 * Double(matchingCharacters(a, b)) / Double(total)
    }

    private static func matchingCharacters(_ a: [UInt8], _ b: [UInt8]) -> Int {
        // b2j: where each element of b occurs, minus "popular" elements.
        var b2j = [UInt8: [Int]]()
        for (j, element) in b.enumerated() {
            b2j[element, default: []].append(j)
        }
        if b.count >= 200 {
            let ntest = b.count / 100 + 1
            for (element, indices) in b2j where indices.count > ntest {
                b2j[element] = nil
            }
        }

        var matched = 0
        var queue = [(0, a.count, 0, b.count)]
        while let (alo, ahi, blo, bhi) = queue.popLast() {
            let (i, j, k) = longestMatch(a, b, b2j, alo, ahi, blo, bhi)
            guard k > 0 else { continue }
            matched += k
            if alo < i && blo < j { queue.append((alo, i, blo, j)) }
            if i + k < ahi && j + k < bhi { queue.append((i + k, ahi, j + k, bhi)) }
        }
        return matched
    }

    private static func longestMatch(
        _ a: [UInt8], _ b: [UInt8], _ b2j: [UInt8: [Int]],
        _ alo: Int, _ ahi: Int, _ blo: Int, _ bhi: Int
    ) -> (Int, Int, Int) {
        var besti = alo, bestj = blo, bestsize = 0
        var j2len = [Int: Int]()
        for i in alo..<ahi {
            var newj2len = [Int: Int]()
            for j in b2j[a[i]] ?? [] {
                if j < blo { continue }
                if j >= bhi { break }
                let k = (j2len[j - 1] ?? 0) + 1
                newj2len[j] = k
                if k > bestsize {
                    besti = i - k + 1
                    bestj = j - k + 1
                    bestsize = k
                }
            }
            j2len = newj2len
        }
        // With no junk function, difflib then extends the match over equal
        // neighbours (which recovers any "popular" elements dropped above).
        while besti > alo && bestj > blo && a[besti - 1] == b[bestj - 1] {
            besti -= 1
            bestj -= 1
            bestsize += 1
        }
        while besti + bestsize < ahi && bestj + bestsize < bhi
            && a[besti + bestsize] == b[bestj + bestsize]
        {
            bestsize += 1
        }
        return (besti, bestj, bestsize)
    }
}
