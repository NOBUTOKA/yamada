function assumeCatalogSupports(testCase, variantId, paths)
% assumeCatalogSupports Skip a test when the loaded catalog lacks a variant or properties.
%   Tests of behavior that exists only in some MATLAB releases gate on the
%   catalog loaded for the running release, not on the release name. A missing
%   variant or property makes the test incomplete instead of failing.
%
%   Example:
%       assumeCatalogSupports(testCase, "uispinner", "AllowEmpty");
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    variantId (1, 1) string
    paths (1, :) string = strings(1, 0)
end

% Read the same packaged catalog the code under test uses.
registry = yamada.model.ComponentRegistry.createDefault();
release = yamada.catalog.ComponentCatalogLoader.defaultRelease();
testCase.assumeTrue(any(registry.listVariantIds() == variantId), ...
    "The " + release + " catalog has no " + variantId + " variant.");
available = string({registry.getById(variantId).Properties.Path});
missing = paths(~ismember(paths, available));
testCase.assumeEmpty(missing, "The " + release + " catalog has no " + variantId + " " + ...
    strjoin(missing, ", ") + ".");
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
