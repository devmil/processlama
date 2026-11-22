# qtbridge-interfaces 0.2.0, patched for ProcessLama

Upstream: https://code.qt.io/cgit/qt/qtbridge-rust.git/ (LGPL-3.0-only or
Qt Commercial), version 0.2.0 from crates.io, unmodified except
`src/object_access/rust_object_access.rs`.

Why: `try_store_handle_and_call_cpp(_mut)` stores the Rust object's handle in a
`Cell` reached through the caller's `&mut` proxy, then calls into C++. Qt
re-enters (for example `rowCount` from `rowsAboutToBeInserted` inside
`beginInsertRows`) through C++'s own pointer to the proxy. Under `noalias`,
release builds may sink the store past the opaque call, so the re-entrant read
finds no handle, tries the borrowed `RefCell` and panics
("Failed to borrow for row_count").

Patch: `std::hint::black_box(&self.borrow)` after storing the handle and after
the C++ call, so the cell's address escapes and the store stays before the
call. Remove this copy once upstream fixes the aliasing.
