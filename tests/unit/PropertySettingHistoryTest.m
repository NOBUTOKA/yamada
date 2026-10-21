classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) PropertySettingHistoryTest < matlab.unittest.TestCase
    % PropertySettingHistoryTest Verify shared source history and original-location edits.
    %   The tests parse owned source fixtures without constructing or executing
    %   the represented application and check immutable occurrence ownership.

    methods (Test)
        function repeatedNumericEditsRetainEverySourceOccurrence(testCase)
            % repeatedNumericEditsRetainEverySourceOccurrence Replace only the final owned value in either syntax.
            registry = macd.model.ComponentRegistry.createDefault();
            for assignments = [false true]
                statements = "app.StatusLabel = uilabel(app.UIFigure, FontSize=17); % constructor";
                target = "FontSize=17";
                replacement = "FontSize=31";
                if assignments
                    statements = [statements, ...
                        "app.StatusLabel.FontSize = 19; % earlier", ...
                        "app.StatusLabel.FontSize = 21; % final"]; %#ok<AGROW>
                    target = "FontSize = 21";
                    replacement = "FontSize = 31";
                end
                source = testCase.fixture(statements);
                document = macd.source.AppSourceParser.parseText(source, registry);
                label = document.getComponentByName("StatusLabel");
                settings = label.Settings;
                document.setProperty(label.Id, "FontSize", 23, registry);
                document.setPropertyBatch(label.Id, ...
                    macd.model.PropertyTransaction.singleChange("FontSize", 31), registry);
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), ...
                    replace(source, target, replacement));
                testCase.verifyEqual(label.Settings, settings);
                testCase.verifyEqual(document.OriginalText, source);
                document.undo();
                document.undo();
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            end
        end

        function subtreeDeletionRemovesAllHistoricalAssignments(testCase)
            % subtreeDeletionRemovesAllHistoricalAssignments Avoid leaving shadowed settings after deletion.

            source = testCase.fixture([ ...
                "app.StatusLabel = uilabel(app.UIFigure, Text=""First"");", ...
                "app.StatusLabel.Text = ""Second"";", ...
                "app.StatusLabel.Text = ""Third"";"]);
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("StatusLabel");
            document.removeSubtree(component.Id, registry);
            generated = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyFalse(contains(generated, "app.StatusLabel"));
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyNumElements(document.getComponent(component.Id).getSettings("Text"), 3);
        end

        function retainsConstructorAndAllLaterAssignments(testCase)
            % retainsConstructorAndAllLaterAssignments Keep the last explicit setting as the editable projection.

            source = testCase.fixture([ ...
                "app.StatusLabel = uilabel(app.UIFigure, Text=""First"");", ...
                "app.StatusLabel.Tooltip = ""Hint"";", ...
                "app.StatusLabel.Text = ""Second"";", ...
                "app.StatusLabel.Text = ""Third"";"]);
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("StatusLabel");
            settings = component.getSettings("Text");
            testCase.verifyEqual(string({settings.Method}), ["nameValue", "assignment", "assignment"]);
            testCase.verifyEqual([settings.LiteralValue], ["First", "Second", "Third"]);
            testCase.verifyEqual(component.getProperty("Text").LiteralValue, "Third");
            testCase.verifyTrue(all(diff([component.Settings.Sequence]) > 0));

            document.setProperty(component.Id, "Text", "Updated");
            [generated, diagnostics] = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(generated, replace(source, """Third""", """Updated"""));
            testCase.verifyEqual([component.getSettings("Text").LiteralValue], ["First", "Second", "Third"]);
        end

        function constructorEditPreservesBothSyntaxSpellingsAndComments(testCase)
            % constructorEditPreservesBothSyntaxSpellingsAndComments Replace only the original argument value.

            registry = macd.model.ComponentRegistry.createDefault();
            for argument = ["Text=""First""", """Text"", ""First"""]
                source = testCase.fixture([ ...
                    "app.StatusLabel = uilabel(app.UIFigure, ... % keep constructor comment", ...
                    "    " + argument + "); % keep trailing comment"]);
                document = macd.source.AppSourceParser.parseText(source, registry);
                component = document.getComponentByName("StatusLabel");
                setting = component.getSettings("Text");
                document.setProperty(component.Id, "Text", "Updated");
                generated = macd.source.RoundTripGenerator(registry).generate(document);
                testCase.verifyEqual(generated, replace(source, """First""", """Updated"""));
                testCase.verifyEqual(component.CreationArguments, {"Text", "Updated"});
                testCase.verifyEqual(setting.LiteralValue, "First");
                testCase.verifyNumElements(component.getSettings("Text"), 1);

                document.undo();
                testCase.verifyEqual(component.CreationArguments, {"Text", "First"});
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
                document.redo();
                testCase.verifyEqual(component.getSettings("Text").Id, setting.Id);
                testCase.verifyEqual(component.getProperty("Text").LiteralValue, "Updated");
            end
        end

        function laterLiteralOverridesEarlierOpaqueSettingWithoutDiscardingIt(testCase)
            % laterLiteralOverridesEarlierOpaqueSettingWithoutDiscardingIt Separate source opacity from final certainty.

            source = testCase.fixture([ ...
                "app.StatusLabel = uilabel(app.UIFigure, Text=""Initial"" + ""Text"");", ...
                "app.StatusLabel.Text = ""Ready"";"]);
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("StatusLabel");
            settings = component.getSettings("Text");
            testCase.verifyNumElements(settings, 2);
            testCase.verifyEqual(settings(1).SourceExpression, """Initial"" + ""Text""");
            testCase.verifyTrue(component.getProperty("Text").IsEditable);
            document.setProperty(component.Id, "Text", "Updated");
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), ...
                replace(source, """Ready""", """Updated"""));
        end

        function noEditPreservesCommentsInsideAssignmentValues(testCase)
            % noEditPreservesCommentsInsideAssignmentValues Compare parsed originals instead of reparsing raw trivia.

            source = testCase.fixture([ ...
                "app.StatusLabel = uilabel(app.UIFigure);", ...
                "app.StatusLabel.Position = [10 ... % keep inner comment", ...
                "    20 100 30];"]);
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
        end

        function subtreeSnapshotsRetainHistoryAndIndependentRequestedValues(testCase)
            % subtreeSnapshotsRetainHistoryAndIndependentRequestedValues Copy source occurrences without live handles.

            source = testCase.fixture([ ...
                "app.StatusLabel = uilabel(app.UIFigure, Text=""First"");", ...
                "app.StatusLabel.Text = ""Second"";"]);
            document = macd.source.AppSourceParser.parseText(source, macd.model.ComponentRegistry.createDefault());
            component = document.getComponentByName("StatusLabel");
            document.setProperty(component.Id, "Text", "Requested");
            snapshot = macd.model.SubtreeSnapshot(document, component.Id);
            restored = snapshot.materialize();
            restored.setProperty("Text", "Other");
            testCase.verifyEqual(component.getProperty("Text").LiteralValue, "Requested");
            testCase.verifyEqual([restored.getSettings("Text").LiteralValue], ["First", "Second"]);
            restoredSettings = restored.getSettings("Text");
            originalSettings = component.getSettings("Text");
            testCase.verifyEqual(string({restoredSettings.Id}), string({originalSettings.Id}));
        end
    end

    methods (Static, Access = private)
        function source = fixture(body)
            % fixture Build a complete initializer with explicitly owned source settings.
            arguments (Input)
                body (1, :) string
            end
            arguments (Output)
                source (1, 1) string
            end

            source = strjoin(["classdef SettingApp < handle", ...
                "    properties", "        UIFigure matlab.ui.Figure", ...
                "        StatusLabel matlab.ui.control.Label", "    end", "    methods", ...
                "        function app = SettingApp", "            createComponents(app);", "        end", ...
                "        function createComponents(app)", "            app.UIFigure = uifigure(""Visible"", ""off"");", ...
                "            " + body, "        end", "    end", "end"], sprintf("\r\n"));
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
