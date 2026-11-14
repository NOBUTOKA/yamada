function artifacts = buildYamadaToolbox(outputFolder)
% buildYamadaToolbox Build a Toolbox candidate, source manifest, and SHA-256 list.
%   Add dev/release to the path before calling this developer-only function.
%   Existing outputs are not replaced, so signed or reviewed files remain fixed.
%   The manifest records the Git commit and dirty state of the checkout, which
%   the release procedure requires before a candidate can be signed.
arguments (Input)
    outputFolder (1, 1) string = ""
end
arguments (Output)
    artifacts (1, 1) struct
end

% Identify the exact checkout through Git before and after packaging.
projectRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
artifacts = packageYamadaToolbox(outputFolder, @() gitSource(projectRoot));
end

function source = gitSource(projectRoot)
% gitSource Return the current commit and whether the checkout has changes.
arguments (Input)
    projectRoot (1, 1) string
end
arguments (Output)
    source (1, 1) struct
end
source = struct("commit", gitOutput(projectRoot, "rev-parse HEAD"), ...
    "dirty", gitOutput(projectRoot, "status --porcelain") ~= "");
end

function result = gitOutput(projectRoot, command)
% gitOutput Require Git to identify candidate source without changing the checkout.
arguments (Input)
    projectRoot (1, 1) string
    command (1, 1) string
end
arguments (Output)
    result (1, 1) string
end
[status, output] = system("git -C """ + projectRoot + """ " + command);
assert(status == 0, "yamada:Release:GitFailed", "Could not identify source: %s", output);
result = strip(string(output));
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of yamada.

yamada is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

yamada is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with yamada. If not, see <https://www.gnu.org/licenses/>.
%}
