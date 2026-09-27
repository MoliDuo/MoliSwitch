import Foundation

struct InputSource: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
}

/// One entry in the per-application input source picker.
struct InputSourceChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}
