# Instructions for Coding Agents

These instructions govern the development of yamada. Project coding conventions do not apply to user application source handled by yamada; its output contracts are defined in `SPECIFICATION.md`.

## Project Invariants

- Keep yamada as a programmatic MATLAB application using ordinary `.m` files, not `.mlapp`.
- During parsing and Preview, execute only explicitly allowlisted MATLAB operations; never execute arbitrary user-supplied code.
- Preserve unsupported or ambiguous input source. Modify only source regions whose ownership is established.
- Keep document state in the model; UI and Preview state are derived views.
- Maintain the declarative component catalog rather than hard-coding capabilities.
- Consult `doc/ARCHITECTURE.md` when changing architectural boundaries, source handling, validation, or generation.

## Source Conventions

These conventions apply to project-owned source code.

### Formatting and Documentation

- MATLAB source and test `.m` files must use UTF-8 without a BOM and CRLF line endings.
- Write MATLAB comments and documentation in English.
- Document every function and method, including test methods and local helpers, immediately after its declaration.
- Provide class help immediately after `classdef`, describing the class's purpose and responsibilities, with a usage example when useful.
- Start class and method H1 lines with the exact declared name and capitalization.
- Document every publicly readable property immediately before its declaration, using its declared name as the H1 name.
- Add a concise comment before each meaningful group of operations, such as validation, model mutation, traversal, generation, I/O, and cleanup.
- Explain non-obvious intent and implementation constraints without commenting self-evident code.
- Write each Markdown prose paragraph on one source line without hard-wrapping. Preserve structural line breaks.

### MATLAB Types and Interfaces

- Add `arguments (Input)` and `arguments (Output)` blocks to every function and method you add or modify. Omit empty blocks. Do not use them in nested functions or `methods (Test)` methods, where MATLAB forbids them, or in handle-class `delete` methods, where validation prevents MATLAB from recognizing the destructor.
- Prefer `string` and double-quoted literals. Use `char` or character-vector cell arrays only at compatibility boundaries.
- Use typed object arrays for homogeneous class instances; use cell arrays only for intentionally heterogeneous or genuinely unknown types.
- Declare a property class whenever all accepted values share one class. Do not add size constraints to property declarations.
- Make implementation state `Access = private`. Use `SetAccess = private` for state that other classes only read. Grant broader access, including `?ClassName` access lists, only to the classes that need it.

### Exceptions

- Preserve input fixtures as test data without imposing project coding conventions.
- Follow `SPECIFICATION.md` and `doc/ARCHITECTURE.md` when changing application source generation or editing.

## Verification

- Before each commit, run the test files or `area` profiles of `tests/runYamadaTests.m` that cover the changed code.
- Run the `full` profile before submitting a pull request and before a release. Documentation-only changes use the checks in `CONTRIBUTING.md`, which also lists commands and additional checks.
- Report completed test results and identify checks that could not be run.

### Long-Running Tests

- Avoid frequent polling during long-running tests.
- Prefer completion notifications or long waits based on recent test durations. Maintain process monitoring and durable logs without repeated model-side inspection.
- A wait timeout does not mean the test has stopped. Verify the existing process before restarting it.

## Git and Contribution Workflow

- Follow `CONTRIBUTING.md` for branches and pull requests, and `doc/RELEASING.md` for releases.
- Inspect the working tree before editing and preserve unrelated changes.
- Treat Git history as project documentation. Make coherent, independently reviewable commits that explain the progression of work.
- Proactively commit completed logical implementation units after relevant checks pass, and check `git status` before finishing a file-changing task.
- Keep commits focused and exclude unrelated changes.
- Prefer amending the relevant unpushed commit for corrections that preserve its purpose; create a new commit for distinct changes.
- Do not commit when explicitly instructed otherwise or when relevant tests fail.
- Submit changes through pull requests to `main`, or to the maintained `release/<major>.<minor>` branch for a maintenance fix.
- Keep investigation reports, experimental plans, benchmark results, and generated measurement artifacts out of `main`. Record durable architectural contracts in `doc/ARCHITECTURE.md`.

## License Notices

The project uses `GPL-3.0-or-later`.

- **MATLAB `.m` files:** Place the complete English GPL notice in a trailing block comment to preserve MATLAB's `help` and `doc` behavior. Copy the exact notice from an existing project-owned `.m` file.
- **Other project-owned source files:** Begin with the three-line SPDX license notice used by existing files of the same type.
- **Third-party files and input fixtures:** Preserve their original license notices.
- **Application source handled by yamada:** Follow the output contract in `SPECIFICATION.md` rather than project license conventions.
