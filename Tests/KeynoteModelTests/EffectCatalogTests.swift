import Foundation
import Testing
@testable import KeynoteModel

@Suite("Effect catalog")
struct EffectCatalogTests {

    @Test("lists are non-empty and duplicate-free")
    func integrity() {
        for list in [
            KeynoteEffects.transitions,
            KeynoteEffects.buildIns,
            KeynoteEffects.buildOuts,
            KeynoteEffects.actions,
        ] {
            #expect(!list.isEmpty)
            #expect(Set(list).count == list.count)
            #expect(list.allSatisfy { $0.hasPrefix("apple:") || $0.hasPrefix("com.apple.iWork.Keynote.") })
        }
    }

    @Test("contains the effects verified against Keynote in this project")
    func verifiedMembers() {
        #expect(KeynoteEffects.transitions.contains("apple:dissolve"))
        #expect(KeynoteEffects.transitions.contains("apple:3D-cube"))
        #expect(KeynoteEffects.transitions.contains("apple:push"))
        #expect(KeynoteEffects.buildIns.contains("apple:bc-appear"))
        #expect(KeynoteEffects.buildOuts.contains("apple:bc-appear"))
        #expect(KeynoteEffects.actions.contains("apple:action-rotation"))
    }

    @Test("convenience constants appear in their category lists")
    func constants() {
        #expect(KeynoteEffects.transitions.contains(KeynoteEffects.push))
        #expect(KeynoteEffects.transitions.contains(KeynoteEffects.cube))
        #expect(KeynoteEffects.transitions.contains(KeynoteEffects.confetti))
        #expect(KeynoteEffects.transitions.contains(KeynoteEffects.magicMove))
        #expect(KeynoteEffects.buildIns.contains(KeynoteEffects.appear))
        #expect(KeynoteEffects.buildIns.contains(KeynoteEffects.pop))
    }
}
