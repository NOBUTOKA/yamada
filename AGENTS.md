# Project instructions

- MATLAB source files and test files must use UTF-8 encoding without a BOM.
- MATLAB source files and test files must use CRLF line endings.
- Write comments in MATLAB source files in English.
- This project is a programmatic MATLAB application. Do not convert the application itself to `.mlapp`.
- Preserve the input `matlab.apps.AppBase` class source; generated or modified source should remain reviewable as text.

## License notices

- The project is licensed under GNU GPL version 3 or any later version (`GPL-3.0-or-later`).
- Every project-owned MATLAB source or test `.m` file must begin with the following English notice. Replace the first description line when a more specific description is useful, but keep the remaining notice intact.

```matlab
% MatlabAppClassDesigner - Visual editor for programmatic MATLAB AppBase classes.
% Copyright (C) 2026 MatlabAppClassDesigner contributors
%
% This file is part of MatlabAppClassDesigner.
%
% MatlabAppClassDesigner is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% MatlabAppClassDesigner is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
```

- Do not add or replace license notices in third-party files or preserved input fixtures. Keep their original notices and record their provenance when they are added.
- AppBase classes created or opened as user output are not automatically licensed under the editor's GPL. Do not insert, replace, or remove a license notice in generated or user-supplied app source unless the user explicitly requests it.

