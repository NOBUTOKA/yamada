classdef (TestTags = {'fast', 'model', 'parser', 'generation', 'lifecycle'}) ButtonSelectionPolicyTest < matlab.unittest.TestCase
    % ButtonSelectionPolicyTest Verify group-wide state, source ordering, and atomic edits.
    %   Fixtures are parsed as data; native contracts live in the separate UI test.

    methods (Test)
        function firstCreatedChildIsSelectedWithoutExplicitValue(testCase)
            % firstCreatedChildIsSelectedWithoutExplicitValue Use creation order instead of Children order.
            [document, registry] = fixture("");
            testCase.verifyEqual(values(document, registry), [1 0]);
        end

        function laterSiblingSettingOverridesAnEarlierExplicitValue(testCase)
            % laterSiblingSettingOverridesAnEarlierExplicitValue Keep the original source occurrence intact.
            [document, registry] = fixture(["app.First.Value = 1;"; "app.Second.Value = 1;"]);
            testCase.verifyEqual(values(document, registry), [0 1]);
            first = document.getComponentByName("First");
            testCase.verifyEqual(first.getProperty("Value").LiteralValue, 1);
            testCase.verifyEqual(numel(first.getSettings("Value")), 1);
            testCase.verifyError(@() document.setProperty(first.Id, "Value", 1, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyFalse(document.IsDirty);
        end

        function zeroSelectsTheOtherChildByCreationOrder(testCase)
            % zeroSelectsTheOtherChildByCreationOrder Model the documented zero-value fallback.
            [document, registry] = fixture("app.First.Value = 0;");
            testCase.verifyEqual(values(document, registry), [0 1]);
        end

        function ownedSelectedObjectReferenceDeterminesChildValues(testCase)
            % ownedSelectedObjectReferenceDeterminesChildValues Resolve a simple reference without evaluating it.
            [document, registry] = fixture("app.Group.SelectedObject = app.Second;");
            testCase.verifyEqual(values(document, registry), [0 1]);
            group = document.getComponentByName("Group");
            testCase.verifyEqual(group.getProperty("SelectedObject").ValueKind, "expression");
        end

        function unresolvedReferenceInvalidatesChildrenUntilDefiniteSelection(testCase)
            % unresolvedReferenceInvalidatesChildrenUntilDefiniteSelection Never fall back to stale literals.
            [document, registry] = fixture("app.Group.SelectedObject = chooseButton();");
            first = document.getComponentByName("First");
            states = document.getEffectivePropertyStates(registry, first.Id);
            testCase.verifyFalse(states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution.IsKnown);
            [document, registry] = fixture(["app.Group.SelectedObject = chooseButton();"; "app.First.Value = 1;"]);
            testCase.verifyEqual(values(document, registry), [1 0]);
        end

        function pendingSelectionUsesTheWholeEmittedCandidate(testCase)
            % pendingSelectionUsesTheWholeEmittedCandidate Share placement with generation and saved checkpoints.
            [document, registry] = fixture("");
            second = document.getComponentByName("Second");
            document.setProperty(second.Id, "Value", 1, registry);
            testCase.verifyEqual(values(document, registry), [0 1]);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, "SelectionApp.m", registry);
            testCase.verifyNotEmpty(checkpoint);
            document.undo();
            testCase.verifyEqual(values(document, registry), [1 0]);
            document.redo();
            testCase.verifyEqual(values(document, registry), [0 1]);
        end

        function newZeroIsPlacedAfterAnotherSiblingExists(testCase)
            % newZeroIsPlacedAfterAnotherSiblingExists Reject invalid early slots and use a proven later slot.
            [document, registry] = fixture("");
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 0, registry);
            testCase.verifyEqual(values(document, registry), [0 1]);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyLessThan(strfind(source, "app.Second = uiradiobutton"), ...
                strfind(source, "app.First.Value = 0;"));
        end

        function copiesEffectiveSelectionAfterAllSiblingCreations(testCase)
            % copiesEffectiveSelectionAfterAllSiblingCreations Freeze implicit values and avoid a sole-child zero assignment.
            [~, registry, source] = fixture("app.Second.Value = 1;");
            source = replace(source, "uibuttongroup(app.UIFigure)", "uibuttongroup(app.UIFigure, Position=[10 20 200 120])");
            document = macd.source.AppSourceParser.parseText(source, registry);
            group = document.getComponentByName("Group");
            snapshot = document.copySubtree(group.Id, registry);
            pasted = document.pasteSubtree(snapshot, document.RootComponentId, registry);
            children = document.Components(string({document.Components.ParentId}) == pasted.Id);
            first = children(1);
            second = children(2);
            states = document.getEffectivePropertyStates(registry, first.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution.EffectiveValue, 0);
            states = document.getEffectivePropertyStates(registry, second.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution.EffectiveValue, 1);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyLessThan(strfind(source, "app." + second.Name + " = uiradiobutton"), ...
                strfind(source, "app." + first.Name + ".Value = 0;"));
        end

        function generatedLegacyConstructorValueParticipates(testCase)
            % generatedLegacyConstructorValueParticipates Replay raw constructor pairs before final assignments.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("LegacySelection", registry);
            group = document.insertComponent(registry, "uibuttongroup", document.RootComponentId);
            document.insertComponent(registry, "uiradiobutton", group.Id);
            second = document.insertComponent(registry, "uiradiobutton", group.Id);
            second.CreationArguments = {"Value", 1};
            states = document.getEffectivePropertyStates(registry, second.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution.EffectiveValue, 1);
            source = macd.source.NewAppGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            copied = parsed.getComponentByName(second.Name);
            states = parsed.getEffectivePropertyStates(registry, copied.Id);
            testCase.verifyEqual(states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution.EffectiveValue, 1);
        end

        function toggleChildrenParticipateInTheSameSelection(testCase)
            % toggleChildrenParticipateInTheSameSelection Share the finite group contract across button types.
            [~, registry, source] = fixture("app.Second.Value = 1;");
            source = replace(source, "uiradiobutton", "uitogglebutton");
            source = replace(source, "matlab.ui.control.RadioButton", "matlab.ui.control.ToggleButton");
            document = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(values(document, registry), [0 1]);
        end
    end
end

function [document, registry, source] = fixture(tail)
% fixture Build an owned group with two children and optional final source writes.
arguments (Input)
    tail string
end
arguments (Output)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
    source (1, 1) string
end
registry = macd.model.ComponentRegistry.createDefault();
source = strjoin(["classdef SelectionApp < matlab.apps.AppBase"; "properties"; ...
    "UIFigure matlab.ui.Figure"; "Group matlab.ui.container.ButtonGroup"; ...
    "First matlab.ui.control.RadioButton"; "Second matlab.ui.control.RadioButton"; "end"; ...
    "methods"; "function app = SelectionApp"; "createComponents(app);"; "end"; ...
    "function createComponents(app)"; "app.UIFigure = uifigure(Visible='off');"; ...
    "app.Group = uibuttongroup(app.UIFigure);"; "app.First = uiradiobutton(app.Group);"; ...
    "app.Second = uiradiobutton(app.Group);"; reshape(tail, [], 1); "end"; "end"; "end"], newline) + newline;
document = macd.source.AppSourceParser.parseText(source, registry);
end

function result = values(document, registry)
% values Return known values in fixture declaration order rather than native child order.
arguments (Input)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
arguments (Output)
    result (1, 2) double
end
result = nan(1, 2);
names = ["First", "Second"];
for index = 1:2
    component = document.getComponentByName(names(index));
    states = document.getEffectivePropertyStates(registry, component.Id);
    state = states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution;
    if state.IsKnown, result(index) = state.EffectiveValue; end
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
