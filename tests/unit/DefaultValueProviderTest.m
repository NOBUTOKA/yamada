classdef DefaultValueProviderTest < matlab.unittest.TestCase
    % DefaultValueProviderTest Verify runtime default probes remain model-free.

    methods (Test)
        function resolvesAndCachesGridDefaults(testCase)
            % resolvesAndCachesGridDefaults Probe one Grid child without document mutation.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("DefaultsApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", grid.Id);
            provider = macd.ui.inspector.DefaultValueProvider(registry);
            properties = registry.getEffectiveProperties("uilabel", "uigridlayout");
            definition = properties(find(string({properties.Path}) == "Layout.Row", 1));
            [found, value] = provider.resolve(label, "uigridlayout", definition);
            testCase.verifyTrue(found);
            testCase.verifyEqual(value, 1);
            count = provider.cacheEntryCount();
            provider.resolve(label, "uigridlayout", definition);
            testCase.verifyEqual(provider.cacheEntryCount(), count);
            testCase.verifyEmpty(label.getProperty("Visible"));
        end
    end
end

%{
MatlabAppClassDesigner - Runtime default provider tests.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
