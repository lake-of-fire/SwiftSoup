# Independent repeat

This benchmark-only commit triggers an independent rebuild and repeat of the unchanged macOS A/B protocol. It does not change production sources, tests, fixtures, timing code, iteration calibration, or branch permissions.

The first run (34314437708) completed successfully. Its short-snippet A/B result was separated from its near-zero A/A estimate. The growth workload's unchanged A/A control drifted, so its small apparent A/B improvement is not treated as established. Both complete runs, including every A/A block and unfavorable observation, must be retained and reported. This repeat is not a replacement or an excuse to discard the first run.

Do not merge this benchmark-only branch into the runtime PR or master.
