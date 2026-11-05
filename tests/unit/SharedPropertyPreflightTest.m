classdef (TestTags = {'fast', 'model', 'generation'}) SharedPropertyPreflightTest < matlab.unittest.TestCase
    % SharedPropertyPreflightTest Reuse complete owned source proofs across components and literal kinds.
    %   Cached configurations remain independent, and unsafe or stale inputs retain
    %   full source preflight without executing an input application.
    properties (Access = private)
        Registry yamada.model.ComponentRegistry
    end
    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Use the production catalog for every local proof.
            testCase.Registry = yamada.model.ComponentRegistry.createDefault();
        end
    end
    methods (Test)
        function reusesCompleteConfigurationAfterInsertion(testCase)
            % reusesCompleteConfigurationAfterInsertion Avoid reparsing an already validated complete plan.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.fixture(layout);
                button = document.getComponentByName("Button");
                field = document.getComponentByName("Field");
                document.setProperty(button.Id, "FontSize", 14, testCase.Registry);
                parent = document.getComponent(field.ParentId);
                document.insertComponent(testCase.Registry, "uilabel", parent.Id);
                plan = yamada.source.PropertySourcePlan.combined(document, parent, testCase.Registry);
                original = document.OriginalText;
                document.setProperty(field.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                testCase.verifyEqual(field.getProperty("Value").LiteralValue, 2);
                testCase.verifyEqual(plan.Document.getComponentByName("Field").getProperty("Value").LiteralValue, 1);
                older = plan;
                testCase.verifyEqual(older.Document.getComponentByName("Field").getProperty("Value").LiteralValue, 1);
                testCase.verifyEqual(document.OriginalText, original);
                document.undo(); document.redo();
                source = yamada.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = yamada.source.AppSourceParser.parseText(source, testCase.Registry);
                testCase.verifyEqual(parsed.getComponentByName("Field").getProperty("Value").LiteralValue, 2);
                testCase.verifyEqual(numel(parsed.Components), numel(document.Components));
            end
        end

        function sharesOwnedProofAcrossOwnersPathsAndLiteralKinds(testCase)
            % sharesOwnedProofAcrossOwnersPathsAndLiteralKinds Generalize independent number, text, color, and enum edits.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.fixture(layout);
                button = document.getComponentByName("Button");
                field = document.getComponentByName("Field");
                document.setProperty(button.Id, "FontSize", 14, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                ids = [button.Id, button.Id, button.Id, field.Id, field.Id];
                paths = ["Text", "FontColor", "Enable", "BackgroundColor", "HorizontalAlignment"];
                values = {"quoted ""text""; % untouched", [0.2 0.3 0.4], "off", [0.8 0.7 0.6], "center"};
                original = document.OriginalText;
                for index = 1:numel(paths)
                    document.setProperty(ids(index), paths(index), values{index}, testCase.Registry);
                    document.validatePropertyCommit(testCase.Registry);
                end
                source = yamada.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = yamada.source.AppSourceParser.parseText(source, testCase.Registry);
                for index = 1:numel(paths)
                    owner = document.getComponent(ids(index));
                    testCase.verifyEqual(parsed.getComponentByName(owner.Name).getProperty(paths(index)).LiteralValue, values{index});
                end
                testCase.verifyEqual(document.OriginalText, original);
                testCase.verifySubstring(source, "% untouched initialization");
                testCase.verifyEqual(document.HistoryIndex, 6);
            end
        end

        function numericPolicyAppliesToEveryRegisteredFamily(testCase)
            % numericPolicyAppliesToEveryRegisteredFamily Use numericValue metadata instead of a factory allowlist.
            for factory = ["uieditfield", "uispinner"]
                document = testCase.fixture("flat", factory);
                field = document.getComponentByName("Field");
                parent = document.getComponent(field.ParentId);
                yamada.source.PropertySourcePlan.combined(document, parent, testCase.Registry);
                document.setProperty(field.Id, "Value", 2.5, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                source = yamada.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = yamada.source.AppSourceParser.parseText(source, testCase.Registry);
                testCase.verifyEqual(parsed.getComponentByName("Field").getProperty("Value").LiteralValue, 2.5);
            end
        end

        function changedInputsDiscardSharedPreflight(testCase)
            % changedInputsDiscardSharedPreflight Reject a complete plan from a different semantic input version.
            document = testCase.fixture("flat");
            field = document.getComponentByName("Field");
            parent = document.getComponent(field.ParentId);
            yamada.source.PropertySourcePlan.combined(document, parent, testCase.Registry);
            document.Metadata.AdditionalInput = "changed after shared proof";
            document.setProperty(field.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            testCase.verifyEqual(field.getProperty("Value").LiteralValue, 2);
        end

        function publicPlansAndRejectedValuesCannotChangeOwnedProof(testCase)
            % publicPlansAndRejectedValuesCannotChangeOwnedProof Preserve public isolation and atomic rejection.
            document = testCase.fixture("flat");
            button = document.getComponentByName("Button");
            parent = document.getComponent(button.ParentId);
            plan = yamada.source.PropertySourcePlan.combined(document, parent, testCase.Registry);
            plan.Document.getComponentByName("Button").setProperty("Text", "Foreign mutation");
            before = document.OriginalText;
            testCase.verifyError(@() document.setProperty(button.Id, "FontColor", [2 0 0], testCase.Registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyEqual(button.getProperty("FontColor").LiteralValue, [0 0 0]);
            document.setProperty(button.Id, "Text", "Accepted", testCase.Registry);
            testCase.verifyEqual(button.getProperty("Text").LiteralValue, "Accepted");
            testCase.verifyEqual(document.OriginalText, before);
            source = yamada.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyFalse(contains(source, "Foreign mutation"));
        end

        function descendantGeometryKeepsCompletePreflight(testCase)
            % descendantGeometryKeepsCompletePreflight Retain full validation for layout-changing container inputs.
            document = testCase.fixture("flat");
            root = document.getComponent(document.RootComponentId);
            yamada.source.PropertySourcePlan.combined(document, root, testCase.Registry);
            document.setProperty(root.Id, "AutoResizeChildren", "on", testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            testCase.verifyEqual(root.getProperty("AutoResizeChildren").LiteralValue, "on");
        end
    end
    methods (Access = private)
        function document = fixture(testCase, layout, factory)
            % fixture Build inert source with owned settings and optional nested grids.
            arguments (Input)
                testCase (1, 1) SharedPropertyPreflightTest
                layout (1, 1) string
                factory (1, 1) string = "uieditfield"
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
            end
            type = "matlab.ui.control.NumericEditField";
            if factory == "uispinner", type = "matlab.ui.control.Spinner"; end
            declarations = ["UIFigure matlab.ui.Figure", "Field " + type, "Button matlab.ui.control.Button"];
            body = ["app.UIFigure = uifigure('Visible','off');", "app.UIFigure.AutoResizeChildren = 'off';", "app.UIFigure.Position = [100 100 640 600];"];
            parent = "UIFigure";
            if layout ~= "absolute"
                depth = 1;
                if layout == "nested", depth = 4; end
                for index = 1:depth
                    name = "Grid" + index;
                    declarations(end + 1) = name + " matlab.ui.container.GridLayout"; %#ok<AGROW>
                    body = [body, "app." + name + " = uigridlayout(app." + parent + ",[2 1]);", ...
                        "app." + name + ".RowHeight = {'fit','1x'};", "app." + name + ".ColumnWidth = {'1x'};"]; %#ok<AGROW>
                    parent = name;
                end
            end
            creation = "app.Field = " + factory + "(app." + parent + ");";
            if factory == "uieditfield", creation = "app.Field = uieditfield(app." + parent + ",'numeric');"; end
            body = [body, "% untouched initialization", creation, "app.Field.Value = 1;", ...
                "app.Field.BackgroundColor = [1 1 1];", "app.Field.HorizontalAlignment = 'right';", ...
                "app.Button = uibutton(app." + parent + ");", "app.Button.Text = 'Before';", ...
                "app.Button.FontColor = [0 0 0];", "app.Button.Enable = 'on';"];
            if layout ~= "absolute"
                body = [body, "app.Field.Layout.Row = 1;", "app.Button.Layout.Row = 2;"];
            end
            source = strjoin(["classdef SharedPropertyFixture < handle", "properties", declarations, "end", ...
                "methods", "function app = SharedPropertyFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", body, "end", "end", "end"], sprintf("\r\n"));
            document = yamada.source.AppSourceParser.parseText(source, testCase.Registry);
        end
    end
    methods (Static, Access = private)
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
