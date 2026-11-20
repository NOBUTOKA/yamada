function results = runYamadaTests(profile, areas, options)
% runYamadaTests Run a selected yamada test profile and assert its success.
%   RESULTS = runYamadaTests(PROFILE) runs the quick or full profile.
%   RESULTS = runYamadaTests("area", AREAS) runs quick coverage together
%   with tests for the requested functional areas.
%   RESULTS = runYamadaTests(..., Workers=N) splits the selected suite by
%   test class across N separate batch MATLAB processes and returns the
%   combined results in suite order. The default of 1 runs in this session.
%   This developer-only entry point is kept with the test suite; add the
%   tests folder to the MATLAB path before calling it.

arguments (Input)
    profile (1, 1) string {mustBeMember(profile, ["quick", "area", "full"])}
    areas (1, :) string = string.empty(1, 0)
    options.Workers (1, 1) double {mustBeInteger, mustBePositive} = 1
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
fprintf("TEST_PROFILE Profile=%s Areas=%s Count=%d Workers=%d\n", ...
    profile, areaText, numel(suite), options.Workers);

% Run the selected tests and surface a compact aggregate for batch callers.
started = tic;
if options.Workers == 1
    results = run(suite);
else
    results = runYamadaTestShards(suite, profile, areas, options.Workers);
end
fprintf("TEST_PROFILE_SUMMARY Profile=%s Passed=%d Failed=%d Incomplete=%d Duration=%.3f Wall=%.3f\n", ...
    profile, sum([results.Passed]), sum([results.Failed]), ...
    sum([results.Incomplete]), sum([results.Duration]), toc(started));

% Name every unsuccessful test so batch and worker runs are diagnosable from the log.
for result = results(~[results.Passed])
    status = "Failed";
    if result.Incomplete && ~result.Failed, status = "Incomplete"; end
    fprintf("TEST_PROFILE_UNSUCCESSFUL Status=%s Name=%s\n", status, result.Name);
end
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
