# yamada 1.0.0 Release Plan

This is the progress and acceptance plan for the first release, reconstructed from the agreed plan in the release-preparation conversation. The reusable maintainer workflow is in [RELEASING.md](RELEASING.md). Update stage status and acceptance evidence in the relevant pull requests. Completion of an audit stage does not mean the release has passed its later validation gates.

## Fixed Decisions

- Publish `1.0.0` as `v1.0.0`, Release title `yamada 1.0.0`, and asset `yamada-1.0.0.mltbx`.
- Support MATLAB R2024a on 64-bit Windows with a graphical session and JVM. Other releases, operating systems, MATLAB Online, and headless operation are outside the release contract.
- Use `yamada` as the normal documented command, with neither parentheses nor an output assignment. Include an Apps gallery entry in the first Toolbox and test both launch paths.
- Retain the existing supported feature set and source-safety boundaries. Do not add roadmap features or require a broad refactor for release. File Exchange, additional platform support, and automated CI are follow-up work.
- Use work branches and pull requests into `main`; no permanent `develop`. Published tags fix releases. Create a maintenance branch only when needed. Keep `AGENTS.md` changes in separate commits and preserve that separation when merging.

## Stage 1: Workflow and Plan Persistence

Status: workflow complete; plan persisted in this change, pending pull request integration.

- PR [#1](https://github.com/NOBUTOKA/yamada/pull/1), merged as `011d073`, added contributor/agent branch rules, the PR template, and the reusable release procedure. Its two commits preserve the separate agent-instruction change.
- The active `main` ruleset requires a PR, zero approvals, no routine bypass, and blocks deletion and force pushes. Issues are enabled. Required CI checks are deferred until real jobs exist; merge commits remain allowed.
- GitHub App installation now includes `NOBUTOKA/yamada`. Windows OpenSSH authentication, repository reads, and push dry-run succeeded; the investigation archive has also been pushed through SSH. Keep HTTPS `origin` and its upstreams for Desktop; specify the SSH remote for CLI pushes.
- Persist this plan and verify creation of its draft PR through the repaired connector. A local document alone is not evidence of a native Codex UI plan entry.

Acceptance: the plan and workflow documents are merged, with review and verification records available. Maintainer approval is required for PR merge unless explicitly delegated.

## Stage 2: Freeze Scope, Known Issues, and Distribution Inputs

Status: contract and source audit complete on the stage-2 work branch; pull request review/integration pending. Release gates R1/R2 are explicitly unresolved.

- `SPECIFICATION.md` defines the selected 1.0.0 contract. README now matches callback-omitting Copy while retaining Cut/Delete safeguards, and uses the normal no-output launch command. Unsupported source, expressions, component references, and incomplete native hierarchy workflows keep their existing boundaries.
- MATLAB runtime dependency analysis identifies MATLAB only. Java/JVM, native graphical UI, release-specific browser integration, installation images, and all dynamically loaded HTML/JavaScript/JSON are explicit dependencies. Development tools are not runtime requirements.
- The complete runtime resources and internal-dependency failure boundaries are recorded in the architecture reference. Catalog and browser resources must be explicitly included in packaging, not inferred solely from MATLAB dependency analysis.
- [Source and resource provenance](THIRD_PARTY_NOTICES.md) separates project code, documentation-derived data, MATLAB-installation assets, fixtures, and user output. No separate permission exists for documentation transcriptions; gate R2 remains unresolved.
- The three root `PERFORMANCE_*.md` plans/reports were preserved unchanged on `codex/investigation-pre-v1` before removal. The roadmap retains unfinished overlay, Inspector, source-range, and matched-measurement work; completed implementation contracts remain in the architecture reference. No Git history was rewritten.
- Focused verification passed: CallbackCopyTest (5), PropertySaveCheckpointTest (11), and PreviewLayoutStabilizationTest (7), with 23 passed, zero failed/incomplete, on R2024a Update 8 / PCWIN64. Local evidence is under ignored `testResults/release-contract/` (dependency inventory, MATLAB terminal log, and test results). This is not the final full regression or installed-artifact acceptance.

Acceptance: selected scope, dependencies, known limitations, and concrete pre-publication gates are documented; preservation of investigation records is verified; focused checks pass. Unresolved release gates below must not be described as fixed.

## Pre-Publication Gates Identified During Stage 2

| Gate | Finding and required resolution | Acceptance |
| --- | --- | --- |
| R1: protect an existing file on write failure | `SourceWriter.write` opens the target with `wb` and writes directly. The lifecycle catches failure and preserves the in-memory checkpoint, but cannot restore bytes truncated or partially written on disk. Add a separate source-safe save change before release: stage and close the complete output beside the target, validate it, and replace the target only through a failure-safe replacement policy. | Fault-injection tests cover write, close, and replacement failure for existing and new targets, preserve original bytes and in-memory history/checkpoints on failure, and clean temporary files. Rerun relevant save/lifecycle suites. Do not claim crash/power-loss durability without evidence. |
| R2: documentation-derived text and source provenance | No separate redistribution permission is recorded for MathWorks documentation transcriptions. Runtime metadata contains short descriptions; development records contain additional transcribed text. Review the tagged source as well as `.mltbx`; excluding `dev` from the package alone is insufficient. | Identify retained explanatory text and replace it with independently authored text, remove it, or establish an applicable redistribution basis. Retain API facts, original third-party notices, and provenance. Verify catalog-generation/parity behavior after changes and clarify preserved-fixture provenance before reusing inputs as examples. |
| R3: package and Apps installation | No release packager or validated installed Apps entry exists yet. Static resource paths and source-checkout tests do not establish installed behavior. | Complete stages 3 and 4 with the exact candidate artifact, including both no-output launch paths and cleanup. |
| R4: final regression and distribution acceptance | Historical test results and focused stage-2 checks do not certify the final candidate. | Complete stage 4 on the final source/artifact and retain terminal summaries and artifact identity. |

R1 and R2 must be resolved in focused follow-up changes before declaring a publishable candidate. They do not authorize unrelated feature work or a change to source-preservation guarantees. Record resolutions here and in the relevant PRs; do not silently convert a release blocker into a user warning.

## Stage 3: Build the Toolbox, Apps Entry, and User Documentation

Status: not started. Resolve R1/R2 as follow-up work before candidate acceptance.

- Implement reproducible R2024a `ToolboxOptions`/`packageToolbox` packaging with one version source, a stable UUID, metadata, supported release/platform limits, explicit file inclusion, and minimal path additions. Do not ship MATLAB installation files, test/development tools, investigation reports, or build output.
- Include runtime sources, all catalog/HTML/JavaScript resources, the license/provenance notices, appropriate user documentation, and a small independently owned example. Write artifacts, manifests, and checksums into ignored build results.
- Register an Apps gallery entry. Prefer the main `.m` entry; add a minimal launcher only if required by R2024a. Keep the application programmatic and handle-based. Custom artwork is optional for registration; use only provenance-clear artwork and verify actual gallery presentation.
- Prepare install, update, removal, command/Apps startup, tutorial, screenshots, known limitations, initial change history, and draft release text. Switch statements about release availability only when publication is imminent and truthful.

Acceptance: a repeatable artifact build from an identified commit with explicit content/version checks, and both launch paths ready for installation verification.

## Stage 4: Validate the Release Candidate

Status: not started.

- Run the full MATLAB regression, relevant browser/Node checks, and static/convention checks on the candidate. Use the interactive licensed account and monitored, durably logged execution; wait for terminal results.
- Install the Toolbox in a separate MATLAB session with the source checkout removed from its path. Confirm `which` resolves the installed entry and resources load from the installed distribution.
- Exercise New/Open, editing, Validate, Diff, Save/Save As, reopen, subtree operations, rename, callbacks, and Undo/Redo. Verify unsupported source retention and non-execution of input code.
- Test cancellation, external changes, save failures, Japanese/space-containing paths, another working folder, local assets, both launch paths, repeated launches, owner lifetime, and figure/listener/timer cleanup.
- Test uninstallation, path/gallery removal, and same-UUID reinstallation. An earlier-version upgrade test becomes mandatory for the first patch release because no prior stable version exists for 1.0.0.
- Record the source commit, MATLAB update, OS, commands, final counts, artifact SHA-256, and failure outcomes in ignored results. Rebuild and repeat affected checks after changes; verify final integrated source and artifact correspond.

Acceptance: no unresolved release blockers or unexplained incomplete mandatory checks; exact publishable artifact and source identified.

## Stage 5: Publish and Verify 1.0.0

Status: not started.

- Merge reviewed preparation PRs and complete final candidate acceptance. Prepare a draft Release with the Toolbox, SHA-256, installation/startup instructions, supported environments, features, and limitations.
- Present the concrete artifact and release text for final maintainer authorization before pushing `v1.0.0` or publishing. Do not merge, tag, or publish solely because the preparation task was authorized.
- Tag the verified commit, publish the matching Release and artifact, and download the public asset to verify identity and links. GitHub's source ZIP is not the installable Toolbox.
- Remove completed packaging tasks from the roadmap, retain unfinished successor work, and mark this plan complete through a follow-up PR without moving the release tag.

Acceptance: fixed source tag, matching downloadable artifact, working public instructions, and recorded post-publication verification.

## After Release

- Reproduce issues with the installed version and declared environment. Use `1.0.1` for compatible fixes, `1.1.0` for compatible additions, and `2.0.0` for breaking contracts. Never repair a published release by moving its tag or replacing its asset.
- If `main` has advanced, create and protect `release/1.0` from the published tag; backport only required fixes through PRs and record applicability to `main`. Test upgrades from the earlier installed version.
- Improve issue templates, CI, automated packaging, and File Exchange distribution as separate follow-ups. Widen MATLAB/platform support only after independent validation.
