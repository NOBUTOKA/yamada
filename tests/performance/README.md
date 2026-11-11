# Editor performance measurements

For contributors measuring editor changes, this guide explains how to run repeatable benchmarks and interpret their output. Run the benchmark from the project root in a licensed graphical MATLAB session. The runner opens a separate MATLAB process for each case and operates editor-owned fixtures; input application code and callbacks are never run.

Record the baseline and candidate revisions and use matching source trees, fixtures, and workload hashes.

Run the checks relevant to the behavior being measured. Use separate MATLAB sessions for regression tests and timing, and run only one measurement workload at a time.

Use successive edits to different component/property pairs as the default interactive workload. Include mixed property paths and value kinds where the fixture supports them, and measure selection separately from each property commit. Repeated changes to the same property on the same component are diagnostic controls only: use them when needed to isolate cache, reuse, or history behavior, label them explicitly, and do not substitute their warmed latency for ordinary editing performance. Distinct numeric fields edited once each are a valid focused workload, but do not cover mixed property kinds.

`runYamadaPerformance` visits a different eligible component for every ordinary property sample and records `property-selection` separately. Property samples are capped by the eligible target count; increase fixture size to obtain more distinct samples. Explicit profiling and endurance options may retain repeated-target diagnostic controls.

```powershell
& tests/performance/runYamadaPerformance.ps1 -Samples 4 `
    -OutputFolder testResults/performance/comparison
```

The three default cases contain the same 12 labels and three panels: absolute positioning, three single-level grids, and four grids including a common outer grid. `-ComponentCount` changes the number of labels, not the total model count. Use a new output directory for every run. Keep other MATLAB test and benchmark processes idle when comparing elapsed time.

`-NestedDepth` sets the maximum number of grid ancestors in `nestedgrid` (default two). Values four and eight add a chain of one-cell outer grids above the same three panels; labels and panel counts stay fixed, while total grid/model counts increase and must be reported. The option does not change `absolute` or `flatgrid`. Startup, Open, selection, first edits, and repeated edits remain separate observations. Do not attribute a total-time change to rendering without examining the corresponding profile.

```powershell
# Higher sample counts and a separate endurance exercise.
& tests/performance/runYamadaPerformance.ps1 -Samples 20 `
    -OutputFolder testResults/performance/distribution
& tests/performance/runYamadaPerformance.ps1 -Samples 4 `
    -RepeatedSelections 100 -AlternatingSelections 100 -DocumentCycles 5 `
    -OutputFolder testResults/performance/endurance
& tests/performance/runYamadaPerformance.ps1 -EnduranceOnly -DocumentCycles 100 `
    -OutputFolder testResults/performance/document-endurance

# Bound larger-fixture exploration before increasing its sample count.
& tests/performance/runYamadaPerformance.ps1 -ComponentCount 50 -Samples 1 `
    -OutputFolder testResults/performance/scale-50
& tests/performance/runYamadaPerformance.ps1 -ComponentCount 200 -Samples 1 `
    -OutputFolder testResults/performance/scale-200
& tests/performance/runYamadaPerformance.ps1 -Cases nestedgrid -ComponentCount 50 `
    -NestedDepth 8 -Samples 3 -Profile -OutputFolder testResults/performance/depth-8
& tests/performance/runYamadaPerformance.ps1 -EnduranceOnly -PropertyChanges 100 `
    -OutputFolder testResults/performance/property-endurance

# New unsaved settings on two siblings in the same grid (or no-grid control).
& tests/performance/runYamadaPerformance.ps1 -EnduranceOnly -AlternatingPropertyChanges 6 `
    -OutputFolder testResults/performance/pending-siblings

# Profiler samples are saved separately and excluded from elapsed-time statistics.
& tests/performance/runYamadaPerformance.ps1 -Samples 2 -Profile `
    -OutputFolder testResults/performance/profile
```

`gallery` and `navigation` are optional `-Cases` values that open preserved product fixtures and select font-capable controls when no matched labels exist. If source safety makes the selected property read-only, `excluded-operations.json` records the boundary and property samples are omitted. Disabled controls are never forced through a commit. The matched generated cases are the controls for layout comparisons. Do not compare a different component count as though only the grid changed.

`-AlternatingPropertyChanges` alternates FontSize changes between two siblings. Run it with `-EnduranceOnly` to begin without normal property edits. The first change introduces one setting; the second introduces a setting on the other component, and later changes revisit both unsaved settings. Selection is recorded separately from each change. `-Profile` additionally records a later change in `profile-property-multiple.mat`; profile durations are excluded from ordinary samples. This option requires two font-capable siblings in the selected fixture.

`-PropertyPath Text` measures actual Label Text edits instead of FontSize. The default remains FontSize with the same numeric sequences. Text edits exercise the full validation path; keep them separate from numeric local re-edits. Both the manifest and measurement JSON record the property. Startup, Open, selection, and property callbacks remain separate, and every ordinary edit verifies the recorded value. For example:

```powershell
& tests/performance/runYamadaPerformance.ps1 -PropertyPath Text -Samples 4 `
    -OutputFolder testResults/performance/text-comparison
```

## Measurements and limits

- `source-manifest.json`: target commit, working-tree status, options, and SHA-256 of tracked and newly added MATLAB, HTML, JSON, and runner source.
- `harness-source/`: the exact benchmark and runner sources used by that run.
- `<case>/measurements.json`: every completed callback and settled sample, grouped by first target, revisit, same target, and first/warm property edit. Startup and Open are separate. Summaries include count, median, and nearest-rank p95.
- `<case>/progress.jsonl`: flushed operation boundaries, including the start of an operation that later times out. Completed samples are persisted immediately.
- `<case>/resources.jsonl`: one-second samples of cumulative CPU seconds, private bytes, working set, and OS handle count for the owned process and its discovered descendants. Shared services, GPU use, and unrelated processes are not included.
- Native object/timer counts and the current serialized overlay payload size are captured after timing stops. Payload size is not a transferred-byte counter.
- `preview-statistics.json`: full Preview renders and incremental synchronizations after normal property samples, before profiling or endurance operations.
- `profile-selection.mat` and `profile-property.mat`: raw MATLAB profiles when `-Profile` is enabled. Inclusive times must not be added across parent/child calls.
- `profile-property-warm.mat`: when at least two normal property samples completed, profiles a further edit on that same component before the selection changes. Its context records component and before/after values. Profiler times are not substitutes for ordinary latency samples.
- `document-lifetime.json`: observed source snapshot identities and destruction events for documents installed by Open/reopen. Listeners capture only the editor figure and snapshot string; no old document or listener handles are saved. This checks observed document lifetimes, not all internal object allocations.
- `outcomes.json` and `<case>/matlab.log`: success, failure, or timeout and diagnostics.

Settled time includes pending editor layout timers and the current HTML revision's two-animation-frame acknowledgement. This measures the browser render pipeline, not physical display scanout. Acknowledgements are opt-in and disabled in ordinary editor use. MATLAB-only timing is available with `runYamadaPerformance(RenderAck=false)`.

The external watchdog defaults to 30 seconds per ordinary operation, 90 seconds per profiled operation, and five minutes per case. Set `-OperationTimeoutSeconds`, `-ProfileTimeoutSeconds`, and `-CaseTimeoutSeconds` explicitly for longer runs; all three limits are recorded in the source manifest. The approved extended 200-component comparison uses 120, 240, and 600 seconds respectively, with the same limits and harness on both versions. After a further 120-second timeout, the deepest ordinary case uses 240, 240, and 600 seconds in a separate matched run. Preserve the original capped runs and report the extended results separately. The watchdog terminates only the process tree it created. A timeout is a failure/limit observation, never a zero-duration sample or a pass. Retain each run's manifest and distinguish first and warm samples when aggregating. Four samples are exploratory; they do not establish a stable p95 or a release latency guarantee.

Repeated selections and document reopenings are excluded from the normal latency distribution. Use their object/timer counts together with resource trends to investigate retention. Resource discovery rejects processes created before the owned invocation, since Windows can leave a reused parent PID in an older process. Layout polling tolerates timers deleted by completed callbacks between discovery and state access. Process allocation alone does not prove a memory leak or the absence of retained MATLAB objects.

`-RepeatedSelections` repeats the current target. `-AlternatingSelections` changes between two different targets and exercises retained Inspector rebinding. `-EnduranceOnly` omits normal selection/property samples so document retention can be explored within the same five-minute case limit. It still measures startup and Open and cannot be combined with profiling. Incomplete cycles remain partial results rather than being treated as a completed endurance test.

`-PropertyChanges` performs actual Inspector edits cycling five finite FontSize values, records them as `retention-property`, and checks that each requested value was committed. It also works with `-EnduranceOnly`, which selects a font-capable target first. The first edit and subsequent edits are separate phases. Document cycles reopen the fixture through the normal unsaved-change guard with Discard; each installed document gets a fresh snapshot identity.


## Display, insertion, and repeated Value updates

`runYamadaUpdateDistribution.ps1` uses a separate synthetic numeric-control fixture and leaves production source unchanged. It compares absolute, flat-grid, and nested-grid layouts with three panels, the requested number of NumericEditFields, and one Label. All component declarations are typed so ordinary insertion anchors are present.

```powershell
& tests/performance/runYamadaUpdateDistribution.ps1 -ComponentCount 12 -NestedDepth 8 -Samples 12 -Additions 6 -Profile
& tests/performance/runYamadaUpdateDistribution.ps1 -Cases flatgrid,nestedgrid -Samples 3 -Additions 2 -Trace:$true
& tests/performance/runYamadaUpdateDistribution.ps1 -Cases absolute,nestedgrid -Samples 100 -Additions 0 -Comparisons:$false
& tests/performance/runYamadaUpdateDistribution.ps1 -Samples 0 -Additions 12 -Comparisons:$false -Profile
```

`Samples` counts actual Value changes to the same NumericEditField. `Comparisons` also measures up to four Label FontSize and Text changes. `Additions` inserts Labels through the normal Palette callback; parent selection is timed separately. After insertions, the same original Value is edited again when `Samples` is positive. Each requested value and insertion count is checked. The final generated source is parsed and compared with the live document outside interactive timing.

`Fit` defaults to true; false uses flexible tracks only. Root and panel dimensions are fixed across layout variants. At very large counts, fit tracks can overflow the available viewport; preserve that case as a geometry stress test rather than calling it a successful boundary reconstruction. `Profile` records separate Value, Label FontSize/Text, insertion, and post-insertion Value profiles where those operations are enabled. Profile overhead is excluded from ordinary distributions.

`Trace` defaults to false. Enable it only for separate diagnostic runs: a 50ms measurement timer observes published geometry revisions and records the first observed unavailable/available states. Native event dispatch can delay sampling, so these are observed intervals, not exact screen-visible durations. The probe never changes editor callbacks or polling limits and is excluded from settling.

Completed samples record callback and settled wall time, layout poll count, native object/timer count, history index, status, and geometry state. `grid-state.json` retains the final value-only grid payload. A rejected post-insertion edit is recorded in `rejected-operation.json` and must be excluded from successful edit latency. Final source audit failure makes the case fail even when earlier samples were saved. Preserve partial results and classify startup/harness failures separately.

The supervisor saves source/fixture hashes, its exact harness, progress, profiles, and owned-process resource samples. Defaults are 300 seconds per operation, 600 seconds per profile, and 3600 seconds per case. The inner settling loop has a separate 240-second limit after callback return. The extended 200-control study uses explicit 600/1200/7200-second supervisor limits. These limits do not establish latency goals. Small samples and nearest-rank p95 remain exploratory.

The rendering acknowledgement belongs to the HTML overlay, not every native control. If an incremental change leaves the overlay payload unchanged, its revision and acknowledgement can be reused. Report these observations as MATLAB, layout, and overlay completion; they do not directly establish when each native widget or physical display finishes painting.

`ParentEachAddition=false` keeps the newly added Label selected for subsequent Palette insertions. It measures consecutive sibling insertion with the existing Inspector surface reuse. The default true explicitly selects the parent before every insertion; selection latency is recorded separately, while the insertion itself changes Inspector type from the parent to a Label.

`ProfileParentSelection` profiles each explicit parent selection before an addition. It labels those samples `profile-selection-add-parent` and saves the matching raw/profile JSON files; do not include them among ordinary selection times. The flag defaults to false. Combine it with `Profile` to collect property and parent-selection profiles in the same run.

`ExplicitValues=false` omits numeric Value assignments from the fixture so edits insert new settings. `AlternatingValueChanges` changes Field1 through the chosen `AlternatingTargetCount` repeatedly, timing selection separately and checking each committed value. Samples record `pendingValueOwners`, the number of numeric Value settings without an original source span. Final source audit compares every numeric field, including untouched fields at their known default zero.

```powershell
& tests/performance/runYamadaUpdateDistribution.ps1 -Samples 0 -Additions 12 -Comparisons:$false -ParentEachAddition:$false -Profile
& tests/performance/runYamadaUpdateDistribution.ps1 -Cases absolute,nestedgrid -Samples 0 -Additions 0 -Comparisons:$false -ExplicitValues:$false -AlternatingValueChanges 24 -Profile
```

`SurfaceHeight` defaults to 650 pixels, with a 1000-pixel source width. Use matching dimensions across layouts and report deliberate fit-overflow workloads separately.

`probeYamadaGridGeometry(FixturePath=...,OutputFolder=...)` separately renders the registered fixture controls without running the input class. It rebuilds grid boundary data directly at several settled times, records native positions and outer bounds, and compares measured fit/fixed minimum height plus spacing with available height. This distinguishes a persistent reconstruction limitation from application geometry-cache retention; it does not change editor behavior.

## Source update strategy experiment

`SourceStrategyExperiment` is a detached prototype for comparing source-update timing. Both strategies use the same catalog-based local literal validation and ordinary model history. Deferred mode keeps the immutable baseline and coalesced patches, caches the emitted result, and invalidates it after another edit. Eager mode rewrites the current source and bulk-shifts its complete experiment-owned position index after each edit. Immutable history/source-baseline positions are separate. Neither strategy silently falls back to the production generator during timed saves.

Run `python tests/performance/prepareSourceStrategyVariants.py` from the project root after verification. It creates two detached `yamada.m` builds and fixtures under `testResults/performance/source-strategy-20261031`, preserving production code. Then run `tests/performance/runSourceStrategyComparison.ps1` for the two-round ordinary comparison, and run it separately with `-Phase profiles -Profiled -Rounds 1` for call graphs. Existing output directories are never overwritten.

The UI harness uses actual hierarchy selection, Inspector callbacks, Preview updates, layout/HTML acknowledgement, and the Save menu. Selection, callback, settled edit, and save times are separate. Each of the 10/50/100-edit conditions begins from the same initial source; operations address different component/property pairs and change encoded lengths. The 100-edit workload mixes 50 insertions with 50 replacements. Source fixtures cover 200 fields with no Grid, single-level Grids, and eight nested Grid levels. Production defaults and other optimization work are held constant between the two prototypes.

Saving uses each strategy's own emitter and the same full parser/model diagnostics, known-state and parent checks, requested-value checks, saved position snapshot, intent re-emission check, and production UTF-8 writer. This is an experimental save adapter: Save As, external-edit protection, and complete Undo/Redo integration are not a claim of production readiness. Record these boundaries with results; prototype timings are not unchanged-main timings. Test invalid-literal atomicity and every retained occurrence position, including duplicate property statements, before adopting performance results.

Each profiled edit is captured independently and aggregated by `writeSourceStrategyProfile`; repeated `profile on` sessions must not discard earlier edits. Raw action graphs remain in the MAT artifact. Selection and artifact writing are excluded from edit profiling. Inclusive times overlap and must not be summed across parent/child functions. Audit source/fixture hashes, loaded variant paths, exact operation prefixes, histories, output bytes, requested values, position oracles, and automatic process-monitor records before comparing results.
