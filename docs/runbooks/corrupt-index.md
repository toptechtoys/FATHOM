# Corrupt storage index

The storage index is regenerable. Reclaim and cloud journals are not and must
never be moved with it.

1. Stop scans and reclaim actions. Run `fathom doctor` and save its output.
2. Verify the failing path is `~/Library/Application Support/FATHOM/storage.sqlite`.
3. Quit FATHOM and FATHOM Bar.
4. Move `storage.sqlite`, `storage.sqlite-wal`, and `storage.sqlite-shm` into a
   timestamped `Index Quarantine` folder beside the index. Do not delete them.
5. Relaunch and run a new scan. Confirm `fathom doctor` reports the current
   schema and `integrity_check` tests remain green.
6. Preserve the quarantine folder for diagnosis. It may contain private paths;
   do not attach it publicly.

Recovery never touches `reclaim-journal.jsonl` or
`cloud-eviction-journal.jsonl`. If the replacement scan cannot persist because
the disk is full, use the memory-only result and reclaim through a validated
dry run before retrying.
