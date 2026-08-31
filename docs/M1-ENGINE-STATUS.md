# M1 — Storage engine status

M1 is implemented. Its two remaining exit gates are reference-machine
measurements, recorded below and as gate 1 of `RELEASE-GATES.md` — not
unfinished implementation. This file records what the engine can prove today and
keeps unfinished accounting from being mistaken for a published value.

## Implemented

- `Measurement<T>` with exactly the three required states.
- Streaming, physical `FTS(3)` traversal.
- No symbolic-link following and no file-content reads.
- `SF_DATALESS` detection from traversal metadata.
- Logical bytes from `stat(2).st_size`.
- Allocated bytes from `stat(2).st_blocks × 512`.
- `(st_dev, st_ino)` identity and link count for hardlink accounting.
- Sparse data-range enumeration with `SEEK_DATA` / `SEEK_HOLE`.
- APFS device extent mapping with `F_LOG2PHYS_EXT`.
- Full-clone identity and reference counts from `ATTR_CMNEXT_CLONEID` (`0x100`)
  and `ATTR_CMNEXT_CLONE_REFCNT`.
- Clone-family grouping from overlapping physical extents, including partially
  diverged and transitively connected families.
- Lowest-common-ancestor crediting and zero-freeable attribution when an
  outside hardlink or full-clone member is proven.
- One bounded-concurrency engine API joining FTS traversal, extent inspection,
  clone families, snapshot inventory and open-file enumeration.
- A staged full-volume pipeline that writes FTS records and extent results
  directly to SQLite in bounded pages instead of retaining path strings and
  per-file maps for the whole volume.
- Streaming physical-segment reduction with lowest-common-ancestor crediting
  and fixed-size node vectors.
- Additive storage-tree accounting with interned path components.
- Exact live-filesystem deletion-set accounting from physical reference
  segments, including partial clones and open descriptors.
- A deterministic 250-case partition property test.
- Transactional SQLite schema for scans, nodes, modification times, clone
  identities, family membership, subtree totals and snapshot inventory.
- FTS5 path/component search plus parameter-bound size, clone, and inter-scan
  change queries for the command palette.
- A physically allocated 512 MB sibling reservation, released with
  `ftruncate(2)` before SQLite writes, plus a tested alternate-volume retry for
  completed in-memory scans on `SQLITE_FULL`.
- Read-only `fs_snapshot_list(2)` inventory with honest privilege/entitlement
  degradation and no shipping subprocess.
- Read-only `fs_snapshot_mount(2)` inspection. Snapshot physical extents stream
  directly into SQLite, are unioned by device/range there, and are subtracted
  from freeable live segments before any value is published.
- Open vnode identity enumeration through libproc, with the complete set
  suppressed if any live process denies inspection.
- Per-entry scan errors without discarding a usable partial walk.
- Golden fixtures covering internal and external clone families, sparse files,
  hardlink pairs, dataless files, physical symlink cycles and the portable path
  length boundary.
- Staged freeable-byte accounting that refuses subtree or incomplete scans,
  requires an exact snapshot-inventory/coverage match, and requires a complete
  libproc open-file inventory.

## Remaining exit gates

- Prove the under-300 MB full-scan memory budget on the reference machine.
- Benchmark the reference volume and meet the 20,000 entries/second target.

The S6 spike confirmed that `fs_snapshot_list(2)` remains present in the Tahoe
SDK and works with the required `ATTR_BULK_REQUIRED` request layout. Apple's
manual still states that snapshot calls require superuser privileges plus an
additional entitlement. FATHOM therefore renders snapshot-held bytes as *not
published* when macOS denies either inventory or read-only mounting. It never
substitutes an estimate.
