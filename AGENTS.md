# Project instructions

- MATLAB source files and test files must use UTF-8 encoding without a BOM.
- MATLAB source files and test files must use CRLF line endings.
- Write comments in MATLAB source files in English.
- Every project-owned MATLAB function and method, including test methods and
  local test helpers, must have an English docstring comment immediately after
  its function declaration. The docstring must briefly state the purpose and,
  where useful, describe inputs, outputs, or important side effects.
- Start class and method H1 help lines with the exact declared name and
  capitalization, such as `% ComponentRecord ...` or `% setProperty ...`.
  Do not force class or method names to all uppercase. MATLAB documentation uses
  uppercase H1 names for many standalone functions, but its class-help examples
  preserve the declared capitalization of classes and methods.
- Every project-owned MATLAB class must have English class help immediately after
  its `classdef` line. Include an H1 overview, a short description of the class's
  responsibilities and boundaries, and a concise usage example when it improves
  understanding. Test classes may omit the usage example when it adds no value.
- Newly generated AppBase class output must follow the same English class and
  method help conventions, while remaining subject to the separate rule that
  user output does not receive the editor project's GPL notice automatically.
- Use explicit `arguments (Input)` and `arguments (Output)` blocks whenever the
  MATLAB function signature and supported value types make validation practical.
  Functions without return values do not need an empty output arguments block.
  Omit arguments blocks where MATLAB forbids them, including methods declared in
  a `methods (Test)` block of a `matlab.unittest.TestCase` class.
- Add concise English comments before meaningful groups of internal operations,
  especially validation, model mutation, traversal, generation, I/O, and cleanup.
  Do not comment self-evident individual assignments.
- Prefer MATLAB `string` values and double-quoted string literals for text. Use
  character vectors or cell arrays of character vectors only at compatibility
  boundaries that require them, such as an API with a documented `char` schema
  or byte-oriented source escaping. Keep any conversion to `char` local to that
  boundary.
- Add class validation to class properties whenever the accepted value class is
  well-defined. Prefer class-only declarations such as `Name string` or
  `Metadata struct`; do not add property size validation unless the invariant is
  necessary and stable.
- Store homogeneous class instances in typed object arrays initialized with
  `ClassName.empty`. Use cell arrays only for intentionally heterogeneous values
  or while the element type is genuinely undefined; replace provisional cells
  when a stable model class is introduced.
- Give each property the narrowest practical access. Use `Access = private` for
  implementation state that no other class needs, and use `SetAccess = private`
  for publicly readable state that only the defining class may change. Do not
  expose a property merely to avoid adding an appropriate method.
- Every property with public `GetAccess` must have English property help. Place
  one or more comment lines immediately above the property definition, using an
  H1 line such as `% Name - MATLAB class name represented by this document.`
  Prefer this form over an end-of-line comment because MATLAB gives the preceding
  comment block precedence and uses it for `help ClassName.PropertyName`, `doc`,
  and property metadata. Private properties do not require property help.
- Generated AppBase classes must add the same preceding English help comment for
  every generated public component property.
- Preserved input fixtures are exempt from the docstring and arguments-block
  rules because their original source structure is test data.
- This project is a programmatic MATLAB application. Do not convert the application itself to `.mlapp`.
- Preserve the input `matlab.apps.AppBase` class source; generated or modified source should remain reviewable as text.

## Commit discipline

- Commit implementation changes in cohesive feature-sized units. After completing
  a cohesive implementation change and passing its relevant MATLAB unit test
  suite, proactively create the Git commit without waiting for a user request.
  Treat this local commit as a normal implementation step, not as an external
  publication action.
- Before the final response for any file-changing task, check `git status`. Do
  not leave agent-authored implementation changes uncommitted. Do not commit
  unrelated pre-existing user changes.
- Do not create a commit when the user explicitly requests no commit, requests
  review-only work, or the relevant tests do not pass.
- Commit changes to this `AGENTS.md` file separately from source, tests, and
  other documentation. An `AGENTS.md` commit must contain no unrelated files.

## License notices

- The project is licensed under GNU GPL version 3 or any later version (`GPL-3.0-or-later`).
- Follow the MRST-style layout for every project-owned MATLAB source or test
  `.m` file: place executable MATLAB declarations and their help text first, and
  place the complete English GPL notice in a block comment at the end of the
  file. For a class, `classdef` must therefore be the first MATLAB construct and
  its class help must remain immediately after the `classdef` line so that
  `help` and `doc` display the class documentation instead of the license.
- Use the following trailing block exactly. Replace the first description line
  when a more specific description is useful, but keep the remaining notice
  intact.

```matlab
%{
MatlabAppClassDesigner - Visual editor for programmatic MATLAB AppBase classes.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
```

- Do not add or replace license notices in third-party files or preserved input fixtures. Keep their original notices and record their provenance when they are added.
- AppBase classes created or opened as user output are not automatically licensed under the editor's GPL. Do not insert, replace, or remove a license notice in generated or user-supplied app source unless the user explicitly requests it.

