classdef (TestTags = {'compatibility', 'catalog'}) CatalogPromotionTest < matlab.unittest.TestCase
    % CatalogPromotionTest Verify provenance when rebuilding the runtime catalog.
    %   This opt-in check belongs to catalog promotion rather than product edits.

    methods (Test)
        function runtimeCatalogRetainsGroupingProvenance(testCase)
            % runtimeCatalogRetainsGroupingProvenance Verify runtime data names the reviewed grouping input.

            % Read raw JSON so the provenance check does not depend on registry details.
            root = yamada.catalog.ComponentCatalogLoader.defaultCatalogRoot();
            manifest = jsondecode(fileread(fullfile(root, "catalog.json")));
            groups = jsondecode(fileread(fullfile(root, "property-groups", "groups.json")));
            profiles = jsondecode(fileread(fullfile(root, "order-profiles.json")));
            testCase.verifyEqual(manifest.schemaVersion, 2);
            testCase.verifyEqual(string(manifest.matlabRelease), ...
                yamada.catalog.ComponentCatalogLoader.defaultRelease());
            testCase.verifyEqual(string(manifest.sourceGroupingSha256), string(groups.inputSha256));

            % Only the surface release keeps its grouping design in the ledger.
            projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tools = fullfile(projectRoot, "dev", "component-data");
            releases = jsondecode(fileread(fullfile(tools, "releases.json")));
            if string(manifest.matlabRelease) == string(releases.surfaceRelease)
                design = jsondecode(fileread(fullfile(tools, string(releases.surfaceRelease), ...
                    "grouping", "GROUPING_DESIGN.json")));
                testCase.verifyEqual(numel(groups.groups), numel(design.groups));
            end
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
