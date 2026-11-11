# Source-strategy experiment inputs

For contributors reproducing source-update measurements, this page records the fixed fixture inputs and how benchmark copies are prepared.

These project-owned synthetic fixtures preserve the 200 numeric-control layouts generated for the 2026-10-29 performance investigation: absolute placement, three single-level grids, and eight nested grid levels. The exact starting inputs come from the preserved `emission-reuse-quiet200-20261029` experiment. The harness parses these synthetic fixtures as data.

`prepareSourceStrategyVariants.py` adds initial literal settings to half of the measured targets in copies under `testResults`, so the same deterministic operation sequence mixes replacements and insertions. The preserved originals remain unchanged. Class comments and source formatting are retained as fixture data.
