classdef (TestTags = {'compatibility', 'catalog'}) CatalogPromotionTest < matlab.unittest.TestCase
    % CatalogPromotionTest Verify provenance when rebuilding the runtime catalog.
    %   This opt-in check belongs to catalog promotion rather than product edits.

    methods (Test)
        function runtimeCatalogRetainsGroupingProvenance(testCase)
            % runtimeCatalogRetainsGroupingProvenance Verify runtime data names the reviewed grouping input.

            % Read raw JSON so the provenance check does not depend on registry details.
            root = macd.catalog.ComponentCatalogLoader.defaultCatalogRoot();
            manifest = jsondecode(fileread(fullfile(root, "catalog.json")));
            groups = jsondecode(fileread(fullfile(root, "property-groups", "groups.json")));
            profiles = jsondecode(fileread(fullfile(root, "order-profiles.json")));
            testCase.verifyEqual(manifest.schemaVersion, 2);
            testCase.verifyEqual(string(manifest.matlabRelease), "R2024a");
            testCase.verifyEqual(string(manifest.sourceGroupingSha256), string(groups.inputSha256));
            projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            design = jsondecode(fileread(fullfile(projectRoot, "dev", "component-data", ...
                "R2024a", "grouping", "GROUPING_DESIGN.json")));
            testCase.verifyEqual(numel(groups.groups), numel(design.groups));
            testCase.verifyEqual(sort(string(manifest.orderProfileFiles)), "order-profiles.json");
            testCase.verifyEqual(sort(string({profiles.profiles.id})), ...
                ["axes", "contextMenu", "menuToolbar", "standardControl", "uifigure"]);
        end
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
