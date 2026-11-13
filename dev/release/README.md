# Building yamada release candidates

For maintainers building and signing a Toolbox candidate, this guide describes the build inputs, output files, and signing command.

Add `dev/release` to the MATLAB path and run `buildYamadaToolbox`. The build requires MATLAB R2024a on Windows. Its default output is the ignored `build/1.0.1` directory; pass a new output folder to keep multiple candidates. Existing output files are never replaced.

```matlab
addpath(fullfile(pwd, "dev", "release"));
artifacts = buildYamadaToolbox;
```

`toolbox.json` is the authoritative source for version, permanent UUID, author, public email, summary, description, and release compatibility. The packager explicitly selects runtime code, resources, user documents, screenshots, and the project-owned example. Only the installed distribution root is added to the MATLAB path. The Apps gallery launches `yamada.m` directly.

The build produces the `.mltbx`, `SHA256SUMS`, and a local `build-manifest.json` containing the source commit, dirty-state flag, MATLAB version, selected input hashes, and artifact SHA-256. A build from a dirty tree is a development candidate, not a publishable release. File timestamps and packager-generated metadata can vary between runs; reproducibility means repeatable source selection and configuration, not byte-identical archives.

## Final source and signatures

GPG-sign the final release commit on a work branch. Integrate it through a PR while preserving the signed commit; a merge commit can have a different signature. The release tag and package manifest must identify that signed source commit. If a separate merge commit is used, verify the intended release tree and repeat affected acceptance checks after integration.

Build from that signed commit in a clean checkout, complete candidate validation, and prepare its detached signature using PowerShell:

```powershell
./dev/release/Complete-YamadaRelease.ps1 -Artifact ./build/1.0.1/yamada-1.0.1.mltbx -SigningKey <signing-key> -ReleaseBranch release/1.0
```

The script checks candidate identity, SHA-256, clean-build provenance, integration into the release branch, and the release commit's GPG signature before invoking GnuPG. GnuPG may request a passphrase, PIN, or hardware-key confirmation. A signing error is a publication blocker. Keep the detached signature outside the Toolbox.

Publish the accepted `.mltbx`, its `.mltbx.asc`, and `SHA256SUMS` as Release assets. Keep the build manifest as local verification evidence. Sign `v1.0.1` and make it point to the same release source commit.

See the [release procedure](../../doc/RELEASING.md) for candidate acceptance and publication.
