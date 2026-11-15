classdef (TestTags = {'catalog', 'ui'}) CatalogSetterAccessRuntimeTest < matlab.unittest.TestCase
    % CatalogSetterAccessRuntimeTest Reproduce recorded access observations on owned native controls.
    %   The test compares all formerly unresolved targets with both the
    %   packaged catalog of the running release and native instance metadata
    %   without running application source. The audit is recorded once in the
    %   surface ledger; the running release checks the targets its catalog
    %   still contains.
    methods (Test)
        function recordedSetterAccessMatchesNativeMetadata(testCase)
            % recordedSetterAccessMatchesNativeMetadata Verify every recorded target after catalog correction.
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tools = fullfile(root, "dev", "component-data");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(tools));
            releases = jsondecode(fileread(fullfile(tools, "releases.json")));
            ledger = fullfile(tools, string(releases.surfaceRelease));
            catalog = fullfile(root, "resources", "component-catalog", ...
                yamada.catalog.ComponentCatalogLoader.defaultRelease());

            % Keep the recorded targets that the running release still exposes.
            review = jsondecode(fileread(fullfile(ledger, "SETTER_ACCESS_RUNTIME_REVIEW.json")));
            expected = reshape(review.observations, 1, []);
            present = arrayfun(@(observation) CatalogSetterAccessRuntimeTest.catalogAccess(catalog, ...
                string(observation.componentId), string(observation.path)) ~= "", expected);
            expected = expected(present);
            testCase.assertNotEmpty(expected);

            % Native metadata and the packaged catalog must both match the audit.
            actual = ProbeCatalogSetterAccess(ledger, expected);
            testCase.assertNumElements(actual, numel(expected));
            testCase.verifyEqual(string({actual.runtimeSetAccess}), string({expected.runtimeSetAccess}));
            testCase.verifyEqual(string({actual.nativeSetAccess}), string({expected.nativeSetAccess}));
            testCase.verifyEqual(string({actual.errorId}), repmat("", 1, numel(actual)));
            for observation = actual
                testCase.verifyEqual(CatalogSetterAccessRuntimeTest.catalogAccess(catalog, ...
                    observation.componentId, observation.path), observation.runtimeSetAccess);
            end
        end
    end

    methods (Static, Access = private)
        function access = catalogAccess(catalog, componentId, path)
            % catalogAccess Read the packaged runtime setter access of one variant property.
            %   An empty string means that the catalog does not contain the property.
            arguments (Input)
                catalog (1, 1) string
                componentId (1, 1) string
                path (1, 1) string
            end
            arguments (Output)
                access (1, 1) string
            end
            access = "";
            file = fullfile(catalog, "components", componentId + ".json");
            if ~isfile(file), return, end
            categories = jsondecode(fileread(file)).categories;
            if ~iscell(categories), categories = num2cell(categories); end
            for category = reshape(categories, 1, [])
                entries = category{1}.entries;
                if ~iscell(entries), entries = num2cell(entries); end
                for entry = reshape(entries, 1, [])
                    if string(entry{1}.path) == path
                        access = string(entry{1}.runtimeSetAccess);
                        return
                    end
                end
            end
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
