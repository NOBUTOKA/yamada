function results = ProbePositionAliasInteractions(outputPath)
% ProbePositionAliasInteractions Check documented UI position aliases on owned controls.
%   The fixture uses literal positions and never loads HTML, image assets, user
%   callbacks, or an opened application. Constructor order is checked separately.
arguments (Input)
    outputPath (1, 1) string
end
arguments (Output)
    results (1, :) struct
end

% Keep every native object within one hidden test-owned figure.
figure = uifigure("Visible", "off");
cleanup = onCleanup(@() delete(figure));
registry = macd.model.ComponentRegistry.createDefault();
ids = ["uibutton-push", "uibutton-state", "uitogglebutton", "uicheckbox", ...
    "uicolorpicker", "uihtml", "uihyperlink", "uiimage", "uilabel", "uilamp", ...
    "uiradiobutton", "uitextarea", "uitree", "uitree-checkbox"];
results = struct("Id", {}, "Path", {}, "SetAccess", {}, "SetterAccepted", {}, "Requested", {}, "Position", {}, ...
    "Inner", {}, "Outer", {}, "PositionFirst", {}, "AliasFirst", {}, "Error", {});
first = [10 20 130 35];
second = [30 40 150 45];
for id = ids
    definition = registry.getById(id);
    parent = figure;
    if any(definition.AllowedParentFactories == "uibuttongroup") && ...
            ~any(definition.AllowedParentFactories == "uifigure")
        parent = uibuttongroup(figure);
    end
    for path = ["Position", "InnerPosition", "OuterPosition"]
        property = definition.Properties(string({definition.Properties.Path}) == path);
        if isempty(property), continue, end
        result = struct("Id", id, "Path", path, "SetAccess", "unresolved", "SetterAccepted", false, "Requested", first, "Position", [], ...
            "Inner", [], "Outer", [], "PositionFirst", [], "AliasFirst", [], "Error", "");
        target = [];
        forward = [];
        reverse = [];
        try
            target = feval(definition.Factory, parent, definition.CreationArguments{:});
            metadata = findprop(target, path);
            result.SetAccess = "restricted";
            if (ischar(metadata.SetAccess) || isstring(metadata.SetAccess)) && string(metadata.SetAccess) == "public"
                result.SetAccess = "public";
            end
            target.(path) = first;
            result.SetterAccepted = true;
            drawnow;
            result.Position = target.Position;
            result.Inner = target.InnerPosition;
            result.Outer = target.OuterPosition;
            forward = feval(definition.Factory, parent, definition.CreationArguments{:}, ...
                "Position", first, path, second);
            reverse = feval(definition.Factory, parent, definition.CreationArguments{:}, ...
                path, second, "Position", first);
            drawnow;
            result.PositionFirst = forward.Position;
            result.AliasFirst = reverse.Position;
        catch exception
            result.Error = string(exception.identifier) + ": " + string(exception.message);
        end
        deleteOwned(target);
        deleteOwned(forward);
        deleteOwned(reverse);
        results(end + 1) = result; %#ok<AGROW>
    end
    if parent ~= figure, delete(parent); end
end

% Save supplemental native facts separately from reviewed application metadata.
file = fopen(outputPath, "w", "n", "UTF-8");
assert(file >= 0, "macd:ProbePositionAliasInteractions:WriteFailed", "Cannot open probe output.");
fileCleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(struct("matlabRelease", "R2024a", "results", results), "PrettyPrint", true));
fprintf("POSITION_ALIAS_PROBE Cases=%d Accepted=%d Restricted=%d UnexpectedErrors=%d\n", ...
    numel(results), sum([results.SetterAccepted]), sum(string({results.SetAccess}) == "restricted"), ...
    sum(string({results.SetAccess}) == "public" & strlength(string({results.Error})) > 0));
end

function deleteOwned(target)
% deleteOwned Release one owned control after either successful probing or failure.
arguments (Input)
    target
end
if ~isempty(target) && isvalid(target), delete(target); end
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
