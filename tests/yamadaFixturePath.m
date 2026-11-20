function path = yamadaFixturePath(name)
% yamadaFixturePath Return the input fixture to use for the running MATLAB release.
%   A fixture that needs components or properties missing from older releases
%   may have release-specific variants in tests/fixtures/<release>/. The newest
%   variant not newer than the running release wins, matching the catalog
%   loader; otherwise the shared fixture in tests/fixtures is used.
%
%   Example:
%       source = yamadaFixturePath("ControlGalleryApp.m");
arguments (Input)
    name (1, 1) string
end
arguments (Output)
    path (1, 1) string
end

% Prefer the newest release folder that applies and contains this fixture.
folder = fullfile(fileparts(mfilename("fullpath")), "fixtures");
entries = dir(folder);
releases = string({entries([entries.isdir]).name});
releases = sort(releases(~cellfun(@isempty, regexp(cellstr(releases), '^R\d{4}[ab]$', 'once'))));
releases = releases(releases <= string(matlabRelease().Release));
for release = flip(releases)
    candidate = fullfile(folder, release, name);
    if isfile(candidate)
        path = string(candidate);
        return
    end
end
path = string(fullfile(folder, name));
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
