classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) PropertyInsertionBatchTest < matlab.unittest.TestCase
    % PropertyInsertionBatchTest Verify shared candidate evaluation across pending source owners.
    %   All fixtures are synthetic handle-based text and are never executed. Candidate
    %   sharing must preserve source ownership, setting order and caller isolation.
    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Load the release catalog used by placement and state checks.
            testCase.Registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Test)
        function parsesOneCandidateForTwelvePendingValueOwners(testCase)
            % parsesOneCandidateForTwelvePendingValueOwners Bound reparsing independently of owner count.
            document = testCase.numericFixture(12);
            original = document.OriginalText;
            for index = 1:12
                document.getComponentByName("Field" + index).setProperty("Value", index + 1);
            end
            profile clear; profile on;
            cleanup = onCleanup(@() profile("off"));
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            profile off;
            functions = profile("info").FunctionTable;
            matches = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
            testCase.verifyEqual(sum([functions(matches).NumCalls]), 1);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            for index = 1:12
                testCase.verifyEqual(parsed.getComponentByName("Field" + index).getProperty("Value").LiteralValue, index + 1);
            end
            testCase.verifyEqual(document.OriginalText, original);
            testCase.verifyEmpty(document.History);
        end

        function placementsMatchIndependentOwnersAndReturnedPlansStayPrivate(testCase)
            % placementsMatchIndependentOwnersAndReturnedPlansStayPrivate Reuse syntax without exposing retained models.
            document = testCase.numericFixture(2);
            for index = 1:2
                document.getComponentByName("Field" + index).setProperty("Value", index + 2);
            end
            for index = 1:2
                isolated = macd.source.AppSourceParser.parseText(document.OriginalText, testCase.Registry);
                single = isolated.getComponentByName("Field" + index);
                single.setProperty("Value", index + 2);
                reference = macd.source.PropertyInsertionPlanner.plan(isolated, single, testCase.Registry);
                component = document.getComponentByName("Field" + index);
                plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
                testCase.verifyEqual(plan.Edits, reference.Edits);
                testCase.verifyEqual(plan.Placements, reference.Placements);
                plan.Component.setProperty("Value", 99);
                plan.Document.getComponentByName("Field" + (3 - index)).setProperty("Value", 98);
                retained = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
                testCase.verifyEqual(retained.Component.getProperty("Value").LiteralValue, index + 2);
                testCase.verifyEqual(retained.Document.getComponentByName("Field" + (3 - index)).getProperty("Value").LiteralValue, 5 - index);
            end
            document.getComponentByName("Field1").setProperty("Value", 7);
            refreshed = macd.source.PropertyInsertionPlanner.plan(document, document.getComponentByName("Field2"), testCase.Registry);
            testCase.verifyEqual(refreshed.Document.getComponentByName("Field1").getProperty("Value").LiteralValue, 7);
        end

        function retainsExistingOccurrencesAndOtherUnsavedRequests(testCase)
            % retainsExistingOccurrencesAndOtherUnsavedRequests Preserve every original setting while replacing only the last.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uieditfield(app.UIFigure,'numeric');", ...
                "app.First.FontSize = 10; % earlier setting", ...
                "app.First.FontSize = 12; % latest setting", ...
                "app.Second = uieditfield(app.UIFigure,'numeric');"]);
            first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            first.setProperty("FontSize", 18);
            first.setProperty("Value", 3);
            second.setProperty("Value", 4);
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifySubstring(source, "app.First.FontSize = 10; % earlier setting");
            testCase.verifySubstring(source, "app.First.FontSize = 18; % latest setting");
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            testCase.verifyNumElements(parsed.getComponentByName("First").getSettings("FontSize"), 2);
            testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Value").LiteralValue, 3);
            testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("Value").LiteralValue, 4);
        end

        function preservesConstructorStyleAndAssignmentPrerequisites(testCase)
            % preservesConstructorStyleAndAssignmentPrerequisites Validate both constructor grouping and execution order.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uidropdown(app.UIFigure, Items=[""A"" ""B""], ItemsData=[10 20]);", ...
                "app.Second = uidropdown(app.UIFigure);", ...
                "app.Second.Items = [""A"" ""B""];", ...
                "app.Second.ItemsData = [10 20];"]);
            document.getComponentByName("First").setProperty("Value", 20);
            document.getComponentByName("Second").setProperty("Value", 10);
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            first = parsed.getComponentByName("First");
            second = parsed.getComponentByName("Second");
            testCase.verifyEqual(first.getSettings("Value").Method, "nameValue");
            testCase.verifyEqual(second.getSettings("Value").Method, "assignment");
            testCase.verifyGreaterThan(second.getSettings("Value").SourceSpan.StartOffset, ...
                second.getSettings("ItemsData").SourceSpan.EndOffset);
            testCase.verifyEqual(first.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(second.getProperty("Value").LiteralValue, 10);
        end

        function failedTentativeBatchKeepsTheEstablishedLaterSlotSearch(testCase)
            % failedTentativeBatchKeepsTheEstablishedLaterSlotSearch Preserve legal setter clamping and fallback.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uislider(app.UIFigure);", "app.First.Value = 20;", ...
                "app.Second = uieditfield(app.UIFigure,'numeric');"]);
            document.getComponentByName("First").setProperty("Limits", [50 100]);
            document.getComponentByName("Second").setProperty("Value", 3);
            [source, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            first = parsed.getComponentByName("First");
            testCase.verifyGreaterThan(first.getSettings("Limits").SourceSpan.StartOffset, ...
                first.getSettings("Value").SourceSpan.EndOffset);
            states = parsed.getEffectivePropertyStates(testCase.Registry, first.Id);
            value = states(arrayfun(@(state) state.Definition.Path == "Value", states)).Resolution;
            testCase.verifyEqual(value.EffectiveValue, 50);
            testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("Value").LiteralValue, 3);
        end

        function unsafeOwnerCannotBeHiddenByAnotherOwner(testCase)
            % unsafeOwnerCannotBeHiddenByAnotherOwner Keep initialization boundaries effective for aggregated edits.
            document = testCase.fixture(["First", "Second"], ...
                ["app.First = uidropdown(app.UIFigure);", "observed = app.First.Value;", ...
                "app.First.Items = [""A"" ""B""];", "app.First.ItemsData = [10 20];", ...
                "app.Second = uieditfield(app.UIFigure,'numeric');"]);
            original = document.OriginalText;
            document.getComponentByName("First").setProperty("Value", 20);
            document.getComponentByName("Second").setProperty("Value", 3);
            [~, diagnostics] = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(document.OriginalText, original);
            testCase.verifyEmpty(document.History);
        end

        function undoAndRedoRebuildTheCorrectOwnerSet(testCase)
            % undoAndRedoRebuildTheCorrectOwnerSet Never reuse a batch from a later history state.
            document = testCase.numericFixture(2);
            first = document.getComponentByName("Field1");
            second = document.getComponentByName("Field2");
            document.setProperty(first.Id, "Value", 3, testCase.Registry);
            document.setProperty(second.Id, "Value", 4, testCase.Registry);
            generator = macd.source.RoundTripGenerator(testCase.Registry);
            both = generator.generate(document);
            document.undo();
            one = generator.generate(document);
            testCase.verifySubstring(one, "app.Field1.Value = 3;");
            testCase.verifyFalse(contains(one, "app.Field2.Value ="));
            document.redo();
            testCase.verifyEqual(generator.generate(document), both);
            testCase.verifyEqual(document.HistoryIndex, 2);
        end
    end

    methods (Access = private)
        function document = numericFixture(testCase, count)
            % numericFixture Create controls without explicit Value settings for owner-scaling coverage.
            arguments (Input)
                testCase (1, 1) PropertyInsertionBatchTest
                count (1, 1) double
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end
            names = "Field" + (1:count);
            initialization = "app." + names + " = uieditfield(app.UIFigure,'numeric');";
            document = testCase.fixture(names, initialization);
        end

        function document = fixture(testCase, names, initialization)
            % fixture Parse owned source while preserving original lines and constructor grouping.
            arguments (Input)
                testCase (1, 1) PropertyInsertionBatchTest
                names (1, :) string
                initialization (1, :) string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end
            source = strjoin(["classdef BatchInsertionFixture < handle", ...
                "properties", "UIFigure matlab.ui.Figure", names, "end", "methods", ...
                "function app = BatchInsertionFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                initialization, "end", "end", "end"], sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
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
