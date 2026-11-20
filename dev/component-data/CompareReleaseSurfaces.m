function differences = CompareReleaseSurfaces(baseFile, otherFile)
% CompareReleaseSurfaces List native surface differences between two ProbeReleaseSurface outputs.
%   Both files must observe the same ledger. Each difference names a variant,
%   its kind, an optional property path, and both observed values, so a
%   release-delta.json can cite it as nativeObservation evidence. Differences
%   are also printed when no output is requested.
%
%   Example:
%       CompareReleaseSurfaces("surface-R2024a.json", "surface-R2023a.json");
arguments (Input)
    baseFile (1, 1) string
    otherFile (1, 1) string
end
arguments (Output)
    differences (1, :) struct
end

% Index the other release's variants by identifier.
base = jsondecode(fileread(baseFile));
other = jsondecode(fileread(otherFile));
otherVariants = struct();
for variant = reshape(asCell(other.variants), 1, [])
    otherVariants.(matlab.lang.makeValidName(variant{1}.id)) = variant{1};
end
differences = struct("variantId", {}, "kind", {}, "path", {}, "base", {}, "other", {});

for variant = reshape(asCell(base.variants), 1, [])
    first = variant{1};
    key = matlab.lang.makeValidName(first.id);
    if ~isfield(otherVariants, key)
        differences(end + 1) = difference(first.id, "variantNotObserved", "", "", ""); %#ok<AGROW>
        continue
    end
    second = otherVariants.(key);
    if first.created ~= second.created
        differences(end + 1) = difference(first.id, "construction", "", ...
            string(first.errorId), string(second.errorId)); %#ok<AGROW>
        continue
    end
    if ~first.created, continue, end

    % Presence: absent and hidden paths are compared separately because hidden API is undocumented.
    for kind = ["absentPaths", "hiddenPaths"]
        before = asStrings(first.(kind));
        after = asStrings(second.(kind));
        for path = setdiff(after, before)
            differences(end + 1) = difference(first.id, kind + "Added", path, "", ""); %#ok<AGROW>
        end
        for path = setdiff(before, after)
            differences(end + 1) = difference(first.id, kind + "Removed", path, "", ""); %#ok<AGROW>
        end
    end

    % Defaults and finite options of paths observed in both releases.
    for field = ["defaults", "options"]
        names = string(fieldnames(first.(field)))';
        for name = names
            if ~isfield(second.(field), name)
                if field == "options"
                    differences(end + 1) = difference(first.id, "optionsRemoved", name, ...
                        strjoin(asStrings(first.(field).(name)), "|"), ""); %#ok<AGROW>
                end
                continue
            end
            before = strjoin(asStrings(first.(field).(name)), "|");
            after = strjoin(asStrings(second.(field).(name)), "|");
            if before ~= after
                differences(end + 1) = difference(first.id, field + "Changed", name, before, after); %#ok<AGROW>
            end
        end
        for name = setdiff(string(fieldnames(second.(field)))', names)
            if field == "options"
                differences(end + 1) = difference(first.id, "optionsAdded", name, "", ...
                    strjoin(asStrings(second.(field).(name)), "|")); %#ok<AGROW>
            end
        end
    end
end

% Print a reviewable list when the caller does not keep the result.
if nargout == 0
    fprintf("%s -> %s\n", base.release, other.release);
    for item = differences
        fprintf("%s %s %s: %s | %s\n", item.variantId, item.kind, item.path, item.base, item.other);
    end
end
end

function item = difference(variantId, kind, path, base, other)
% difference Build one comparison record.
arguments (Input)
    variantId (1, 1) string
    kind (1, 1) string
    path (1, 1) string
    base (1, 1) string
    other (1, 1) string
end
arguments (Output)
    item (1, 1) struct
end
item = struct("variantId", variantId, "kind", kind, "path", path, "base", base, "other", other);
end

function values = asCell(value)
% asCell Normalize a decoded JSON array of objects to a cell array.
arguments (Input)
    value
end
arguments (Output)
    values cell
end
if iscell(value), values = value; else, values = num2cell(value); end
end

function values = asStrings(value)
% asStrings Normalize a decoded JSON string, string array, or empty value to a string row.
arguments (Input)
    value
end
arguments (Output)
    values (1, :) string
end
if isempty(value), values = strings(1, 0); return, end
values = reshape(string(value), 1, []);
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
