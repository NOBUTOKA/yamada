function writeSourceStrategyProfile(output, name, profiles)
% writeSourceStrategyProfile Aggregate independent action call graphs without profiling selection or artifact writing.
arguments (Input)
    output (1, 1) string
    name (1, 1) string
    profiles cell = {profile("info")}
end
save(fullfile(output, name + ".mat"), "profiles");
names = strings(0, 1);
files = strings(0, 1);
calls = zeros(0, 1);
totals = zeros(0, 1);
self = zeros(0, 1);
for index = 1:numel(profiles)
    entries = profiles{index}.FunctionTable;
    names = [names; string({entries.FunctionName})']; %#ok<AGROW>
    files = [files; string({entries.FileName})']; %#ok<AGROW>
    calls = [calls; [entries.NumCalls]']; %#ok<AGROW>
    elapsed = [entries.TotalTime]';
    child = reshape(arrayfun(@(entry) sum([entry.Children.TotalTime]), entries), [], 1);
    totals = [totals; elapsed]; %#ok<AGROW>
    self = [self; max(0, elapsed - child)]; %#ok<AGROW>
end
[~, first, group] = unique(names + string(newline) + files, "stable");
functions = struct("Name", cellstr(names(first)), "File", cellstr(files(first)), ...
    "Calls", num2cell(accumarray(group, calls)), ...
    "TotalSeconds", num2cell(accumarray(group, totals)), ...
    "SelfSeconds", num2cell(accumarray(group, self)));
path = fullfile(output, name + ".json");
file = fopen(path, "w", "n", "UTF-8");
assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
fprintf(file, "%s", jsonencode(functions));
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
