function [options, metadata] = yamadaToolboxOptions(projectRoot, toolboxRoot)
% yamadaToolboxOptions Define explicit packaging inputs and public metadata.
%   Only the distribution root is added to MATLAB's path. Development inputs,
%   fixtures, and measurement artifacts are never selected by directory-wide packaging.
arguments (Input)
    projectRoot (1, 1) string
    toolboxRoot (1, 1) string
end
arguments (Output)
    options (1, 1) matlab.addons.toolbox.ToolboxOptions
    metadata (1, 1) struct
end

% Map selected source files into an isolated, already prepared payload folder.
[files, metadata] = yamadaToolboxFiles(projectRoot);
relative = extractAfter(files, strlength(projectRoot) + 1);
files = fullfile(toolboxRoot, relative);
assert(all(isfile(files)), "yamada:Release:MissingPayload", "The prepared payload is incomplete.");

% Use the documented Toolbox Apps registration rather than a custom installer.
options = matlab.addons.toolbox.ToolboxOptions(toolboxRoot, metadata.identifier, ToolboxFiles=files);
options.ToolboxName = metadata.name;
options.ToolboxImageFile = fullfile(toolboxRoot, "doc", "images", "toolbox-cover.png");
options.ToolboxVersion = metadata.version;
options.AuthorName = metadata.author;
options.AuthorEmail = metadata.email;
options.AuthorCompany = metadata.company;
options.Summary = metadata.summary;
options.Description = metadata.description;
options.Readme = fullfile(toolboxRoot, metadata.readme);
options.MinimumMatlabRelease = metadata.minimumMatlabRelease;
options.MaximumMatlabRelease = metadata.maximumMatlabRelease;

% Clear the packager's own platform fields, whose names differ between releases.
platforms = options.SupportedPlatforms;
for field = string(fieldnames(platforms))'
    platforms.(field) = field == "Win64";
end
options.SupportedPlatforms = platforms;
options.ToolboxFiles = files;
options.ToolboxMatlabPath = toolboxRoot;
options.AppGalleryFiles = fullfile(toolboxRoot, "yamada.m");
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
