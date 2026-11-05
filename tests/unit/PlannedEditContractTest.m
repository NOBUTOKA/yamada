classdef (TestTags = {'fast', 'model', 'generation'}) PlannedEditContractTest < matlab.unittest.TestCase
    % PlannedEditContractTest Verify source ordering and derived-state guarantees of accepted edit plans.
    %   Parent placement is established before descendants are created, and
    %   source-effect transitions update the affected state without losing history.
    properties (TestParameter)
        % Destination - Absolute or Grid placement chosen for the moved container.
        Destination = {"absolute", "grid"}
    end
    methods (Test)
        function parentPlacementPrecedesChildCreation(testCase, Destination)
            % parentPlacementPrecedesChildCreation Preserve child configuration when the new parent rectangle changes.
            [document, registry] = fixture(Destination);
            moved = document.getComponentByName("Moved"); child = document.getComponentByName("Child");
            right = document.getComponentByName("Right"); original = document.CurrentText;
            if Destination == "grid"
                document.reparentSubtree(moved.Id, right.Id, registry, [], [2 2]);
                paths = ["Layout.Row", "Layout.Column"]; expected = {2, 2};
                testCase.verifyEmpty(moved.getProperty("Position"));
            else
                document.reparentSubtree(moved.Id, right.Id, registry, [], [], [13 17 200 140]);
                paths = "Position"; expected = {[13 17 200 140]};
            end
            for index = 1:numel(paths)
                settings = moved.getSettings(paths(index)); testCase.assertNotEmpty(settings);
                testCase.verifyEqual(settings(end).LiteralValue, expected{index});
                testCase.verifyLessThan(settings(end).SourceSpan.EndOffset, child.SourceSpans.Creation.StartOffset);
            end
            testCase.verifyEqual(child.getProperty("Position").LiteralValue, [7 8 30 20]);
            changed = document.CurrentText;
            document.undo(); testCase.verifyEqual(document.CurrentText, original);
            document.redo(); testCase.verifyEqual(document.CurrentText, changed);
            reloaded = yamada.source.AppSourceParser.parseText(changed, registry);
            other = reloaded.getComponentByName("Moved");
            for index = 1:numel(paths), testCase.verifyEqual(other.getProperty(paths(index)).LiteralValue, expected{index}); end
        end

        function nativeSizeConstraintsRejectBeforeEditing(testCase, Destination)
            % nativeSizeConstraintsRejectBeforeEditing Reject a nonsquare lamp request without changing model or source.
            [document, registry] = fixture(Destination);
            source = replace(document.CurrentText, "matlab.ui.control.Button", "matlab.ui.control.Lamp");
            source = replace(source, "uibutton(app.Moved)", "uilamp(app.Moved)");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            child = document.getComponentByName("Child"); before = document.CurrentText; history = document.HistoryIndex;
            testCase.verifyError(@() document.reparentSubtree(child.Id, document.RootComponentId, registry, ...
                [1 2 40 20], [], [1 2 40 20]), "yamada:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(document.CurrentText, before); testCase.verifyEqual(document.HistoryIndex, history);
        end

        function copiedOrientationSurvivesOriginalDeletion(testCase, Destination)
            % copiedOrientationSurvivesOriginalDeletion Use captured orientation when pasting after the source owner is gone.
            [document, registry] = fixture(Destination);
            source = replace(document.CurrentText, "matlab.ui.control.Button", "matlab.ui.control.Slider");
            source = replace(source, "uibutton(app.Moved)", "uislider(app.Moved)");
            source = replace(source, "app.Moved.Position = [5 6 120 90];", "");
            source = replace(source, "app.Child.Position = [7 8 30 20];", ...
                "app.Child.Orientation = 'vertical';" + newline + "app.Child.Position = [7 8 3 100];");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            child = document.getComponentByName("Child");
            snapshot = document.copySubtree(child.Id, registry);
            document.removeSubtree(child.Id, registry);
            pasted = document.pasteSubtree(snapshot, document.RootComponentId, registry, [7 8 3 100]);
            testCase.verifyEqual(string(pasted.getProperty("Orientation").LiteralValue), "vertical");
            parsed = yamada.source.AppSourceParser.parseText(document.CurrentText, registry);
            testCase.verifyEqual(string(parsed.getComponentByName(pasted.Name).getProperty("Orientation").LiteralValue), "vertical");
        end

        function removingAnExecutionEffectRefreshesOtherOwners(testCase, Destination)
            % removingAnExecutionEffectRefreshesOtherOwners Restore known state and unknown state through deletion history.
            [document, registry] = fixture(Destination);
            source = replace(document.CurrentText, "app.Child.Position = [7 8 30 20];", ...
                "app.Child.Position = [7 8 30 20];" + newline + "app.Child.UnknownProperty = 1;");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName("Left"); child = document.getComponentByName("Child");
            states = document.getEffectivePropertyStates(registry, left.Id);
            testCase.verifyFalse(states(arrayfun(@(state) state.Definition.Path == "Position", states)).Resolution.IsKnown);
            document.removeSubtree(child.Id, registry);
            states = document.getEffectivePropertyStates(registry, left.Id);
            testCase.verifyTrue(states(arrayfun(@(state) state.Definition.Path == "Position", states)).Resolution.IsKnown);
            document.undo();
            states = document.getEffectivePropertyStates(registry, left.Id);
            testCase.verifyFalse(states(arrayfun(@(state) state.Definition.Path == "Position", states)).Resolution.IsKnown);
            document.redo();
            states = document.getEffectivePropertyStates(registry, left.Id);
            testCase.verifyTrue(states(arrayfun(@(state) state.Definition.Path == "Position", states)).Resolution.IsKnown);
        end
    end
end

function [document, registry] = fixture(destination)
% fixture Load trusted source with a final parent rectangle originally written after child initialization.
arguments (Input)
    destination (1, 1) string
end
arguments (Output)
    document (1, 1) yamada.model.DocumentModel
    registry (1, 1) yamada.model.ComponentRegistry
end
right = "app.Right = uipanel(app.UIFigure);";
if destination == "grid", right = "app.Right = uigridlayout(app.UIFigure, [2 2]);"; end
source = strjoin(["classdef PlannedHierarchyFixture < handle"; "properties"; ...
    "UIFigure matlab.ui.Figure"; "Left matlab.ui.container.Panel"; "Right"; ...
    "Moved matlab.ui.container.Panel"; "Child matlab.ui.control.Button"; "end"; "methods"; ...
    "function app = PlannedHierarchyFixture"; "createComponents(app);"; "end"; ...
    "function createComponents(app)"; "app.UIFigure = uifigure('Visible','off');"; ...
    "app.UIFigure.Position = [100 100 800 600];"; "app.Left = uipanel(app.UIFigure);"; ...
    "app.Left.Position = [1 1 350 500];"; right; "app.Moved = uipanel(app.Left);"; ...
    "app.Moved.Position = [1 2 80 70];"; "app.Child = uibutton(app.Moved);"; ...
    "app.Child.Position = [7 8 30 20];"; "app.Moved.Position = [5 6 120 90];"; ...
    "end"; "end"; "end"], string(sprintf("\r\n")));
registry = yamada.model.ComponentRegistry.createDefault();
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
