# Recipe over-match and revocation

Runtime refuses any recipe whose match count exceeds `max_matches`. Treat a
field report as a potential supply-chain incident even when no action ran.

1. Record recipe identifier, signed catalogue version, app version, match
   count, and the declared root. Ask for redacted diagnostics, not raw paths.
2. Reproduce against synthetic fixtures and confirm containment after symlink
   resolution. Do not test against a contributor's real home directory.
3. Remove the recipe from the bundled catalogue or reduce its scope and bump
   catalogue version. Sign the complete replacement; never patch a signed file.
4. Add the field shape to fixture coverage and assert containment,
   `max_matches`, and non-empty regeneration cost.
5. Ship the revocation in an app update. FATHOM's one-outbound-request law
   forbids a remote recipe updater, so the existing signed bundle remains
   unchanged until the user installs that release.

No over-matched paths may be redistributed among categories or silently
ignored to make totals appear complete.
