<!-- For contributors submitting a pull request: describe the change, its safety effects, and validation for reviewers. -->

## Change

Describe the concrete problem and resulting behavior. Link the related issue, if any.

## Scope and Safety

Describe effects on source preservation, Safe Preview, and the supported input/output contract. For documentation-only changes, state that runtime behavior is unchanged. Include UI examples when useful.

## Validation

- Checks run and results:
- Checks not run and why:
- MATLAB release and platform, when applicable:

## Checklist

- [ ] The change has one focused purpose and targets the intended integration or maintenance branch.
- [ ] Relevant checks pass; omitted checks are explained above.
- [ ] Documentation reflects any public behavior changes.
- [ ] `git diff --check` passes.
- [ ] Any `AGENTS.md` change is in its own commit, and the merge method preserves that separation.
