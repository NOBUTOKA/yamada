function suite = selectYamadaTests(profile, areas)
% selectYamadaTests Select a documented yamada test profile.
%   SUITE = selectYamadaTests(PROFILE) returns the quick or full unit-test
%   suite. SUITE = selectYamadaTests("area", AREAS) returns the quick suite
%   plus tests tagged for each requested functional area.

arguments (Input)
    profile (1, 1) string {mustBeMember(profile, ["quick", "area", "full"])}
    areas (1, :) string = string.empty(1, 0)
end
arguments (Output)
    suite (1, :) matlab.unittest.Test
end

% Discover tests from the project root rather than the caller's folder.
projectRoot = fileparts(mfilename("fullpath"));
testRoot = fullfile(projectRoot, "tests", "unit");

switch profile
    case "quick"
        validateNoAreas(profile, areas);
        suite = testsuite(testRoot, "Tag", "fast");
    case "area"
        validateAreas(areas);
        quickSuite = testsuite(testRoot, "Tag", "fast");
        areaSuite = testsuite(testRoot, "Tag", areas);
        suite = uniqueByName([quickSuite, areaSuite]);
    case "full"
        validateNoAreas(profile, areas);
        suite = testsuite(testRoot);
end

if isempty(suite)
    error("yamada:TestSelection:EmptySuite", ...
        "The %s test profile selected no tests.", profile);
end
end

function validateNoAreas(profile, areas)
% validateNoAreas Reject irrelevant area filters for fixed profiles.
arguments (Input)
    profile (1, 1) string
    areas (1, :) string
end

if ~isempty(areas)
    error("yamada:TestSelection:UnexpectedAreas", ...
        "The %s test profile does not accept area tags.", profile);
end
end

function validateAreas(areas)
% validateAreas Require supported functional area tags.
arguments (Input)
    areas (1, :) string
end

if isempty(areas)
    error("yamada:TestSelection:AreasRequired", ...
        "The area test profile requires at least one area tag.");
end

supported = ["parser", "catalog", "model", "generation", "preview", ...
    "gridOverlay", "inspector", "dialog", "editorShell", "previewTab", ...
    "lifecycle"];
unknown = setdiff(areas, supported);
if ~isempty(unknown)
    error("yamada:TestSelection:UnsupportedArea", ...
        "Unsupported test area tags: %s.", join(unknown, ", "));
end
end

function suite = uniqueByName(suite)
% uniqueByName Preserve first-occurrence order while removing duplicate tests.
arguments (Input)
    suite (1, :) matlab.unittest.Test
end
arguments (Output)
    suite (1, :) matlab.unittest.Test
end

[~, indices] = unique(string({suite.Name}), "stable");
suite = suite(indices);
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
