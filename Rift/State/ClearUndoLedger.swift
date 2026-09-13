/// pane-local undo bookkeeping for the one undoable clear (sdd §7.5, m3.1):
/// records what a clear removed and from which pane, invalidates that record
/// on the mutations that make restoring unsafe, and hands it back exactly once.
/// generic over the pane identifier and the per-pane metadata so the same
/// source compiles into the test bundle without the app module; no ui, no
/// observation, no foundation
struct ClearUndoLedger<Pane: Hashable & Sendable, Meta: Equatable & Sendable>: Equatable, Sendable {
    /// one recorded clear. `token` is unique per record, so a callback that was
    /// registered for an earlier clear can never consume a later one — not even
    /// a later clear of the same pane
    struct Record: Equatable, Sendable {
        let token: UInt64
        let pane: Pane
        let text: String
        let meta: Meta
    }

    /// the record that can still be restored; nil when nothing is undoable
    private(set) var pending: Record?
    private var nextToken: UInt64 = 1

    /// the pane whose clear is currently undoable
    var pendingPane: Pane? {
        pending?.pane
    }

    /// records a clear of `text` from `pane`. an empty pane records nothing and
    /// returns nil; a newer clear supersedes whatever was pending
    @discardableResult
    mutating func recordClear(of pane: Pane, text: String, meta: Meta) -> Record? {
        guard !text.isEmpty else { return nil }
        let record = Record(token: nextToken, pane: pane, text: text, meta: meta)
        nextToken &+= 1
        pending = record
        return record
    }

    /// text arriving in a pane: non-empty text in the pending pane means the
    /// pane was refilled and the record is dropped; empty text (the clear
    /// itself) and text in the other pane leave it untouched
    mutating func noteText(_ text: String, in pane: Pane) {
        guard let record = pending, record.pane == pane, !text.isEmpty else { return }
        pending = nil
    }

    /// swapping sides drops the record: the cleared slot no longer means the
    /// same pane
    mutating func noteSwap() {
        pending = nil
    }

    /// consumes the pending record only when it is exactly `record` (same
    /// token); on a mismatch the current record stays untouched and nil is
    /// returned — the guard for stale UndoManager callbacks
    mutating func takePending(matching record: Record) -> Record? {
        guard let current = pending, current == record else { return nil }
        pending = nil
        return current
    }

    /// consumes whatever is pending (the visible Undo action); one-shot
    mutating func takePending() -> Record? {
        let current = pending
        pending = nil
        return current
    }
}
