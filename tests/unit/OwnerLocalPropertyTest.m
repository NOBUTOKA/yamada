classdef (TestTags = {'fast', 'model', 'parser', 'generation'}) OwnerLocalPropertyTest < matlab.unittest.TestCase
    % OwnerLocalPropertyTest Preserve implicit setter effects, source and history for component-local policy edits.
    %   Fresh parsing provides an independent semantic oracle for each finite
    %   policy family, including effects that have no explicit source setting.
    methods (Test)
        function coupledEditsAndHistoryRetainAllEffectiveStates(testCase)
            % coupledEditsAndHistoryRetainAllEffectiveStates Match full initialization semantics for every local policy family.
            registry = macd.model.ComponentRegistry.createDefault();
            for scenario = policyScenarios()
                document = policyDocument(scenario, registry); owner = document.getComponentByName("Subject");
                before = document.CurrentText;
                document.setPropertyBatch(owner.Id, scenario.Changes, registry);
                document.validatePropertyCommit(registry);
                verifyEffectiveStates(testCase, document, registry);
                after = document.CurrentText;
                document.undo(); testCase.verifyEqual(document.CurrentText, before);
                verifyEffectiveStates(testCase, document, registry);
                document.redo(); testCase.verifyEqual(document.CurrentText, after);
                verifyEffectiveStates(testCase, document, registry);
            end
        end

        function changedFollowersRemainCurrentDuringDistinctEdits(testCase)
            % changedFollowersRemainCurrentDuringDistinctEdits Keep implicit numeric rounding and width followers across later independent edits.
            registry = macd.model.ComponentRegistry.createDefault(); scenarios = policyScenarios();
            for scenario = scenarios(ismember(string({scenarios.Name}), ["numeric", "width", "items", "color"]))
                document = policyDocument(scenario, registry); owner = document.getComponentByName("Subject");
                document.setPropertyBatch(owner.Id, scenario.Changes, registry); document.validatePropertyCommit(registry);
                other = document.getComponentByName("Unchanged");
                document.setProperty(other.Id, "Tooltip", "A different owner and longer text", registry);
                document.validatePropertyCommit(registry);
                document.setProperty(other.Id, "Text", "Another distinct setting", registry); document.validatePropertyCommit(registry);
                verifyEffectiveStates(testCase, document, registry);
                testCase.verifyEqual(document.HistoryIndex, 3);
            end
        end
    end
end

function scenarios = policyScenarios()
% policyScenarios Supply reviewed scalar, domain, text, tick, width and axes-mode edit cases.
arguments (Output)
    scenarios (1, :) struct
end
scenarios = struct("Name", {}, "Type", {}, "Body", {}, "Changes", {});
scenarios(end + 1) = struct("Name", "bounded", "Type", "matlab.ui.control.Slider", ...
    "Body", ["app.Subject = uislider(app.UIFigure);", "app.Subject.Value = 20;", "app.Subject.Limits = [50 100];"], ...
    "Changes", [struct("Path", "Value", "Value", 75), struct("Path", "Limits", "Value", [60 100])]);
scenarios(end + 1) = struct("Name", "numeric", "Type", "matlab.ui.control.NumericEditField", ...
    "Body", ["app.Subject = uieditfield(app.UIFigure,'numeric');", "app.Subject.Value = 2.4;", "app.Subject.RoundFractionalValues = 'off';"], ...
    "Changes", struct("Path", "RoundFractionalValues", "Value", "on"));
scenarios(end + 1) = struct("Name", "text", "Type", "matlab.ui.control.EditField", ...
    "Body", ["app.Subject = uieditfield(app.UIFigure);", "app.Subject.Value = 'alpha';", "app.Subject.CharacterLimits = [0 20];"], ...
    "Changes", [struct("Path", "Value", "Value", 'beta'), struct("Path", "CharacterLimits", "Value", [0 8])]);
scenarios(end + 1) = struct("Name", "items", "Type", "matlab.ui.control.DropDown", ...
    "Body", ["app.Subject = uidropdown(app.UIFigure);", "app.Subject.Items = {'A','B'};", "app.Subject.Value = 'A';"], ...
    "Changes", [struct("Path", "Items", "Value", {{'C','D'}}), struct("Path", "Value", "Value", 'D')]);
scenarios(end + 1) = struct("Name", "ticks", "Type", "matlab.ui.control.Slider", ...
    "Body", ["app.Subject = uislider(app.UIFigure);", "app.Subject.MajorTicksMode = 'auto';"], ...
    "Changes", struct("Path", "MajorTicks", "Value", [0 25 100]));
scenarios(end + 1) = struct("Name", "limits", "Type", "matlab.ui.control.UIAxes", ...
    "Body", ["app.Subject = uiaxes(app.UIFigure);", "app.Subject.XLimMode = 'auto';"], ...
    "Changes", struct("Path", "XLim", "Value", [1 20]));
scenarios(end + 1) = struct("Name", "font", "Type", "matlab.ui.control.UIAxes", ...
    "Body", ["app.Subject = uiaxes(app.UIFigure);", "app.Subject.FontSizeMode = 'auto';"], ...
    "Changes", struct("Path", "FontSize", "Value", 18));
scenarios(end + 1) = struct("Name", "color", "Type", "matlab.ui.control.UIAxes", ...
    "Body", "app.Subject = uiaxes(app.UIFigure);", "Changes", struct("Path", "XColor", "Value", [0.2 0.3 0.4]));
scenarios(end + 1) = struct("Name", "width", "Type", "matlab.ui.control.UIAxes", ...
    "Body", ["app.Subject = uiaxes(app.UIFigure);", "app.Subject.LineWidth = 0.5;"], ...
    "Changes", struct("Path", "LineWidth", "Value", 2));
end

function document = policyDocument(scenario, registry)
% policyDocument Parse one subject alongside an independent component without executing application code.
arguments (Input)
    scenario (1, 1) struct
    registry (1, 1) macd.model.ComponentRegistry
end
arguments (Output)
    document (1, 1) macd.model.DocumentModel
end
source = strjoin(["classdef OwnerLocalFixture < handle", "properties", "UIFigure matlab.ui.Figure", ...
    "Subject " + scenario.Type, "Unchanged matlab.ui.control.Label", "end", "methods", ...
    "function app = OwnerLocalFixture", "createComponents(app);", "end", "function createComponents(app)", ...
    "app.UIFigure = uifigure(Visible='off');", scenario.Body, ...
    "app.Unchanged = uilabel(app.UIFigure);", "app.Unchanged.Text = 'untouched';", "end", "end", "end"], sprintf('\r\n'));
document = macd.source.AppSourceParser.parseText(source, registry);
end

function verifyEffectiveStates(testCase, document, registry)
% verifyEffectiveStates Compare every owner's semantic projection against independently parsed current source.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
reference = macd.source.AppSourceParser.parseText(document.CurrentText, registry);
testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(reference.Diagnostics));
for component = document.Components
    fresh = reference.getComponentByName(component.Name);
    actual = document.getEffectivePropertyStates(registry, component.Id);
    expected = reference.getEffectivePropertyStates(registry, fresh.Id);
    actualDefinitions = [actual.Definition]; expectedDefinitions = [expected.Definition];
    testCase.assertEqual([actualDefinitions.Path], [expectedDefinitions.Path]);
    for index = 1:numel(actual)
        a = actual(index).Resolution; b = expected(index).Resolution;
        for field = ["IsKnown", "IsEditable", "EffectiveValue", "ExplicitKind", "ExplicitValue", "RequestedValue"]
            testCase.verifyEqual(a.(field), b.(field), component.Name + "." + a.Path + "." + field);
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
