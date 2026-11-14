classdef (TestTags = {'fast', 'model', 'generation'}) ScopedCommitValidationTest < matlab.unittest.TestCase
    % ScopedCommitValidationTest Verify committed changes retain complete diagnostic guarantees.
    %   Synthetic source is parsed without constructing its application or running callbacks.
    properties (TestParameter)
        % Layout - Parent arrangement used to test unrelated state reuse.
        %   The nested chain includes a direct grid parent, so a single-grid
        %   variant exercises no additional scope path.
        Layout = {"absolute", "nested"}
    end
    methods (Test)
        function freshSettingsDoNotRevalidateUnrelatedFields(testCase, Layout)
            % freshSettingsDoNotRevalidateUnrelatedFields Compare scoped results with full validation after each insertion.
            registry = yamada.model.ComponentRegistry.createDefault();
            [document, names] = makeFixture(registry, string(Layout));
            baseline = document.validatePropertyCommit(registry);
            testCase.assertFalse(yamada.validation.ModelValidator.hasErrors(baseline));
            paths = ["Value", "Tooltip", "FontSize"];
            values = {2, "New hint", 17};
            for index = 1:3
                component = document.getComponentByName(names(index));
                testCase.assertEmpty(component.getProperty(paths(index)));
                document.setProperty(component.Id, paths(index), values{index}, registry);
                actual = document.validatePropertyCommit(registry);
                expected = yamada.validation.ModelValidator.validate(document, registry);
                testCase.verifyEqual(actual, expected);
                testCase.verifyEqual(document.HistoryIndex, index);
                % No caller-owned diagnostic refresh can replace the retained proof.
                document.Diagnostics = yamada.model.Diagnostic("presentation", "warning", "Presentation only.");
                testCase.verifyEqual(document.validatePropertyCommit(registry), expected);
            end
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            parsed = yamada.source.AppSourceParser.parseText(source, registry);
            for index = 1:3
                testCase.verifyEqual(parsed.getComponentByName(names(index)).getProperty(paths(index)).LiteralValue, values{index});
            end
        end

        function pendingScopesRejectChangedInputs(testCase, Layout)
            % pendingScopesRejectChangedInputs Never reuse a pending scope after another document or catalog write.
            for kind = ["entry", "metadata", "registry", "history"]
                registry = yamada.model.ComponentRegistry.createDefault();
                [document, names] = makeFixture(registry, string(Layout));
                document.validatePropertyCommit(registry);
                target = document.getComponentByName(names(1));
                document.setProperty(target.Id, "Tooltip", "Pending", registry);
                switch kind
                    case "entry"
                        document.getComponentByName(names(end)).setProperty("Value", 3);
                    case "metadata"
                        document.Metadata.OtherWriter = true;
                    case "registry"
                        registry.register(registry.get("uilabel"));
                    case "history"
                        document.undo();
                end
                actual = document.validatePropertyCommit(registry);
                testCase.verifyEqual(actual, yamada.validation.ModelValidator.validate(document, registry));
            end
        end

        function preparedCommitsCanChainFullProofs(testCase, Layout)
            % preparedCommitsCanChainFullProofs Reuse complete pre-commit proofs across distinct edits without a post-check.
            registry = yamada.model.ComponentRegistry.createDefault();
            [document, names] = makeFixture(registry, string(Layout));
            document.validatePropertyCommit(registry);
            document.setProperty(document.getComponentByName(names(1)).Id, "Tooltip", "First", registry);
            document.setProperty(document.getComponentByName(names(2)).Id, "Tooltip", "Second", registry);
            actual = document.validatePropertyCommit(registry);
            testCase.verifyEqual(actual, yamada.validation.ModelValidator.validate(document, registry));
        end
    end
end

function [document, names, depth] = makeFixture(registry, layout)
% makeFixture Build independent numeric owners under zero, one, or several grid ancestors.
arguments (Input)
    registry (1, 1) yamada.model.ComponentRegistry
    layout (1, 1) string
end
arguments (Output)
    document (1, 1) yamada.model.DocumentModel
    names (1, :) string
    depth (1, 1) double
end
document = yamada.model.NewAppFactory.createEmpty("ScopedValidationFixture", registry);
parent = document.RootComponentId;
depth = double(layout ~= "absolute");
if layout == "nested", depth = 4; end
for index = 1:depth
    grid = document.insertComponent(registry, "uigridlayout", parent);
    grid.setProperty("RowHeight", repmat({"1x"}, 1, 12));
    grid.setProperty("ColumnWidth", {"1x"});
    parent = grid.Id;
end
names = strings(1, 0);
for index = 1:12
    component = document.insertComponent(registry, "uieditfield", parent, {"numeric"});
    if depth > 0
        component.setProperty("Layout.Row", index);
        component.setProperty("Layout.Column", 1);
    end
    names(end + 1) = component.Name; %#ok<AGROW>
end
source = yamada.source.NewAppGenerator(registry).generate(document);
document = yamada.source.AppSourceParser.parseText(source, registry);
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
