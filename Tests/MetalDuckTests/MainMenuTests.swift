import AppKit
import Testing
@testable import MetalDuck

@MainActor @Test func menuQuitsWithCommandQ() throws {
    let menu = MainMenu.make()
    let quit = try #require(menu.items.first?.submenu?.items.first { $0.action == #selector(NSApplication.terminate(_:)) })
    #expect(quit.keyEquivalent == "q")
    #expect(quit.keyEquivalentModifierMask == .command)
    #expect(menu.items.map(\.title) == ["MetalDuck", "Edit", "Window"])
}
