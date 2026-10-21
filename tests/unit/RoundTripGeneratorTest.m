classdef (TestTags = {'fast', 'generation'}) RoundTripGeneratorTest < matlab.unittest.TestCase
    % RoundTripGeneratorTest Verify conservative source-preserving rewrites.

    methods (Test)
        function newChildFollowsParentCreationAcrossHelpers(testCase)
            % newChildFollowsParentCreationAcrossHelpers Use execution visits when helper file order differs.
            registry = macd.model.ComponentRegistry.createDefault();
            source = strjoin(["classdef AnchorApp < handle"; "properties"; ...
                "UIFigure matlab.ui.Figure"; "EarlyPanel matlab.ui.container.Panel"; ...
                "LatePanel matlab.ui.container.Panel"; "end"; "methods"; ...
                "function app = AnchorApp"; "createEarly(app);"; "createLate(app);"; "end"; ...
                "function createLate(app)"; "app.LatePanel = uipanel(app.UIFigure);"; "end"; ...
                "function createEarly(app)"; "app.UIFigure = uifigure(Visible='off');"; ...
                "app.EarlyPanel = uipanel(app.UIFigure);"; "end"; "end"; "end"], newline) + newline;
            document = macd.source.AppSourceParser.parseText(source, registry);
            parent = document.getComponentByName("LatePanel");
            child = macd.model.ComponentRecord("new-child", "NewChild", "uilabel", "matlab.ui.control.Label");
            child.setProperty("Text", "retained");
            document.addComponent(child, parent.Id);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.assertGreaterThan(strlength(source), 0);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            actual = parsed.getComponentByName("NewChild");
            testCase.assertNotEmpty(actual);
            testCase.verifyEqual(actual.ParentId, parsed.getComponentByName("LatePanel").Id);
        end

        function noEditRoundTripPreservesExactSource(testCase)
            % noEditRoundTripPreservesExactSource Keep parsed bytes unchanged.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            [source, diagnostics] = generator.generate(document);

            testCase.verifyEqual(source, document.OriginalText);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function propertyEditChangesOnlyOwnedAssignment(testCase)
            % propertyEditChangesOnlyOwnedAssignment Replace one direct literal value.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            label = document.getComponentByName("LeftValueLabel");
            label.setProperty("Text", "First value");
            [source, diagnostics] = generator.generate(document);

            testCase.verifySubstring(source, "app.LeftValueLabel.Text = ""First value"";");
            testCase.verifySubstring(source, "app.CalculateButton.ButtonPushedFcn = @app.CalculateButtonPushed");
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function generatedComponentUsesAnchoredInsertion(testCase)
            % generatedComponentUsesAnchoredInsertion Add declaration and initialization.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            parent = document.getComponentByName("GridLayout");
            component = macd.model.ComponentRecord("generated-status", "StatusLabel", ...
                "uilabel", "matlab.ui.control.Label", "generated");
            component.setProperty("Text", "Ready");
            document.addComponent(component, parent.Id);
            [source, diagnostics] = generator.generate(document);

            testCase.verifySubstring(source, "StatusLabel matlab.ui.control.Label");
            testCase.verifySubstring(source, "app.StatusLabel = uilabel(app.GridLayout);");
            testCase.verifySubstring(source, "app.StatusLabel.Text = ""Ready"";");
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function insertedGridOmitsReadOnlyPosition(testCase)
            % insertedGridOmitsReadOnlyPosition Avoid read-only assignments when extending parsed apps.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            registry = macd.model.ComponentRegistry.createDefault();
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            testCase.verifyEmpty(grid.getProperty("Position"));
            grid.setProperty("Position", [1 1 300 200]);
            grid.setProperty("InnerPosition", [1 1 300 200]);
            grid.setProperty("OuterPosition", [1 1 300 200]);
            document.setProperty(grid.Id, "RowHeight", {"1x"});
            [source, diagnostics] = generator.generate(document);

            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(source, "app." + grid.Name + " = uigridlayout(app.UIFigure);");
            testCase.verifyFalse(contains(source, "app." + grid.Name + ".Position ="));
            testCase.verifyFalse(contains(source, "app." + grid.Name + ".InnerPosition ="));
            testCase.verifyFalse(contains(source, "app." + grid.Name + ".OuterPosition ="));
            testCase.verifySubstring(source, "app." + grid.Name + ".RowHeight = {""1x""};");
        end

        function removesOwnedCatalogReadOnlyAssignments(testCase)
            % removesOwnedCatalogReadOnlyAssignments Remove only known restricted setter assignments.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            original = replace(document.OriginalText, ...
                "app.GridLayout = uigridlayout(app.UIFigure);", ...
                "app.GridLayout = uigridlayout(app.UIFigure);" + newline + ...
                "            app.GridLayout.Position = [1 1 640 480];" + newline + ...
                "            app.GridLayout.InnerPosition = [1 1 620 460];" + newline + ...
                "            app.GridLayout.OuterPosition = [1 1 640 480];" + newline + ...
                "            app.UIFigure.Number = 1;" + newline + ...
                "            app.GridLayout.CustomUnknownProperty = 123;");
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(original, registry);
            grid = document.getComponentByName("GridLayout");
            testCase.assertNotEmpty(grid.getProperty("Position"));
            [source, diagnostics] = generator.generate(document);

            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyFalse(contains(source, "app.GridLayout.Position ="));
            testCase.verifyEmpty(regexp(source, ...
                'app\.\w+\.(InnerPosition|OuterPosition|Number)\s*=', "once"));
            testCase.verifySubstring(source, "app.GridLayout.CustomUnknownProperty = 123;");
            testCase.verifySubstring(source, "app.UIFigure.Position =");
            testCase.verifySubstring(source, "app.CalculateButton.ButtonPushedFcn = @app.CalculateButtonPushed");
        end

        function deletionRejectsExternalReference(testCase)
            % deletionRejectsExternalReference Block deletion when source uses the component.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            source = document.OriginalText + newline + "app.LeftValueLabel.Visible = 'on';";
            document = macd.source.AppSourceParser.parseText(source, ...
                macd.model.ComponentRegistry.createDefault());
            document.removeComponent("parsed-LeftValueLabel");
            [generated, diagnostics] = generator.generate(document);

            testCase.verifyEqual(generated, source);
            testCase.verifyTrue(any([diagnostics.Code] == "ambiguous-component-deletion"));
        end

        function checkboxTreePreservesWritableGeometrySettings(testCase)
            % checkboxTreePreservesWritableGeometrySettings Keep owned public geometry writes and edit the existing Position token.
            registry = macd.model.ComponentRegistry.createDefault();
            bodies = {["app.Tree = uitree(app.UIFigure, 'checkbox');", ...
                "app.Tree.InnerPosition = [10 20 150 200];", "app.Tree.Position = [30 40 160 210];"], ...
                "app.Tree = uitree(app.UIFigure, 'checkbox', InnerPosition=[10 20 150 200], Position=[30 40 160 210]);", ...
                "app.Tree = uitree(app.UIFigure, 'checkbox', 'InnerPosition', [10 20 150 200], 'Position', [30 40 160 210]);"};
            for body = bodies
                original = strjoin(["classdef GeometryFixture < handle", "properties", ...
                    "UIFigure matlab.ui.Figure", "Tree matlab.ui.container.CheckBoxTree", "end", "methods", ...
                    "function app = GeometryFixture", "createComponents(app);", "end", ...
                    "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                    body{1}, "end", "end", "end"], sprintf('\r\n'));
                document = macd.source.AppSourceParser.parseText(original, registry);
                generator = macd.source.RoundTripGenerator(registry);
                [source, diagnostics] = generator.generate(document);
                testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
                testCase.verifyEqual(source, original);
                tree = document.getComponentByName("Tree");
                testCase.assertNumElements(tree.getSettings("InnerPosition"), 1);
                target = tree.getSettings("Position");
                document.setProperty(tree.Id, "Position", [50 60 170 220], registry);
                [source, diagnostics] = generator.generate(document);
                testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
                testCase.verifyEqual(source, replace(original, "[30 40 160 210]", "[50 60 170 220]"));
                testCase.verifyEqual(tree.getSettings("Position").Id, target.Id);
                reopened = macd.source.AppSourceParser.parseText(source, registry);
                other = reopened.getComponentByName("Tree");
                testCase.verifyEqual(other.getProperty("Position").LiteralValue, [50 60 170 220]);
                testCase.verifyEqual(other.getSettings("Position").Method, target.Method);
                testCase.verifyNumElements(other.getSettings("InnerPosition"), 1);
            end
        end

        function ownedLeafDeletionRemovesOnlyOwnedSource(testCase)
            % ownedLeafDeletionRemovesOnlyOwnedSource Remove an unreferenced leaf.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            document.removeComponent("parsed-LeftValueLabel");
            [source, diagnostics] = generator.generate(document);

            testCase.verifyFalse(contains(source, "app.LeftValueLabel"));
            testCase.verifyFalse(contains(source, "LeftValueLabel  matlab.ui.control.Label"));
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function documentEditRewritesPositionAndGridAssignment(testCase)
            % documentEditRewritesPositionAndGridAssignment Verify canvas layout edits.

            % Route geometry changes through DocumentModel rather than records.
            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            root = document.getComponent(document.RootComponentId);
            result = document.getComponentByName("ResultLabel");
            document.setProperty(root.Id, "Position", [120 130 360 250]);
            document.setProperty(result.Id, "Layout.Row", 4);
            [source, diagnostics] = generator.generate(document);

            testCase.verifySubstring(source, ...
                "app.UIFigure.Position = [120 130 360 250];");
            testCase.verifySubstring(source, "app.ResultLabel.Layout.Row = 4;");
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function gridLayoutEditRewritesTracksAndChildPlacement(testCase)
            % gridLayoutEditRewritesTracksAndChildPlacement Keep a grid edit localized to owned literals.

            [document, generator] = RoundTripGeneratorTest.parsedFixture();
            grid = document.getComponentByName("GridLayout");
            button = document.getComponentByName("CalculateButton");
            changes = struct("ComponentId", {grid.Id, grid.Id, button.Id, button.Id}, ...
                "Path", {"RowHeight", "ColumnWidth", "Layout.Row", "Layout.Column"}, ...
                "Value", {{'fit', 42, '1x', 'fit', 'fit'}, {'2x', '1x'}, [3 4], [1 2]});
            document.applyGridLayoutEdit(grid.Id, changes);
            [source, diagnostics] = generator.generate(document);

            testCase.verifySubstring(source, ...
                "app.GridLayout.RowHeight = {'fit', 42, '1x', 'fit', 'fit'};");
            testCase.verifySubstring(source, "app.GridLayout.ColumnWidth = {'2x', '1x'};");
            testCase.verifySubstring(source, "app.CalculateButton.Layout.Row = [3 4];");
            testCase.verifySubstring(source, "app.CalculateButton.Layout.Column = [1 2];");
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
        end
    end

    methods (Static, Access = private)
        function [document, generator] = parsedFixture()
            % parsedFixture Load the preserved fixture and one shared generator.

            testPath = mfilename("fullpath");
            fixturePath = string(fullfile(fileparts(fileparts(testPath)), ...
                "fixtures", "handle", "SimpleCalculatorApp.m"));
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fixturePath, registry);
            generator = macd.source.RoundTripGenerator(registry);
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
