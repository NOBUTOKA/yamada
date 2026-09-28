function results = runYamadaTests(profile, areas)
% runYamadaTests Run a selected yamada test profile and assert its success.
%   RESULTS = runYamadaTests(PROFILE) runs the quick or full profile.
%   RESULTS = runYamadaTests("area", AREAS) runs quick coverage together
%   with tests for the requested functional areas.
%   This developer-only entry point is kept with the test suite; add the
%   tests folder to the MATLAB path before calling it.

arguments (Input)
    profile (1, 1) string {mustBeMember(profile, ["quick", "area", "full"])}
    areas (1, :) string = string.empty(1, 0)
end
arguments (Output)
    results (1, :) matlab.unittest.TestResult
end

% Build the suite before any test executes so invalid requests fail clearly.
suite = selectYamadaTests(profile, areas);
if isempty(areas)
    areaText = "";
else
    areaText = join(areas, ",");
end
fprintf("TEST_PROFILE Profile=%s Areas=%s Count=%d\n", ...
    profile, areaText, numel(suite));

% Run the selected tests and surface a compact aggregate for batch callers.
results = run(suite);
fprintf("TEST_PROFILE_SUMMARY Profile=%s Passed=%d Failed=%d Incomplete=%d Duration=%.3f\n", ...
    profile, sum([results.Passed]), sum([results.Failed]), ...
    sum([results.Incomplete]), sum([results.Duration]));
assertSuccess(results);
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
