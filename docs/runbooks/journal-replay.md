# Reclaim journal after interruption

The journal is append-only. An intent line is fsynced before each Trash move,
followed by an outcome line. Absence of an outcome is uncertainty, not failure
or success.

1. Stop further reclaim actions and preserve `reclaim-journal.jsonl`.
2. Group lines by operation identifier and locate intents without outcomes.
3. For each unresolved intent, compare the recorded inode, size, and mtime with
   the original path and inspect the Trash for the same identity.
4. If the identity is in Trash, record recovery as moved. If it remains at the
   source unchanged, it is safe to offer the action again through a new dry
   run. If neither is provable, report *not attributable* and do nothing.
5. Never replay an intent by path alone, never move an item automatically, and
   never truncate the journal during recovery.

The same procedure applies to the cloud-eviction journal, except recovery uses
ubiquitous download state rather than Trash identity.
