classdef (TestTags = {'fast', 'model', 'generation', 'parser'}) PositionGeometryTest < matlab.unittest.TestCase
    % PositionGeometryTest Verify shared constraints and source-preserving Position edits.
    %   Owned source is parsed as data; native agreement is checked separately.

    methods (Test)
        function linkedFieldsAndFixedDimensionsUseOneConstraint(testCase)
            % linkedFieldsAndFixedDimensionsUseOneConstraint Preserve the edited dimension and update its partner.
            spec = macd.model.PositionGeometry.constraint("switchPosition", "vertical", true);
            value = macd.model.PositionGeometry.edit([10 20 20 45], 3, 40, spec);
            testCase.verifyEqual(value, [10 20 40 90]);
            testCase.verifyEqual(macd.model.PositionGeometry.edit(value, 4, 135, spec), [10 20 60 135]);
            testCase.verifyEqual(macd.model.PositionGeometry.edit(value, 1, 30, spec), [30 20 40 90]);
            spec = macd.model.PositionGeometry.constraint("sliderPosition", "vertical", true);
            testCase.verifyEqual(spec.FixedIndex, 3);
            testCase.verifyEqual(macd.model.PositionGeometry.edit([10 20 3 100], 3, 9, spec), [10 20 3 100]);
            testCase.verifyEqual(macd.model.PositionGeometry.edit([10 20 3 100], 4, 120, spec), [10 20 3 120]);
        end

        function resizeAnchorsAndFractionalRatiosRemainConsistent(testCase)
            % resizeAnchorsAndFractionalRatiosRemainConsistent Keep opposite edges without integer size rounding.
            spec = macd.model.PositionGeometry.constraint("semicircularPosition", "north", true);
            before = [10 20 120 65];
            value = macd.model.PositionGeometry.resize([0 20 130 65], before, "w", spec);
            testCase.verifyEqual(value(1) + value(3), 130, "AbsTol", 1e-12);
            testCase.verifyEqual(value(3) / value(4), 120 / 65, "AbsTol", 1e-12);
            spec = macd.model.PositionGeometry.constraint("sliderPosition", "horizontal", true);
            testCase.verifyEqual(macd.model.PositionGeometry.resize([10 5 200 50], ...
                [10 20 100 3], "se", spec), [10 20 200 3]);
            testCase.verifyFalse(macd.model.PositionGeometry.valid([1 2 -1 4]));
            testCase.verifyFalse(macd.model.PositionGeometry.constraint("switchPosition").Known);
        end

        function editingCopyAndSavePreservePositionHistory(testCase)
            % editingCopyAndSavePreservePositionHistory Keep original source ownership and one undo unit.
            registry = macd.model.ComponentRegistry.createDefault();
            for id = ["uiswitch-rocker", "uiswitch-slider", "uiswitch-toggle", "uigauge-semicircular"]
                definition = registry.getById(id);
                source = PositionGeometryTest.source(definition);
                document = macd.source.AppSourceParser.parseText(source, registry);
                component = document.getComponentByName("Control");
                states = document.getEffectivePropertyStates(registry, component.Id);
                resolution = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
                testCase.verifyTrue(resolution.IsEditable, id);
                testCase.verifyTrue(resolution.IsKnown, id);
                before = macd.source.RoundTripGenerator(registry).generate(document);
                original = component.settingSnapshot();
                orientation = "horizontal";
                if definition.Factory == "uigauge", orientation = "north"; end
                spec = macd.model.PositionGeometry.constraint(definition.getProperty("Position").Application.EffectPolicy, orientation, true);
                requested = macd.model.PositionGeometry.edit(resolution.EffectiveValue, 3, 90, spec);
                history = document.HistoryIndex;
                document.setProperty(component.Id, "Position", requested, registry);
                testCase.verifyEqual(document.HistoryIndex, history + 1);
                testCase.verifyEqual(numel(component.Settings), numel(original));
                snapshot = document.copySubtree(component.Id, registry);
                pasted = document.pasteSubtree(snapshot, document.RootComponentId, registry);
                testCase.verifyNotEmpty(pasted);
                document.undo();
                document.undo();
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), before);
                document.redo();
                emitted = macd.source.RoundTripGenerator(registry).generate(document);
                testCase.verifySubstring(emitted, "% keep position comment");
                checkpoint = macd.model.SavedSourceCheckpoint(document, emitted, fullfile(tempdir, "PositionFixture.m"), registry);
                testCase.verifyEqual(checkpoint.SourceText, emitted);
                requested(1) = requested(1) + 5;
                document.setProperty(component.Id, "Position", requested, registry);
                states = document.getEffectivePropertyStates(registry, component.Id);
                value = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
                testCase.verifyTrue(macd.model.PropertyStateResolver.matchesRequested(value, requested));
            end
        end
    end

    methods (Static, Access = private)
        function source = source(definition)
            % source Build an owned handle-class fixture with a writable declared control.
            arguments (Input)
                definition (1, 1) macd.model.ComponentDefinition
            end
            arguments (Output)
                source (1, 1) string
            end
            styleArgument = "";
            if ~isempty(definition.CreationArguments)
                styleArgument = ", '" + string(definition.CreationArguments{1}) + "'";
            end
            orientation = "horizontal";
            if definition.Factory == "uigauge", orientation = "north"; end
            source = strjoin(["classdef PositionFixture < handle"; "properties"; ...
                "UIFigure matlab.ui.Figure"; "Control " + definition.DeclaredType; "end"; ...
                "methods"; "function app = PositionFixture"; "createComponents(app);"; "end"; ...
                "function createComponents(app)"; "app.UIFigure = uifigure(Visible='off');"; ...
                "app.Control = " + definition.Factory + "(app.UIFigure" + styleArgument + ");"; ...
                "app.Control.Orientation = '" + orientation + "';"; ...
                "app.Control.Position = [10 20 100 70]; % keep position comment"; "end"; "end"; "end"], newline) + newline;
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
