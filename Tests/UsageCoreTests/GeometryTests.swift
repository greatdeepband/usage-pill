import CoreGraphics
import Testing
@testable import UsageCore

private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

@Test func keepsPointInsideScreen() {
    let p = clampTopLeft(CGPoint(x: 100, y: 500), pillSize: CGSize(width: 250, height: 44), screens: [screen])
    #expect(p == CGPoint(x: 100, y: 500))
}

@Test func pullsOffscreenPointBack() {
    let p = clampTopLeft(CGPoint(x: 5000, y: -200), pillSize: CGSize(width: 250, height: 44), screens: [screen])
    #expect(p.x <= screen.maxX - 250)
    #expect(p.y >= screen.minY + 44)
    #expect(p.y <= screen.maxY)
}

@Test func choosesNearestScreen() {
    let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
    let p = clampTopLeft(CGPoint(x: 4000, y: 500), pillSize: CGSize(width: 250, height: 44), screens: [screen, right])
    #expect(p.x == right.maxX - 250)
    #expect(p.y == 500)
}

@Test func emptyScreensReturnsPointUnchanged() {
    let p = clampTopLeft(CGPoint(x: 7, y: 7), pillSize: CGSize(width: 250, height: 44), screens: [])
    #expect(p == CGPoint(x: 7, y: 7))
}
