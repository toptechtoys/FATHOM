# Running the app, and trusting what you see

Read before you change a screen or the menu bar widget.

## On an Intel Mac

**Running it on an Intel Mac.** `project.yml` pins `ARCHS: arm64`; overriding it
builds a working x86_64 app, which runs on an Intel MacBookPro16,1 under macOS
26 and shows every layout. It has caught defects the compiler, the contrast gate
and the arithmetic all passed: a readout row that resolved to CSS `auto-fill`
and stopped a third of the way across every section, and a `Layout` that trapped
on SwiftUI's infinite width proposal and killed the app at launch with no crash
report.

An Intel host cannot answer the Apple-silicon questions: IOReport, SMC
temperature, `perflevel1` and the NVMe SMART user client all render *not
published* there, and idle cost means nothing off Apple silicon. **Run it anyway
when you change a screen.** It is the cheapest check in this repository and the
only one that has ever caught a layout.

## Check the number before you believe a pixel

**Make the app print the number before you believe a pixel.** Running it is
the cheapest check here, and reading it wrong is the cheapest mistake. Three
diagnoses in one day were wrong the same way: a window "opening below its
minimum" that was measured off a screenshot at an assumed scale — the real
scale is 0.52 px per point on the development display, and the window was
opening at exactly its declared default; and twice, keyboard input "not being
delivered" when it was arriving the whole time.

Every one collapsed the moment something was instrumented to answer directly.
A temporary overlay reporting `GRID 2,184x164` proved the readout row was
sized correctly and specified wrongly. `defaults read com.exhibinaut.fathom`
showed five saved window frames and named the real defect. An `NSEvent`
counter beside a handler counter — arrivals versus calls — settled in one
screenshot what two speculative fixes had not. `sample(1)` named the exact
frame the Bluetooth read was parked in. Forty-eight timed reads turned a
timeout somebody liked the sound of into one the machine chose.

A screenshot shows you *that* something is wrong. It is very bad at *what*,
and it will let you write a confident paragraph about a defect that does not
exist. Add the counter, take the measurement, delete it afterwards.
