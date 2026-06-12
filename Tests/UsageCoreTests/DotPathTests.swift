import Testing
import Foundation
@testable import UsageCore

private func json(_ s: String) -> Any {
    try! JSONSerialization.jsonObject(with: Data(s.utf8))
}

@Test func resolvesNestedKeysAndIndices() {
    let j = json(#"{"balance_infos":[{"total_balance":"110.53"}],"n":{"v":7}}"#)
    #expect(DotPath.resolve("balance_infos.0.total_balance", in: j) == 110.53)
    #expect(DotPath.resolve("n.v", in: j) == 7)
}

@Test func numericStringsParseButOtherStringsDont() {
    let j = json(#"{"a":"12.5","b":"hello","c":""}"#)
    #expect(DotPath.resolve("a", in: j) == 12.5)
    #expect(DotPath.resolve("b", in: j) == nil)
    #expect(DotPath.resolve("c", in: j) == nil)
}

@Test func rejectsBooleansMissingPathsAndBadIndices() {
    let j = json(#"{"flag":true,"off":false,"arr":[1,2]}"#)
    #expect(DotPath.resolve("flag", in: j) == nil)
    #expect(DotPath.resolve("off", in: j) == nil)
    #expect(DotPath.resolve("nope.deep", in: j) == nil)
    #expect(DotPath.resolve("arr.5", in: j) == nil)
    #expect(DotPath.resolve("arr.-1", in: j) == nil)
    #expect(DotPath.resolve("", in: j) == nil)
}

@Test func nonFiniteRejected() {
    let j: Any = ["x": Double.infinity]
    #expect(DotPath.resolve("x", in: j) == nil)
}
