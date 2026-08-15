import FoundationModels

// Layer 2. Whether the local tier is even possible on this machine — the one
// question the UI has to ask before offering a download that may not be needed.
// It belongs here rather than in the view for the same reason Vision and PDFKit
// live in Tools: a framework that does inference is not something layer 4 gets
// to hold (coding-standards.md §1, and the check in scripts/layers.sh).
//
// No session is opened and no prompt is built. F5 is still the only thing that
// will ever make a call, and this file opens no socket either.

/// Whether macOS has the on-device model on this machine.
///
/// Deliberately a function and not a stored value: macOS downloads and evicts
/// these assets on its own schedule, so anything cached goes stale the moment
/// the user leaves for System Settings and comes back. Ask again instead.
public func localModelAvailable() -> Bool {
    SystemLanguageModel.default.isAvailable
}
