classdef (TestTags = {'fast', 'catalog'}) CallbackDiscoveryTest < matlab.unittest.TestCase
    % CallbackDiscoveryTest Verify callback discovery from effective catalog contracts.
    %   These tests cover every concrete runtime variant and ensure callback
    %   discovery does not change property editability or Safe Preview policy.

    methods (Test)
        function discoversEveryVariantInCatalogOrder(testCase)
            % discoversEveryVariantInCatalogOrder Compare discovery with each concrete catalog surface.
            registry = macd.model.ComponentRegistry.createDefault();
            ids = registry.listVariantIds();

            % Include every direct parent so contextual properties cannot leak into discovery.
            for index = 1:numel(ids)
                definition = registry.getById(ids(index));
                parents = unique(["" definition.AllowedParentFactories]);
                for parent = parents
                    properties = registry.getEffectiveProperties(definition.Factory, ...
                        parent, definition.CreationArguments);
                    expected = strings(1, 0);
                    for property = properties(:)'
                        if isfield(property.ValueSchema, "kind") && ...
                                string(property.ValueSchema.kind) == "callback"
                            expected(end + 1) = property.Path; %#ok<AGROW>
                        end
                    end
                    callbacks = registry.getEffectiveCallbacks(definition.Factory, ...
                        parent, definition.CreationArguments);
                    testCase.verifyEqual(reshape(string({callbacks.Path}), 1, []), expected);
                    testCase.verifyFalse(any(ismember(string({callbacks.Path}), ...
                        ["Interruptible", "BusyAction"])));
                    if ~isempty(callbacks)
                        original = properties(ismember(string({properties.Path}), expected));
                        testCase.verifyEqual([callbacks.IsEditable], [original.IsEditable]);
                        testCase.verifyEqual(string({callbacks.Editor}), string({original.Editor}));
                        testCase.verifyEqual(string({callbacks.PreviewPolicy}), ...
                            string({original.PreviewPolicy}));
                    end
                end
            end
        end

        function distinguishesButtonConstructionStyles(testCase)
            % distinguishesButtonConstructionStyles Resolve binding names from the concrete button style.
            registry = macd.model.ComponentRegistry.createDefault();
            push = registry.getEffectiveCallbacks("uibutton", "uifigure", {});
            state = registry.getEffectiveCallbacks("uibutton", "uifigure", {'state'});
            testCase.verifyTrue(any(string({push.Path}) == "ButtonPushedFcn"));
            testCase.verifyFalse(any(string({push.Path}) == "ValueChangedFcn"));
            testCase.verifyTrue(any(string({state.Path}) == "ValueChangedFcn"));
            testCase.verifyFalse(any(string({state.Path}) == "ButtonPushedFcn"));
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
