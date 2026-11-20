function runYamadaTestWorker(profile, areas, queueFolder)
% runYamadaTestWorker Run claimed test classes for a sharded profile run.
%   runYamadaTestWorker(PROFILE, AREAS, QUEUEFOLDER) is started by
%   runYamadaTests in a separate MATLAB process when Workers is greater than
%   one; developers do not call it directly. It rebuilds the same profile
%   suite, then repeatedly claims the next unclaimed test class listed in
%   QUEUEFOLDER/classes.txt and saves that class's results. AREAS is a
%   comma-separated list, or empty for profiles without areas.
arguments (Input)
    profile (1, 1) string
    areas (1, 1) string
    queueFolder (1, 1) string
end

% Rebuild the profile suite exactly as the coordinating process did.
if strlength(areas) == 0
    areaList = string.empty(1, 0);
else
    areaList = split(areas, ",")';
end
suite = selectYamadaTests(profile, areaList);
owners = extractBefore(string({suite.Name}), "/");
classes = readlines(fullfile(queueFolder, "classes.txt"), "EmptyLineRule", "skip")';

% Claim classes in queue order; directory creation is atomic across processes.
for index = 1:numel(classes)
    claim = java.io.File(char(fullfile(queueFolder, "claims", string(index))));
    if ~claim.mkdir(), continue, end
    fprintf("TEST_WORKER_CLASS Index=%d Class=%s\n", index, classes(index));
    results = run(suite(owners == classes(index)));
    resultPath = fullfile(queueFolder, "results", string(index) + ".mat");
    save(resultPath, "results");
end
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
