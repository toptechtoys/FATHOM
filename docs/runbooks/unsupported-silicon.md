# Unsupported Apple silicon

An unknown SoC is a publication gap, not permission to reuse a nearby channel
map.

1. Run `fathom doctor` and `fathom dump-channels`; record macOS build and exact
   `hw.model`.
2. Confirm CPU, memory, storage, and other public-API modules still operate.
   Private hardware values must remain *not published*.
3. Compare channel inventory on the target machine with independent reference
   measurements. Never infer labels from channel order or another SoC.
4. Add an exact model entry and exact channel labels to a new map version, add
   fixture assertions, and sign the complete map with the offline release key.
5. Verify sampling deltas, units, idle wake-up budgets, and full-window energy
   on that physical model before declaring support.

Until step 5 passes, UI copy must name the unsupported model and offer
`dump-channels`; it must not show approximated power, frequency, or bandwidth.
