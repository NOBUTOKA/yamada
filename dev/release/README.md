# Building yamada release candidates

Add `dev/release` to the MATLAB path and run `buildYamadaToolbox`. The build requires MATLAB R2024a on Windows. Its default output is the ignored `build/1.0.0` directory; pass a new output folder to keep multiple candidates. Existing output files are never replaced.

```matlab
addpath(fullfile(pwd, "dev", "release"));
artifacts = buildYamadaToolbox;
```

`toolbox.json` is the authoritative source for version, permanent UUID, author, public email, summary, description, and release compatibility. The packager explicitly selects runtime code, resources, user documents, screenshots, and the project-owned example. Only the installed distribution root is added to the MATLAB path. The Apps gallery points directly to `yamada.m`; no custom installer or `.mlapp` conversion is involved.

The build produces the `.mltbx`, `SHA256SUMS`, and a local `build-manifest.json` containing the source commit, dirty-state flag, MATLAB version, selected input hashes, and artifact SHA-256. A build from a dirty tree is a development candidate, not a publishable release. File timestamps and packager-generated metadata can vary between runs; reproducibility means repeatable source selection and configuration, not byte-identical archives.

## Final source and signatures

Prepare the final release commit on a work branch and have the maintainer GPG-sign it. Integrate it through a PR while preserving the signed commit; a merge commit can have a different signature. The release tag and package manifest must identify the maintainer-signed source commit. If a separate merge commit is used, verify the intended release tree and repeat affected acceptance checks after integration.

Build from that exact signed commit in a clean checkout. Do not change or sign an earlier development candidate. After candidate acceptance, prepare the detached signature using PowerShell so the concrete signed assets are ready for the maintainer's final publication authorization:

```powershell
./dev/release/Complete-YamadaRelease.ps1 -Artifact ./build/1.0.0/yamada-1.0.0.mltbx -SigningKey <maintainer-key>
```

The script checks candidate identity, SHA-256, clean-build provenance, integration into `main`, and the release commit's GPG signature before invoking GnuPG. Hardware-key interaction belongs to the maintainer. A signing error is a publication blocker. Keep the detached signature outside the Toolbox.

Publish the accepted `.mltbx`, its `.mltbx.asc`, and `SHA256SUMS` as Release assets. Keep the build manifest as local verification evidence. Sign `v1.0.0` and make it point to the same release source commit; push the tag and publish only with final authorization. Do not add public-key fingerprints or signature/checksum tutorials to user documentation.

`RELEASE_NOTES.md` is the draft Release text. Source and installer acceptance checks remain mandatory before publication; a successful package build alone does not satisfy them.
