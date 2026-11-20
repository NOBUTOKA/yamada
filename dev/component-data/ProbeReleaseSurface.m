function surface = ProbeReleaseSurface(releaseDirectory, outputFile)
% ProbeReleaseSurface Record the native surface of every ledger variant in the running release.
%   For each component document under releaseDirectory/components, construct
%   one owned fixture and record whether construction succeeds, which ledger
%   property paths are absent or hidden, every readable default value, and the
%   finite options that set reports. Run it in two releases on the same ledger
%   and compare the outputs with CompareReleaseSurfaces to find the evidence for
%   a release-delta.json. User app source and callbacks are never run.
%
%   Example:
%       ProbeReleaseSurface("dev/component-data/R2024a", "surface-R2023a.json");
arguments (Input)
    releaseDirectory (1, 1) string
    outputFile (1, 1) string = ""
end
arguments (Output)
    surface (1, 1) struct
end

% Read ledger documents before constructing any native control.
files = dir(fullfile(releaseDirectory, "components", "*.json"));
variants = struct("id", {}, "factory", {}, "created", {}, "errorId", {}, "absentPaths", {}, ...
    "hiddenPaths", {}, "defaults", {}, "options", {});
figure = uifigure("Visible", "off");
cleanup = onCleanup(@() delete(figure));
for file = reshape(files, 1, [])
    document = jsondecode(fileread(fullfile(file.folder, file.name)));
    variant = struct("id", string(document.id), "factory", string(document.factory), "created", false, ...
        "errorId", "", "absentPaths", strings(1, 0), "hiddenPaths", strings(1, 0), ...
        "defaults", struct(), "options", struct());
    names = topLevelPaths(document.properties);
    try
        target = construct(figure, variant.factory, creationArguments(document));
        variant.created = true;
    catch exception
        variant.errorId = string(exception.identifier);
        variants(end + 1) = variant; %#ok<AGROW>
        continue
    end

    % Hidden properties exist but are not documented public API in this release.
    for name = names
        if ~isprop(target, name)
            variant.absentPaths(end + 1) = name;
            continue
        end
        metadata = findprop(target, name);
        if ~isempty(metadata) && metadata.Hidden
            variant.hiddenPaths(end + 1) = name;
        end
        key = matlab.lang.makeValidName(name);
        try
            variant.defaults.(key) = describeValue(target.(name));
        catch exception
            variant.defaults.(key) = "<get error " + string(exception.identifier) + ">";
        end
        try
            choices = set(target, name);
            if iscell(choices) && ~isempty(choices), variant.options.(key) = string(choices(:))'; end
        catch
            % Properties without finite choices are recorded through their defaults only.
        end
    end
    delete(target);
    variants(end + 1) = variant; %#ok<AGROW>
end
surface = struct("release", string(version("-release")), "version", string(version), "variants", variants);

% Write the observation when requested so another release can compare against it.
if strlength(outputFile) > 0
    fileId = fopen(outputFile, "w", "n", "UTF-8");
    if fileId < 0, error("yamada:ReleaseSurface:Write", "Cannot write %s.", outputFile); end
    closer = onCleanup(@() fclose(fileId));
    fprintf(fileId, "%s\n", jsonencode(surface, "PrettyPrint", true));
end
end

function names = topLevelPaths(properties)
% topLevelPaths Return unique first segments of ledger property paths.
arguments (Input)
    properties
end
arguments (Output)
    names (1, :) string
end
if iscell(properties)
    paths = string(cellfun(@(item) item.path, properties, "UniformOutput", false));
else
    paths = string({properties.path});
end
names = unique(extractBefore(reshape(paths, 1, []) + ".", "."), "stable");
end

function values = creationArguments(document)
% creationArguments Return a ledger variant's positional factory arguments as a cell array.
arguments (Input)
    document (1, 1) struct
end
arguments (Output)
    values cell
end
values = {};
if isfield(document, "creationArguments") && ~isempty(document.creationArguments)
    values = cellstr(string(document.creationArguments));
end
end

function target = construct(figure, factory, values)
% construct Create one component under the minimal parent its factory requires.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    factory (1, 1) string
    values cell
end
arguments (Output)
    target (1, 1) matlab.graphics.Graphics
end
switch factory
    case "uifigure"
        target = uifigure("Visible", "off", values{:});
    case "uitab"
        target = uitab(uitabgroup(figure), values{:});
    case "uitreenode"
        target = uitreenode(uitree(figure), values{:});
    case {"uiradiobutton", "uitogglebutton"}
        target = feval(factory, uibuttongroup(figure), values{:});
    case {"uipushtool", "uitoggletool"}
        target = feval(factory, uitoolbar(figure), values{:});
    otherwise
        target = feval(factory, figure, values{:});
end
end

function text = describeValue(value)
% describeValue Encode one property value compactly enough for cross-release comparison.
arguments (Input)
    value
end
arguments (Output)
    text (1, 1) string
end
text = string(class(value)) + mat2str(size(value));
% Handles and callbacks are compared by class and size only.
if isa(value, "matlab.graphics.Graphics") || isa(value, "function_handle"), return, end
try
    text = text + " " + string(jsonencode(value));
catch
    % Values that JSON cannot encode keep the class and size description.
end
if strlength(text) > 300, text = extractBefore(text, 301); end
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
