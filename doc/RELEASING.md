# Releasing yamada

This is the maintainer procedure for building, validating, publishing, and maintaining versioned MATLAB Toolbox releases. It defines the repeatable build workflow and release acceptance gates. The first planned release is `1.0.0`.

## Branches and Publication

Use the [contributor workflow](../CONTRIBUTING.md#branch-workflow): focused work branches and pull requests into `main`, with no permanent `develop`. `main` holds verified integrated development for the next release. A merge is not a publication. Use a release branch only when stabilization or maintenance must proceed in parallel with development.

Preserve cohesive commits. An `AGENTS.md` commit must contain only that file and must remain separate when merged; use a merge commit or rebase merge for a pull request that also contains other changes. Squash merging is suitable only when it does not violate this separation.

## Version Policy

Use `major.minor.patch`: `1.0.0` for the first stable release, `1.0.1` for compatible fixes, `1.1.0` for compatible feature additions, and `2.0.0` for breaking changes. Compatibility includes supported input source, preservation and generation behavior, and documented user workflows, not just callable MATLAB APIs. Describe intentional compatibility changes in release notes. MATLAB release compatibility such as R2024a is a separate setting.

Use `1.0.0` in Toolbox metadata, `v1.0.0` as the Git tag, `yamada 1.0.0` as the Release title, and `yamada-1.0.0.mltbx` as the asset name. Keep one authoritative version value when packaging is implemented and validate derived names against it. Keep the Toolbox UUID stable across versions.

The version, permanent UUID, author, public contact, description, and compatibility are defined in [`dev/release/toolbox.json`](../dev/release/toolbox.json). Use [`buildYamadaToolbox`](../dev/release/buildYamadaToolbox.m) to create a candidate, input manifest, and `SHA256SUMS`; see the [build procedure](../dev/release/README.md). The default output is ignored under `build/`. Existing candidates are not overwritten.

## Repository Settings

A repository administrator configures GitHub Settings > Rules > Rulesets with an active branch ruleset targeting `main`. This document describes the intended settings, not evidence that the remote configuration has been applied. Inspect any existing rules before adding another ruleset because overlapping rules also apply.

- Require a pull request before merging, with zero required approvals for sole-maintainer operation.
- Restrict deletions and block force pushes. Do not configure routine bypass actors.
- Do not require Code Owner approval or approval of the most recent push for sole-maintainer operation.
- Add required status checks only after the actual CI jobs exist and have been verified. Until then, maintainers inspect recorded local verification results in the pull request.
- Do not require linear history while merge commits are needed to preserve separate `AGENTS.md` commits. Keep at least one merge method available that preserves those commits.

Apply equivalent protection to maintenance branches when they are created. Enable Issues for bug reports. Keep the default branch as `main`. Automatic work-branch deletion is optional; retained maintenance branches must not be deleted inadvertently.

GitHub documents these controls in [Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets). If the current tooling cannot inspect or modify settings, ask the administrator to apply them and report the result; do not report a documented policy as an active protection rule.

## Prepare the Release

1. Confirm the version's supported feature set against `SPECIFICATION.md`. Classify known issues as release blockers or documented limitations. Source loss, corrupt saves, execution of input application code, and failure of essential installed workflows block publication.
2. Confirm the MATLAB releases, platforms, and required products actually verified. Initially target R2024a; declare only platforms validated for the artifact. Audit internal MATLAB dependencies and their failure behavior.
3. Reconcile README, specification, examples, and release notes with the implementation. Document installation, update, removal, limitations, and bug reporting. Use `yamada` as the normal launch command; reserve handle-returning forms for development and tests.
4. Audit runtime resources and redistribution rights. Package runtime MATLAB code, the release-specific JSON catalog, `EditorInteractionOverlay.html`, `RootResizeGuide.html`, `stabilize-request.js`, license notices, and appropriate user documentation. Explicitly exclude development tools, tests, investigation reports, logs, repository metadata, and build output. Keep investigation artifacts out of `main` under the project integration policy.
5. Review the explicit packaging inputs and metadata, then build with the R2024a-supported `matlab.addons.toolbox.ToolboxOptions` and `matlab.addons.toolbox.packageToolbox` procedure. Include the Apps gallery entry alongside the documented command, and verify both paths using the installed candidate.

## Validate the Candidate

Record the source commit, MATLAB release/update, operating system, commands, terminal results, and artifact SHA-256. Keep generated logs and measurement artifacts in ignored local results or the investigation branch. Relevant checks must finish successfully; progress output is not a passing result.

- Run the full MATLAB regression suite as described in `CONTRIBUTING.md`, relevant HTML/JavaScript checks, and applicable static and convention checks. Follow `AGENTS.md` for the Windows MATLAB account and waiting requirements.
- Build from the final intended source commit. Install the resulting Toolbox with the source checkout absent from the MATLAB path and confirm the resolved entry point belongs to the installed copy.
- Launch with `yamada` without parentheses or an output assignment. Verify the app survives startup and cleans up correctly when closed.
- Exercise New/Open, component and property editing, Validate, Diff Preview, Save/Save As, and reopen. Cover subtree operations, rename, callback management, and Undo/Redo.
- Verify source preservation and non-execution of input code. Exercise cancellation, external changes, save failures, Japanese and space-containing paths, and startup from another working folder.
- Check runtime resource discovery, cleanup of figures/listeners/timers, and uninstallation. For updates, test replacement of an installed earlier version and verify the stable Toolbox identity and resolved paths.

If candidate code or packaged contents change, repeat affected checks and rebuild. Final validation must identify the exact commit and artifact to publish, including after integration into `main`.

## Publish

1. Prepare a maintainer GPG-signed final release commit on a work branch and integrate it through a PR while preserving that signed commit. Build from that exact clean revision, resolve remaining blockers, and complete final artifact acceptance. Have the maintainer prepare the detached `.mltbx.asc` signature before requesting publication authorization. If a separate merge commit is used, verify the intended release tree and repeat affected acceptance checks after integration.
2. Prepare a draft GitHub Release with the version, source commit, `.mltbx`, `.mltbx.asc`, `SHA256SUMS`, supported environments, installation and `yamada` launch instructions, features, known limitations, and changes from the prior release. Use the [Release text draft](../dev/release/RELEASE_NOTES.md). GitHub's automatic source archives are distinct from the installable Toolbox asset.
3. Obtain the maintainer's final authorization before pushing the release tag or publishing. When an agent prepares the release, present the concrete artifact and release text for that decision.
4. Have the maintainer GPG-sign the `v<version>` tag pointing to the accepted source commit, then push the tag and publish the matching assets. Verify that source identity, Toolbox metadata, asset name, checksum, and release notes agree. Hardware-key interaction belongs to the maintainer; do not publish an unsigned substitute if signing fails.
5. Download the published asset and verify its checksum and public documentation links. Record completion without committing generated measurement reports to `main`.

Never move a published tag or replace its artifact to repair a release. Explain serious known problems on the Release page, direct users to a safe version, and publish a new patch release.

Do not add public-key fingerprints or signature/checksum verification tutorials to user-facing documentation. Release assets still include the detached GPG signature and SHA-256 checksum list. Maintainers validate these artifacts before publishing.

## After Release

Monitor issues and reproduce reports with the installed version and stated environment. Route fixes through work branches and pull requests. Continue normal development on `main` without changing published tags.

If `main` already contains later features, create `release/<major>.<minor>` from the published tag to maintain that release line. Prefer fixing on `main` and backporting only required commits through a maintenance pull request. For a maintenance-only fix, explicitly assess and record applicability to `main`. Validate and publish each patch using the same candidate and publication gates.

Keep completed work out of `ROADMAP.md`; preserve unfinished successor work and consolidate durable implementation contracts in `doc/ARCHITECTURE.md`. Improve issue templates and CI incrementally. File Exchange distribution and additional MATLAB/platform support are follow-up work, each with its own verification.
