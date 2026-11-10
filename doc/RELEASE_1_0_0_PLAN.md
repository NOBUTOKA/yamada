# yamada 1.0.0 Release Plan

This is the progress and acceptance plan for the first release, reconstructed from the agreed plan in the release-preparation conversation. The reusable maintainer workflow is in [RELEASING.md](RELEASING.md). Update stage status and acceptance evidence in the relevant pull requests. Completion of an audit stage does not mean the release has passed its later validation gates.

## Fixed Decisions

- Publish `1.0.0` as `v1.0.0`, Release title `yamada 1.0.0`, and asset `yamada-1.0.0.mltbx`.
- Support MATLAB R2024a on 64-bit Windows with a graphical session and JVM. Other releases, operating systems, MATLAB Online, and headless operation are outside the release contract.
- Use `yamada` as the normal documented command, with neither parentheses nor an output assignment. Include an Apps gallery entry in the first Toolbox and test both launch paths.
- Retain the existing supported feature set and source-safety boundaries. Do not add roadmap features or require a broad refactor for release. File Exchange, additional platform support, and automated CI are follow-up work.
- Use work branches and pull requests into `main`; no permanent `develop`. Published tags fix releases. Create a maintenance branch only when needed. Keep `AGENTS.md` changes in separate commits and preserve that separation when merging.

## Stage 1: Workflow and Plan Persistence

Status: complete. The persisted plan and stage-2 documents were integrated by PR #2 (`d38737f`).

- PR [#1](https://github.com/NOBUTOKA/yamada/pull/1), merged as `011d073`, added contributor/agent branch rules, the PR template, and the reusable release procedure. Its two commits preserve the separate agent-instruction change.
- The active `main` ruleset requires a PR, zero approvals, no routine bypass, and blocks deletion and force pushes. Issues are enabled. Required CI checks are deferred until real jobs exist; merge commits remain allowed.
- GitHub App installation now includes `NOBUTOKA/yamada`. Windows OpenSSH authentication, repository reads, and push dry-run succeeded; the investigation archive has also been pushed through SSH. Keep HTTPS `origin` and its upstreams for Desktop; specify the SSH remote for CLI pushes.
- Persist this plan and verify creation of its draft PR through the repaired connector. A local document alone is not evidence of a native Codex UI plan entry.

Acceptance: the plan and workflow documents are merged, with review and verification records available. Maintainer approval is required for PR merge unless explicitly delegated.

## Stage 2: Freeze Scope, Known Issues, and Distribution Inputs

Status: contract and source audit merged in PR #2. Remediation substeps 2A/R1 and 2B/R2 below are planned and not implemented; both gates remain open.

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
| R1: protect an existing file on write failure | `SourceWriter.write` opens the target with `wb` and writes directly. The lifecycle catches failure and preserves the in-memory checkpoint, but cannot restore bytes truncated or partially written on disk. Implement stage 2A before release. | Fault tests cover write, close, replacement, and recovery failures. Original bytes remain at the target or in an explicitly reported recovery backup if restoration itself fails; checkpoint state follows the actual publication outcome. Do not claim crash/power-loss durability without evidence. |
| R2: documentation-derived text and source provenance | No separate redistribution permission is recorded. Short factual labels and API facts must be assessed separately from protectable expression or arrangement. Review the tagged source as well as `.mltbx` and specifically identified historical concerns under stage 2B. | Independently author avoidable explanatory text or establish the applicable retention basis; retain API facts and notices. Verify regeneration/parity and record any concrete historical disposition. Do not infer either infringement or mandatory history rewriting from a documentation reference alone. |
| R3: package and Apps installation | No release packager or validated installed Apps entry exists yet. Static resource paths and source-checkout tests do not establish installed behavior. | Complete stages 3 and 4 with the exact candidate artifact, including both no-output launch paths and cleanup. |
| R4: final regression and distribution acceptance | Historical test results and focused stage-2 checks do not certify the final candidate. | Complete stage 4 on the final source/artifact and retain terminal summaries and artifact identity. |

R1 and R2 must be resolved in separate implementation pull requests before declaring a publishable candidate. R2 requires a specific rights/content assessment, not an assumption that every documentation-derived API fact infringes copyright or that every historical commit must be rewritten. Neither gate authorizes unrelated feature work or weaker source-preservation guarantees. The current pull request updates plans and provenance guidance only.

### Stage 2A / R1: Failure-Safe Source Saving

Deliver one implementation PR from up-to-date `main`, followed by stage 2B in its own PR. Retain `SourceWriter.write(filePath, source, lineEnding)` and the existing lifecycle write seam. Keep encoding, generated text, Save/Save As prompts, history, and checkpoint publication behavior unchanged.

1. Add a small internal filesystem transaction adapter with injectable I/O operations for deterministic fault tests; production calls use real filesystem operations. Normalize and encode before I/O. Create an exclusively owned, uniquely named staging file in the target directory using create-new semantics, write all bytes, check write status and explicit close success, and read back the staged bytes before touching the destination. Do not stage on another volume or truncate the destination as a fallback.
2. On supported Windows, use the documented .NET `System.IO.File.Replace(staging, target, uniqueBackup, false)` for an existing regular file, retaining metadata/ACL merge errors as failures. Use the non-overwriting two-argument `System.IO.File.Move` for a new target so a competing file is never replaced implicitly. Verify MATLAB R2024a .NET invocation on the actual host before committing the implementation. A local PowerShell feasibility probe passed replacement-with-backup, rejection of a locked target, and non-overwriting move collision; that is not MATLAB verification or proof of every failure mode.
3. Record the original bytes and file state before replacement. Recheck the destination immediately before publication and reject a detected external change; this narrows the race but is not an interprocess compare-and-swap guarantee. Preserve existing replacement approval rules. Do not replace read-only files, directories, or linked/reparse-point targets by silently changing their permissions or dereferencing them; unsupported target semantics must fail before modification. Reject unsafe new-file paths whose resolved directory is unsuitable. Do not claim network, non-NTFS, or other-filesystem behavior without explicit tests; where the required primitive is unavailable, reject saving safely rather than falling back to destructive overwrite.
4. Treat publication as the commit point. Windows replacement can fail after the old file has moved to its backup name, so do not assume that an exception leaves the target unchanged. Inspect the transaction's own paths and verify bytes; restore the original path only when it is safe and will not overwrite an unrelated concurrent change. If recovery cannot finish, retain the original backup, include its exact recovery path in the save error, and preserve the dirty document and checkpoint. Never delete the only remaining original copy during cleanup.
5. After successful publication, cleanup failures must not be reported as an ordinary pre-publication save failure while leaving the checkpoint stale. Preserve a usable new file and report any retained cleanup/recovery path separately. Keep failure handling and cleanup narrow enough that it cannot delete user files or backups owned by another attempt. No new normal-flow dialog is required. Do not promise power-loss durability, stable file IDs/hard-link identity, or unsupported-volume atomicity.
6. Add meaningful writer fault-injection tests for staging open/write/short write/close/read-back failure, locked/read-only target, destination collision/change, replacement failure with target unchanged, old file moved to backup, rollback failure, and cleanup failure after commit. Assert exact original/new bytes, recovery-file retention, no unrelated deletion, UTF-8 without BOM, CRLF/LF, and Japanese/space-containing paths. Include real Windows temporary-file tests for .NET replacement, ACL preservation, and new-file collision, not just mocks.
7. Extend lifecycle coverage to prove failed pre-publication writes retain FilePath, dirty state, saved-source checkpoint, history, and external-change state, including Save As. Verify successful publication advances the checkpoint once and retains Undo/Redo. Run writer tests, PropertySaveCheckpointTest, and EditorLifecycleTest; check project conventions and relevant static analysis. The final release full suite remains stage 4.

Acceptance: original contents remain at the target on ordinary failures, or are retained in an explicitly reported recovery backup if rollback itself fails; no failure silently destroys the only original copy. Successful publication and in-memory save state agree. Document the exact filesystem support and recovery boundary, and close R1 only after terminal test results pass. If Windows/.NET behavior cannot satisfy this contract, revise the adapter design with evidence before implementing a weaker fallback.

### Stage 2B / R2: Catalog Text and Redistribution Review

Deliver a separate content/tooling PR after R1. Follow the [provenance review policy](THIRD_PARTY_NOTICES.md#replacement-and-retention-policy). Its job is to remove avoidable dependence on upstream wording while preserving API facts, catalog capabilities, normal UI behavior, and reproducible generation. It is not a blanket relicensing or automatic history-rewrite task.

1. Inventory property summaries, runtime descriptions, default/accepted-value fields, category labels/order, copied examples/images, generated documentation, and development summaries. Separate project-authored policy/effect text from upstream wording. Keep the detailed field-level review and Git-history scan under ignored results; commit the resulting durable policy, source references, and resolutions without republishing copied passages as an audit appendix.
2. Preserve exact API names, class names, enum tokens, actual literal defaults, numeric limits, and type/shape facts. Keep source URLs and runtime verification provenance. Independently author descriptive summaries where they contain avoidable upstream wording; common functional labels such as a property name or type name need not be changed merely to differ from the reference. Remove explanatory prose from default/value fields or express its facts in canonical project-owned terms, without altering supported values. Do not use a character-count threshold or synonym substitution as a legal clearance test.
3. Review category selection/order separately as a possible compilation/arrangement question. Retain ordinary API-derived categories and existing interaction order unless a concrete issue is identified. Do not silently reorder the Inspector or remove properties as a licensing workaround. Escalate a substantiated arrangement concern for a maintainer decision before changing the product contract.
4. Update the development schema/help and audit guidelines so summaries are project-authored and value fields store canonical API facts, rather than requiring verbatim official headings. Keep the existing field layout where practical. The promotion script currently copies `summary` into runtime `metadata.description`; regenerate the entire runtime catalog from the reviewed development data instead of hand-editing only the runtime copy. Update exact-heading assertions and any scripts that parse raw wording, especially finite-enum normalization and multiline Text detection, to use reviewed semantic contracts. Test that type, values, defaults, editability, Preview policy, callback classification, parent rules, grouping, and generation behavior remain equivalent.
5. Cover both the `.mltbx` inclusion list and the complete future release-tag tree, including `dev`, tests/fixtures, and documentation. Retain original notices. Do not assume that exclusion from the Toolbox resolves a source-archive issue, that attribution grants reuse rights, or that adding a GPL header changes third-party rights. Do not include existing fixtures as public examples without establishing their origin; use a new clearly project-owned example later.
6. Inspect relevant current and historical refs read-only, including the investigation archive branch and renamed paths. Identify the first/last affected commits and reachable branches/tags only for specifically questionable content. Default to a normal corrective commit for the current release tree; do not force-push, delete refs, rewrite history, or duplicate questionable material onto another public archive. Historical API facts/ordinary labels alone do not trigger rewriting.
7. If concrete protected expression or an applicable contractual restriction remains in public history, record it separately from current-tree remediation. Before closing R2, obtain a maintainer disposition supported by applicable rights/permission or qualified advice as needed. A current-tree rewrite is not retrospective permission. Any necessary purge/repository migration is a separately authorized operation with a scoped ref/clone/fork/cache plan; never infer authorization from this release plan. Do not claim that retaining history is automatically lawful or that history rewriting erases all prior copies.
8. Run development schema and policy checks, catalog promotion/parity checks, ComponentCatalogLoaderTest, ComponentRegistryBaselineTest, and affected catalog/Inspector tests. Compare semantic capability snapshots before/after with presentation descriptions isolated, and verify deterministic regeneration. Review tooltip examples for clarity and factual accuracy. Close R2 only when current content, licensing/provenance notices, and any concrete historical concern have explicit dispositions.

Acceptance: no unreviewed explanatory transcription is carried into the release tree, required API facts and behavior remain intact, regeneration cannot restore removed wording, and historical handling is explicitly recorded without an unapproved destructive operation. The exact replacement set comes from this field-level assessment; the existence of documentation references alone is not evidence of infringement.

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
