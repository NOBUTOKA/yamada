function results = ProbeStoredPositionInteractions(outputPath)
% ProbeStoredPositionInteractions Compare stored position inputs on owned native variants.
arguments (Input)
    outputPath (1, 1) string
end
arguments (Output)
    results (1, :) struct
end
% Construct only catalog factories inside hidden, fixture-owned parents.
registry = yamada.model.ComponentRegistry.createDefault();
figure = uifigure("Visible", "off");
cleanup = onCleanup(@() delete(figure));
results = struct("Id", {}, "Requested", {}, "Actual", {}, "Error", {});
for id = registry.listVariantIds()
    definition = registry.getById(id);
    if isempty(definition.getProperty("Position")), continue, end
    target = [];
    parent = figure;
    try
        if any(definition.AllowedParentFactories == "uibuttongroup") && ...
                ~any(definition.AllowedParentFactories == "uifigure")
            parent = uibuttongroup(figure);
        elseif definition.Factory == "uitab"
            parent = uitabgroup(figure);
        end
        if definition.Factory == "uifigure"
            target = uifigure("Visible", "off");
        else
            target = feval(definition.Factory, parent, definition.CreationArguments{:});
        end
        for requested = {[10 20 130 35], [30 40 150 45], [10 20 0 0]}
            target.Position = requested{1};
            drawnow;
            results(end + 1) = struct("Id", id, "Requested", requested{1}, ...
                "Actual", target.Position, "Error", ""); %#ok<AGROW>
        end
    catch exception
        results(end + 1) = struct("Id", id, "Requested", [], "Actual", [], ...
            "Error", string(exception.identifier)); %#ok<AGROW>
    end
    if ~isempty(target) && isvalid(target), delete(target); end
    if parent ~= figure && isvalid(parent), delete(parent); end
end
% Persist supplemental evidence without modifying the reviewed application ledger.
file = fopen(outputPath, "w", "n", "UTF-8");
assert(file >= 0);
fileCleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(results, "PrettyPrint", true));
fprintf("STORED_POSITION Cases=%d Errors=%d\n", numel(results), sum(strlength(string({results.Error})) > 0));
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
