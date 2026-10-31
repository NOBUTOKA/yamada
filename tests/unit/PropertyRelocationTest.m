classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) PropertyRelocationTest < matlab.unittest.TestCase
    % PropertyRelocationTest Preserve source setting histories during parsed subtree moves.
    %   Fixtures are owned source text. Parsing and candidate validation never
    %   execute their constructor expressions or callbacks.

    methods (Test)
        function mixedHistoryAndBoundTokenSurviveMove(testCase)
            % mixedHistoryAndBoundTokenSurviveMove Keep constructor and past assignments rather than regenerating projections.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20], Value=10);", ...
                "app.Control.Value = 10;", "app.Control.Value  =  20;"]);
            document.setProperty(component.Id, "Value", 10, registry);
            before = macd.source.RoundTripGenerator(registry).generate(document);
            ids = string({component.Settings.Id});
            document.reparentSubtree(component.Id, target.Id, registry, [], [], [10 20 100 22]);
            source = document.GeneratedText;
            testCase.verifySubstring(source, "uidropdown(app.Right, Items=[""A"" ""B""], ItemsData=[10 20], Value=10)");
            testCase.verifySubstring(source, "app.Control.Value  =  10;");
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            history = reopened.getComponentByName("Control").getSettings("Value");
            testCase.verifyNumElements(history, 3);
            testCase.verifyEqual(string({history.Method}), ["nameValue" "assignment" "assignment"]);
            testCase.verifyEqual([history.LiteralValue], [10 10 10]);
            original = component.Settings(string({component.Settings.Method}) ~= "generated");
            testCase.verifyEqual(string({original(ismember(string({original.Id}), ids)).Id}), ids);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), before);
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
        end

        function existingConstructorSettingCanBeReeditedAfterMove(testCase)
            % existingConstructorSettingCanBeReeditedAfterMove Keep binding to the original token across move and edit history.
            [document, registry, component, target] = testCase.fixture( ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20], Value=10);");
            original = document.OriginalText;
            settingId = component.getSettings("Value").Id;
            document.reparentSubtree(component.Id, target.Id, registry, [], [], [10 20 100 22]);
            moved = document.GeneratedText;
            document.setProperty(component.Id, "Value", 20, registry);
            edited = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(edited, "Value=20");
            testCase.verifyFalse(contains(edited, "app.Control.Value ="));
            testCase.verifyEqual(component.getSettings("Value").Id, settingId);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), moved);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), original);
            document.redo();
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), edited);
        end

        function repeatedInitializerCannotBeRelocated(testCase)
            % repeatedInitializerCannotBeRelocated Reject repeated source ownership without changing hierarchy or history.
            [original, registry] = testCase.fixture("app.Control = uidropdown(app.Left, Position=[10 20 100 22]);");
            source = replace(original.OriginalText, "createComponents(app);", ...
                "createComponents(app);" + sprintf("\r\n") + "createComponents(app);");
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Control");
            before = component.settingSnapshot();
            parent = component.ParentId;
            snapshot = macd.model.SubtreeSnapshot(document, component.Id);
            document.PendingEdits{end + 1} = struct("Kind", "reparent-subtree", "OriginalRecords", snapshot.Records);
            testCase.verifyError(@() macd.source.SubtreeReparentSourceEdits.build(document, registry), ...
                "macd:SubtreeReparentSourceEdits:UnsafeSource");
            testCase.verifyEqual(component.ParentId, parent);
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, 0);
        end

        function pendingSelectionUsesMovedDomainAndSharedState(testCase)
            % pendingSelectionUsesMovedDomainAndSharedState Place a pending Value after the relocated ItemsData write.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left);", "app.Control.Items = [""A"" ""B""];", ...
                "app.Control.ItemsData = [10 20];"]);
            document.setProperty(component.Id, "Value", 20, registry);
            pendingId = component.getSettings("Value").Id;
            document.reparentSubtree(component.Id, target.Id, registry, [], [], [10 20 100 22]);
            source = document.GeneratedText;
            testCase.verifyGreaterThan(strfind(source, "app.Control.Value = 20;"), strfind(source, "app.Control.ItemsData = [10 20];"));
            states = document.getEffectivePropertyStates(registry, component.Id);
            value = states(arrayfun(@(state) state.Definition.Path == "Value", states)).Resolution;
            testCase.verifyEqual(value.EffectiveValue, 20);
            testCase.verifyEqual(value.LastSettingId, pendingId);
            testCase.verifyEqual(value.ExplicitKind, "literal");
            testCase.verifyNumElements(strfind(source, "app.Control.Value = 20;"), 1);
        end

        function pendingConstructorSelectionStaysInOriginalStyle(testCase)
            % pendingConstructorSelectionStaysInOriginalStyle Avoid duplicating constructor settings as assignments.
            [document, registry, component, target] = testCase.fixture( ...
                "app.Control = uidropdown(app.Left, 'Items', {'A','B'}, 'ItemsData', [10 20]);");
            document.setProperty(component.Id, "Value", 20, registry);
            document.reparentSubtree(component.Id, target.Id, registry, [], [], [10 20 100 22]);
            source = document.GeneratedText;
            testCase.verifySubstring(source, "'Value', 20");
            testCase.verifyFalse(contains(source, "app.Control.Items ="));
            testCase.verifyFalse(contains(source, "app.Control.Value ="));
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(reopened.getComponentByName("Control").getSettings("Value").Method, "nameValue");
        end

        function pendingLimitsRepairIntermediateValueBeforeMove(testCase)
            % pendingLimitsRepairIntermediateValueBeforeMove Reuse insertion proof rather than appending a domain repair.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 150;"]);
            document.setProperty(component.Id, "Limits", [0 200], registry);
            document.reparentSubtree(component.Id, target.Id, registry, [], [], [10 20 100 3]);
            source = document.GeneratedText;
            testCase.verifyLessThan(strfind(source, "app.Control.Limits = [0 200];"), strfind(source, "app.Control.Value = 150;"));
            states = document.getEffectivePropertyStates(registry, component.Id);
            value = states(arrayfun(@(state) state.Definition.Path == "Value", states)).Resolution;
            testCase.verifyEqual(value.EffectiveValue, 150);
        end

        function gridMoveRemovesConstructorPositionAndKeepsTrivia(testCase)
            % gridMoveRemovesConstructorPositionAndKeepsTrivia Remove obsolete argument code while retaining continuation comments.
            [document, registry, component] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, ... % creation", ...
                "    Position=[10 20 100 22], ... % old position", ...
                "    Tooltip='Hint');"]);
            grid = document.getComponentByName("Grid");
            document.reparentSubtree(component.Id, grid.Id, registry);
            source = document.GeneratedText;
            testCase.verifyFalse(contains(source, "Position=[10 20 100 22]"));
            testCase.verifySubstring(source, "% creation");
            testCase.verifySubstring(source, "% old position");
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            selected = reopened.getComponentByName("Control");
            testCase.verifyEmpty(selected.getProperty("Position"));
            testCase.verifyEqual(selected.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(selected.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyEqual(selected.getProperty("Tooltip").LiteralValue, 'Hint');
        end

        function interleavedHistoriesKeepOriginalStatementOrder(testCase)
            % interleavedHistoriesKeepOriginalStatementOrder Do not group a parent's children into separate property blocks.
            [original, registry] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""]);", ...
                "app.Other = uidropdown(app.Left, Items=[""X"" ""Y""]);", ...
                "app.Other.Value = ""Y"";", "app.Control.Value = ""B""; % last selection"]);
            source = replace(original.OriginalText, "Grid matlab.ui.container.GridLayout", ...
                "Other" + sprintf("\r\n") + "Grid matlab.ui.container.GridLayout");
            document = macd.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName("Left");
            right = document.getComponentByName("Right");
            document.reparentSubtree(left.Id, right.Id, registry, [], [], [10 20 200 200]);
            moved = document.GeneratedText;
            testCase.verifyLessThan(strfind(moved, "app.Other.Value = ""Y"";"), strfind(moved, "app.Control.Value = ""B"";"));
            testCase.verifySubstring(moved, "app.Control.Value = ""B""; % last selection");
            testCase.verifyNumElements(strfind(moved, "% last selection"), 1);
        end

        function rootVisibilityRemainsAfterRelocatedInitialization(testCase)
            % rootVisibilityRemainsAfterRelocatedInitialization Keep the existing final figure visibility stage last.
            [original, registry] = testCase.fixture("app.Control = uidropdown(app.Left, Position=[10 20 100 22]);");
            source = replace(original.OriginalText, "app.Grid = uigridlayout(app.Right);", ...
                "app.Grid = uigridlayout(app.Right);" + sprintf("\r\n") + "app.UIFigure.Visible = 'on';");
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Control");
            right = document.getComponentByName("Right");
            document.reparentSubtree(component.Id, right.Id, registry);
            moved = document.GeneratedText;
            testCase.verifyGreaterThan(strfind(moved, "app.UIFigure.Visible = 'on';"), strfind(moved, "app.Control = uidropdown(app.Right"));
        end

        function opaqueConstructorTokensArePreservedWithoutExecution(testCase)
            % opaqueConstructorTokensArePreservedWithoutExecution Keep expressions rather than emitting only literal projections.
            [document, registry, component, target] = testCase.fixture( ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Tooltip=""Opaque"" + ""Hint"");");
            document.reparentSubtree(component.Id, target.Id, registry, [], [], [10 20 100 22]);
            source = document.GeneratedText;
            testCase.verifySubstring(source, "Tooltip=""Opaque"" + ""Hint""");
            testCase.verifyFalse(contains(source, "app.Control.Tooltip ="));
            testCase.verifyFalse(contains(source, "app.Control.Items ="));
        end
    end

    methods (Static, Access = private)
        function [document, registry, component, target] = fixture(body)
            % fixture Build a direct initializer with a later destination and a grid child.
            arguments (Input)
                body (1, :) string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                component (1, 1) macd.model.ComponentRecord
                target (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            source = strjoin(["classdef RelocationApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Left matlab.ui.container.Panel", "Right matlab.ui.container.Panel", ...
                "Grid matlab.ui.container.GridLayout", "Control", "end", "methods", ...
                "function app = RelocationApp", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Left = uipanel(app.UIFigure);", body, "app.Right = uipanel(app.UIFigure);", ...
                "app.Grid = uigridlayout(app.Right);", "end", "end", "end"], sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Control");
            target = document.getComponentByName("Right");
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
