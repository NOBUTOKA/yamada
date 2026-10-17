# Editor performance measurements

Run the benchmark from the project root in the interactive account that owns the
MATLAB license. The runner opens a separate MATLAB process for each case and
operates editor-owned fixtures; input application code and callbacks are never run.

```powershell
& tests/performance/runYamadaPerformance.ps1 -Samples 4 `
    -OutputFolder testResults/performance/comparison
```

The three default cases contain the same 12 labels and three panels: absolute
positioning, three single-level grids, and four grids including a common outer
grid. `-ComponentCount` changes the number of labels, not the total model count.
Use a new output directory for every run. Keep other MATLAB test and benchmark
processes idle when comparing elapsed time.

```powershell
# Higher sample counts and a separate endurance exercise.
& tests/performance/runYamadaPerformance.ps1 -Samples 20 `
    -OutputFolder testResults/performance/distribution
& tests/performance/runYamadaPerformance.ps1 -Samples 4 `
    -RepeatedSelections 100 -DocumentCycles 5 `
    -OutputFolder testResults/performance/endurance

# Bound larger-fixture exploration before increasing its sample count.
& tests/performance/runYamadaPerformance.ps1 -ComponentCount 50 -Samples 1 `
    -OutputFolder testResults/performance/scale-50
& tests/performance/runYamadaPerformance.ps1 -ComponentCount 200 -Samples 1 `
    -OutputFolder testResults/performance/scale-200

# Profiler samples are saved separately and excluded from elapsed-time statistics.
& tests/performance/runYamadaPerformance.ps1 -Samples 2 -Profile `
    -OutputFolder testResults/performance/profile
```

`gallery` and `navigation` are optional `-Cases` values that open preserved product
fixtures and select font-capable controls when no matched labels exist. If source
safety makes the selected property read-only, `excluded-operations.json` records
the boundary and property samples are omitted. Disabled controls are never forced
through a commit. The matched generated cases are the controls for layout comparisons.
Do not compare a different component count as though only the grid changed.

## Measurements and limits

- `source-manifest.json`: target commit, working-tree status, options, and SHA-256
  of tracked and newly added MATLAB, HTML, JSON, and runner source.
- `harness-source/`: the exact benchmark and runner sources used by that run.
- `<case>/measurements.json`: every completed callback and settled sample, grouped
  by first target, revisit, same target, and first/warm property edit. Startup and
  Open are separate. Summaries include count, median, and nearest-rank p95.
- `<case>/progress.jsonl`: flushed operation boundaries, including the start of an
  operation that later times out. Completed samples are persisted immediately.
- `<case>/resources.jsonl`: one-second samples of cumulative CPU seconds, private
  bytes, working set, and OS handle count for the owned process and its discovered
  descendants. Shared services, GPU use, and unrelated processes are not included.
- Native object/timer counts and the current serialized overlay payload size are
  captured after timing stops. Payload size is not a transferred-byte counter.
- `preview-statistics.json`: full Preview renders and incremental synchronizations
  after normal property samples, before profiling or endurance operations.
- `profile-selection.mat` and `profile-property.mat`: raw MATLAB profiles when
  `-Profile` is enabled. Inclusive times must not be added across parent/child calls.
- `outcomes.json` and `<case>/matlab.log`: success, failure, or timeout and diagnostics.

Settled time includes pending editor layout timers and the current HTML revision's
two-animation-frame acknowledgement. This measures the browser render pipeline,
not physical display scanout. Acknowledgements are opt-in and disabled in ordinary
editor use. MATLAB-only timing is available with `runYamadaPerformance(RenderAck=false)`.

The external watchdog allows 30 seconds per ordinary operation, 90 seconds per
profiled operation, and five minutes per case. It terminates only the process tree
it created. A timeout is a failure/limit observation, never a zero-duration sample
or a pass. Split long distributions across independent runs rather than silently
raising these limits. Retain each run's manifest and distinguish first and warm
samples when aggregating. Four samples are exploratory; they do not establish a
stable p95 or a release latency guarantee.

Repeated selections and document reopenings are excluded from the normal latency
distribution. Use their object/timer counts together with resource trends to
investigate retention. Process allocation alone does not prove a memory leak or
the absence of retained MATLAB objects.
