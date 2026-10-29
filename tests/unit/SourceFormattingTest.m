classdef (TestTags = {'fast', 'generation', 'parser', 'model'}) SourceFormattingTest < matlab.unittest.TestCase
    % SourceFormattingTest Verify local formatting without executing edited apps.
    %   Text fixtures cover indentation, owned deletions, and grouped settings.

    methods (Test)
        function addedComponentsInheritSpacesAndTabs(testCase)
            % addedComponentsInheritSpacesAndTabs Preserve local indentation and newline conventions.
            registry = macd.model.ComponentRegistry.createDefault();
            for ending = [string(newline), string(sprintf("\r\n"))]
                for indent = ["            ", string(char(9))]
                    original = SourceFormattingTest.fixture(ending, indent);
                    document = macd.source.AppSourceParser.parseText(original, registry);
                    component = document.insertComponent(registry, "uilabel", document.RootComponentId);
                    document.setProperty(component.Id, "Text", "Added", registry);
                    [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(document);
                    testCase.assertFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
                    testCase.verifySubstring(source, ending + "        " + component.Name + " matlab.ui.control.Label");
                    testCase.verifySubstring(source, ending + indent + "app." + component.Name + " = uilabel(app.UIFigure);");
                    testCase.verifySubstring(source, ending + indent + "app." + component.Name + ".Text = ""Added"";");
                    reopened = macd.source.AppSourceParser.parseText(source, registry);
                    testCase.verifyEqual(reopened.getComponentByName(component.Name).getProperty("Text").LiteralValue, "Added");
                end
            end
        end

        function removedSubtreeDoesNotLeaveVacatedLines(testCase)
            % removedSubtreeDoesNotLeaveVacatedLines Remove full owned lines and retain neighboring blocks.
            registry = macd.model.ComponentRegistry.createDefault();
            ending = string(sprintf("\r\n"));
            original = SourceFormattingTest.fixture(ending, "            ");
            original = erase(original, " % keep this comment");
            document = macd.source.AppSourceParser.parseText(original, registry);
            document.removeSubtree(document.getComponentByName("First").Id, registry);
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.assertFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            expected = regexprep(original, '(?m)^ *First matlab.ui.control.Label\r\n', '');
            expected = regexprep(expected, '(?m)^ *app\.First[^\r\n]*\r\n', '');
            testCase.verifyEqual(source, expected);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), original);
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), expected);
        end

        function readOnlyPropertyDoesNotTriggerDeletionCleanup(testCase)
            % readOnlyPropertyDoesNotTriggerDeletionCleanup Preserve restricted setter lines and their whitespace.
            registry = macd.model.ComponentRegistry.createDefault();
            ending = string(newline);
            original = SourceFormattingTest.fixture(ending, "            ");
            extra = "            app.UIFigure.Number = 1;" + ending;
            original = replace(original, "            app.First =", extra + "            app.First =");
            document = macd.source.AppSourceParser.parseText(original, registry);
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.assertFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(source, original);
        end

        function newPropertiesFollowTheOwnersExistingSettings(testCase)
            % newPropertiesFollowTheOwnersExistingSettings Keep edits in their component block through history and reopen.
            registry = macd.model.ComponentRegistry.createDefault();
            ending = string(sprintf("\r\n"));
            original = SourceFormattingTest.fixture(ending, "            ");
            document = macd.source.AppSourceParser.parseText(original, registry);
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "FontSize", 19, registry);
            document.setProperty(first.Id, "Tooltip", "Hint", registry);
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.assertFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            block = "            app.First.Text = ""First""; % keep this comment" + ending + ...
                "            app.First.FontSize = 19;" + ending + ...
                "            app.First.Tooltip = ""Hint"";";
            testCase.verifySubstring(source, block + ending + ending + "            app.Second =");
            document.undo();
            testCase.verifyFalse(contains(macd.source.RoundTripGenerator(registry).generate(document), ".Tooltip ="));
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            document = reopened;
            document.setProperty(document.getComponentByName("First").Id, "FontWeight", "bold", registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source, block + ending + "            app.First.FontWeight = ""bold"";" + ...
                ending + ending + "            app.Second =");
        end

        function insertedBlocksHaveOneBlankLineAtEachBoundary(testCase)
            % insertedBlocksHaveOneBlankLineAtEachBoundary Separate new blocks without splitting same-owner settings.
            for ending = [string(newline), string(sprintf("\r\n"))]
                for separator = [ending, ending + ending]
                    source = "    app.First.Text = ""First""; % note" + separator + ...
                        "    app.Last.Text = ""Last"";" + ending;
                    anchor = strfind(source, " % note") + strlength(" % note") - 1;
                    block = ending + "    app.Middle = uilabel(app.UIFigure);" + ending + ...
                        "    app.Middle.Text = ""Middle"";";
                    edits = struct("Start", anchor + 1, "End", anchor, "Text", block);
                    edits = macd.source.SourceFormatting.separateComponents(source, edits);
                    actual = extractBefore(source, edits.Start) + edits.Text + extractAfter(source, edits.End);
                    expected = "    app.First.Text = ""First""; % note" + ending + ending + ...
                        "    app.Middle = uilabel(app.UIFigure);" + ending + ...
                        "    app.Middle.Text = ""Middle"";" + ending + ending + ...
                        "    app.Last.Text = ""Last"";" + ending;
                    testCase.verifyEqual(actual, expected);
                    testCase.verifyEqual(macd.source.SourceFormatting.separateComponents(source, edits), edits);
                end
            end
        end

        function multipleInsertedComponentsKeepTheirOwnSettingsTogether(testCase)
            % multipleInsertedComponentsKeepTheirOwnSettingsTogether Separate generated groups and preserve deletion history.
            registry = macd.model.ComponentRegistry.createDefault();
            ending = string(sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(SourceFormattingTest.fixture(ending, "            "), registry);
            first = document.insertComponent(registry, "uilabel", document.RootComponentId);
            second = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.setProperty(first.Id, "Text", "Added first", registry);
            document.setProperty(second.Id, "Text", "Added second", registry);
            generator = macd.source.RoundTripGenerator(registry);
            [source, diagnostics] = generator.generate(document);
            testCase.assertFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(source, "app.Second.Text = ""Second"";" + ending + ending + ...
                "            app." + first.Name + " = uilabel(app.UIFigure);");
            testCase.verifySubstring(source, ".Text = ""Added first"";" + ending + ending + ...
                "            app." + second.Name + " = uilabel(app.UIFigure);");
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(generator.generate(reopened), source);
            reopened.removeSubtree(reopened.getComponentByName(first.Name).Id, registry);
            removed = generator.generate(reopened);
            testCase.verifyFalse(contains(removed, "app." + first.Name + " ="));
            testCase.verifyFalse(contains(removed, ending + ending + ending));
            reopened.undo();
            testCase.verifyEqual(generator.generate(reopened), source);
        end

        function constructorArgumentInsertionKeepsItsOriginalWhitespace(testCase)
            % constructorArgumentInsertionKeepsItsOriginalWhitespace Do not format a partial statement as a new block.
            for ending = [string(newline), string(sprintf("\r\n"))]
                for body = ["    app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""]);", ...
                        "    app.Control = uidropdown(app.UIFigure, ..." + ending + ...
                        "        Items=[""A"" ""B""]); "]
                    source = "    app.UIFigure = uifigure;" + ending + body + ending;
                    anchor = strfind(source, "Items=[") - 1;
                    edits = struct("Start", anchor + 1, "End", anchor, "Text", "FontSize=18, ");
                    testCase.verifyEqual(macd.source.SourceFormatting.separateComponents(source, edits), edits);
                end
            end
        end

        function deletionKeepsCommentsAndInlineNeighbors(testCase)
            % deletionKeepsCommentsAndInlineNeighbors Preserve all source outside vacated lines.
            for ending = [string(newline), string(sprintf("\r\n"))]
                for line = ["    gone; % retained comment", "    gone; kept;"]
                    source = "before;" + ending + line + ending + "after;" + ending;
                    start = strfind(source, "gone;");
                    edits = struct("Start", start, "End", start + 4, "Text", "");
                    actual = SourceFormattingTest.apply(source, edits);
                    testCase.verifyEqual(actual, erase(source, "gone;"));
                end
                source = "before;" + ending + "    gone;" + ending + "after;" + ending;
                start = strfind(source, "gone;");
                edits = struct("Start", start, "End", start + 4, "Text", "");
                testCase.verifyEqual(SourceFormattingTest.apply(source, edits), ...
                    "before;" + ending + "after;" + ending);
                edits(2) = struct("Start", start + 5, "End", start + 4, "Text", ending + "    added;");
                testCase.verifyEqual(SourceFormattingTest.apply(source, edits), ...
                    "before;" + ending + "    added;" + ending + "after;" + ending);
            end
        end

        function deletionRemovesBlockSeparatorsAndCompleteInlineLines(testCase)
            % deletionRemovesBlockSeparatorsAndCompleteInlineLines Clean only whitespace adjacent to owned removals.
            for ending = [string(newline), string(sprintf("\r\n"))]
                source = "before;" + ending + ending + "    one;" + ending + ...
                    "    two;" + ending + ending + "after;" + ending;
                first = strfind(source, "one;");
                second = strfind(source, "two;");
                edits = struct("Start", {first, second}, "End", {first + 3, second + 3}, "Text", {"", ""});
                testCase.verifyEqual(SourceFormattingTest.apply(source, edits), ...
                    "before;" + ending + ending + "after;" + ending);
                source = "before;" + ending + "    one; two;" + ending + "after;" + ending;
                first = strfind(source, "one;");
                second = strfind(source, "two;");
                edits = struct("Start", {first, second}, "End", {first + 3, second + 3}, "Text", {"", ""});
                testCase.verifyEqual(SourceFormattingTest.apply(source, edits), ...
                    "before;" + ending + "after;" + ending);
                source = "    one;" + ending + "after;" + ending;
                edits = struct("Start", 5, "End", 8, "Text", "");
                testCase.verifyEqual(SourceFormattingTest.apply(source, edits), "after;" + ending);
                source = "before;" + ending + "    one;";
                start = strfind(source, "one;");
                edits = struct("Start", start, "End", start + 3, "Text", "");
                testCase.verifyEqual(SourceFormattingTest.apply(source, edits), "before;");
            end
        end
    end

    methods (Static, Access = private)
        function source = fixture(ending, indent)
            % fixture Build an inert app with adjacent component setting blocks.
            arguments (Input)
                ending (1, 1) string
                indent (1, 1) string
            end
            arguments (Output)
                source (1, 1) string
            end
            lines = ["classdef FormattingApp < handle", "    properties", ...
                "        UIFigure matlab.ui.Figure", "        First matlab.ui.control.Label", ...
                "        Second matlab.ui.control.Label", "    end", "    methods", ...
                "        function app = FormattingApp", "            createComponents(app);", "        end", ...
                "        function createComponents(app)", indent + "app.UIFigure = uifigure(Visible='off');", ...
                indent + "app.First = uilabel(app.UIFigure);", ...
                indent + "app.First.Text = ""First""; % keep this comment", ...
                indent + "app.Second = uilabel(app.UIFigure);", ...
                indent + "app.Second.Text = ""Second"";", "        end", "    end", "end"];
            source = strjoin(lines, ending) + ending;
        end

        function source = apply(source, edits)
            % apply Apply normalized source edits in reverse offset order.
            arguments (Input)
                source (1, 1) string
                edits struct
            end
            arguments (Output)
                source (1, 1) string
            end
            edits = macd.source.SourceFormatting.cleanDeletions(source, edits);
            [~, order] = sort([edits.Start], "descend");
            for index = order
                edit = edits(index);
                source = extractBefore(source, edit.Start) + edit.Text + extractAfter(source, edit.End);
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
