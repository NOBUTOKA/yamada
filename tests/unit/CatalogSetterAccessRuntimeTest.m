classdef (TestTags = {'catalog', 'ui'}) CatalogSetterAccessRuntimeTest < matlab.unittest.TestCase
    % CatalogSetterAccessRuntimeTest Reproduce recorded access observations on owned native controls.
    %   The test compares all formerly unresolved targets with both the current
    %   ledger and native instance metadata without running application source.
    methods (Test)
        function recordedSetterAccessMatchesNativeMetadata(testCase)
            % recordedSetterAccessMatchesNativeMetadata Verify every recorded target after catalog correction.
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tools = fullfile(root, "dev", "component-data");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(tools));
            release = fullfile(tools, "R2024a");
            review = jsondecode(fileread(fullfile(release, "SETTER_ACCESS_RUNTIME_REVIEW.json")));
            expected = reshape(review.observations, 1, []);
            testCase.assertNotEmpty(expected);
            actual = ProbeCatalogSetterAccess(release, expected);
            testCase.assertNumElements(actual, numel(expected));
            testCase.verifyEqual(string({actual.runtimeSetAccess}), string({expected.runtimeSetAccess}));
            testCase.verifyEqual(string({actual.nativeSetAccess}), string({expected.nativeSetAccess}));
            testCase.verifyEqual(string({actual.errorId}), repmat("", 1, numel(actual)));
            for observation = actual
                ledger = jsondecode(fileread(fullfile(release, "components", observation.componentId + ".json")));
                properties = ledger.properties;
                if iscell(properties)
                    paths = cellfun(@(item) string(item.path), properties);
                    property = properties{paths == observation.path};
                else
                    property = properties(string({properties.path}) == observation.path);
                end
                testCase.verifyEqual(string(property.runtimeSetAccess), observation.runtimeSetAccess);
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
