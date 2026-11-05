classdef (TestTags = {'inspector', 'ui'}) DefaultValueProviderTest < matlab.unittest.TestCase
    % DefaultValueProviderTest Verify runtime default probes remain model-free.

    methods (Test)
        function resolvesGridDefaultsWithoutMutation(testCase)
            % resolvesGridDefaultsWithoutMutation Probe one Grid child without document mutation.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("DefaultsApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", grid.Id);
            provider = yamada.ui.inspector.DefaultValueProvider(registry);
            properties = registry.getEffectiveProperties("uilabel", "uigridlayout");
            definition = properties(find(string({properties.Path}) == "Layout.Row", 1));
            [found, value] = provider.resolve(label, "uigridlayout", definition);
            testCase.verifyTrue(found);
            testCase.verifyEqual(value, 1);
            [againFound, againValue] = provider.resolve(label, "uigridlayout", definition);
            testCase.verifyTrue(againFound);
            testCase.verifyEqual(againValue, value);
            testCase.verifyEmpty(label.getProperty("Visible"));
        end
    end

    methods (Test, TestTags = {'fast'})
        function resolvesKnownAndUnknownDefaults(testCase)
            % resolvesKnownAndUnknownDefaults Report known and unavailable properties consistently.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("DefaultsApp", registry);
            listBox = document.insertComponent(registry, "uilistbox", document.RootComponentId);
            provider = yamada.ui.inspector.DefaultValueProvider(registry);
            properties = registry.getEffectiveProperties("uilistbox", "uifigure");
            selected = properties(ismember(string({properties.Path}), ["Visible", "Enable"]));
            selected(end + 1) = yamada.model.PropertyDefinition("NoSuchProperty", [], false, true, struct());
            testCase.verifyNumElements(selected, 3);
            results = provider.resolveAll(listBox, "uifigure", selected);
            testCase.verifyEqual(results.Found, [true true false]);
            repeated = provider.resolveAll(listBox, "uifigure", selected);
            testCase.verifyEqual(repeated, results);
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
