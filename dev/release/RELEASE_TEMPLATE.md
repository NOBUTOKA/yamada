# GitHub Release template

Use the title and body below when preparing a draft. Replace every placeholder. Use the version without the `v` prefix for `{{VERSION}}` and include the prefix in `{{PREVIOUS_TAG}}`. Update the requirements paragraph if the supported environments change.

## Title

```text
v{{VERSION}}
```

## Body

```markdown
### Changelog
- {{USER_VISIBLE_CHANGE}}

**Requires MATLAB R2023a through R2026b on 64-bit Windows** with a graphical session, JVM, and .NET support. On R2026b, install MATLAB Support for OpenJDK or another supported OpenJDK distribution first. See the [supported format and limitations](https://github.com/NOBUTOKA/yamada/blob/v{{VERSION}}/SPECIFICATION.md).

Close yamada, download `yamada-{{VERSION}}.mltbx` from **Assets**, and open it in MATLAB to install or update. Enter `yamada` in the Command Window or select **yamada** in the **Apps** tab. [Getting Started](https://github.com/NOBUTOKA/yamada/blob/v{{VERSION}}/doc/GETTING_STARTED.md)

Use `yamada-{{VERSION}}.mltbx.sha256` to check the download for corruption and `yamada-{{VERSION}}.mltbx.asc` to verify its authenticity. The signing key's primary fingerprint is `EC162591100908006F1F7B0BFCA5A6716AD79C55`. [Public key on keys.openpgp.org](https://keys.openpgp.org/vks/v1/by-fingerprint/EC162591100908006F1F7B0BFCA5A6716AD79C55) · [GitHub copy](https://github.com/NOBUTOKA.gpg)

Built from [`{{SHORT_COMMIT}}`](https://github.com/NOBUTOKA/yamada/commit/{{FULL_COMMIT}}).

[Full Changelog](https://github.com/NOBUTOKA/yamada/compare/{{PREVIOUS_TAG}}...v{{VERSION}})
```
