function [files, metadata] = yamadaToolboxFiles(projectRoot)
% yamadaToolboxFiles Select owned distribution inputs without scanning development outputs.
arguments (Input)
    projectRoot (1, 1) string
end
arguments (Output)
    files (:, 1) string
    metadata (1, 1) struct
end

% Load the single version and stable identity shared by every release artifact.
metadata = jsondecode(fileread(fullfile(projectRoot, "dev", "release", "toolbox.json")));
assert(~isempty(regexp(metadata.version, "^\d+\.\d+\.\d+$", "once")), ...
    "yamada:Release:InvalidVersion", "Expected a major.minor.patch version.");
assert(~isempty(regexp(metadata.identifier, "^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$", "once")), ...
    "yamada:Release:InvalidIdentifier", "Expected a fixed UUID.");

% Select owned runtime source, resources, and a bounded set of user documents.
relativeFiles = ["yamada.m"; "README.md"; "LICENSE"; "SPECIFICATION.md"; ...
    "CHANGELOG.md"; "doc/GETTING_STARTED.md"; ...
    "examples/WelcomeApp.m"];
for folder = ["+yamada", "resources", "doc/images"]
    entries = dir(fullfile(projectRoot, folder, "**", "*"));
    entries = entries(~[entries.isdir]);
    for entry = entries'
        path = string(fullfile(entry.folder, entry.name));
        [~, ~, extension] = fileparts(path);
        if (folder == "+yamada" && extension == ".m") || ...
                (folder == "resources" && ismember(extension, [".json", ".html", ".js"])) || ...
                (folder == "doc/images" && extension == ".png")
            relativeFiles(end + 1, 1) = extractAfter(path, strlength(projectRoot) + 1);
        end
    end
end
files = fullfile(projectRoot, sort(unique(relativeFiles)));
assert(all(isfile(files)), "yamada:Release:MissingInput", "A selected package file is missing.");

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
