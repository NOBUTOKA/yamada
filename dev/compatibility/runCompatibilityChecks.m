function results = runCompatibilityChecks()
% runCompatibilityChecks Run opt-in MATLAB and catalog promotion observations.
%   Add dev/compatibility to the path and call this function when reviewing a
%   MATLAB upgrade or promoting regenerated catalog artifacts.
arguments (Output)
    results (1, :) matlab.unittest.TestResult
end

% Discover only the explicitly separated development checks.
folder = fileparts(mfilename("fullpath"));
suite = [testsuite(fullfile(folder, "NativeBehaviorTest.m")), ...
    testsuite(fullfile(folder, "CatalogPromotionTest.m"))];
results = run(suite);
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
