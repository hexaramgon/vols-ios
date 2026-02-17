//
//  ClosedRange+Extensions.swift
//  SharedUtilities
//
//

public extension ClosedRange where Bound: AdditiveArithmetic {
    var distance: Bound {
        upperBound - lowerBound
    }
}

public extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

public extension Sequence where Iterator.Element: Hashable {
    func unique() -> [Iterator.Element] {
        var seen: Set<Iterator.Element> = []
        return filter { seen.insert($0).inserted }
    }
}
