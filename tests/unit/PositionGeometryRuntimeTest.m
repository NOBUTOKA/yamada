classdef (TestTags = {'model', 'catalog', 'preview', 'ui'}) PositionGeometryRuntimeTest < matlab.unittest.TestCase
    % PositionGeometryRuntimeTest Compare finite geometry with owned R2024a controls.
    %   These fixtures execute only test-authored factories and literal setters.

    methods (Test)
        function linearGaugePreviewKeepsWidthAndHeightIndependent(testCase)
            % linearGaugePreviewKeepsWidthAndHeightIndependent Preserve narrow, tall, and height-only Preview edits.
            registry = yamada.model.ComponentRegistry.createDefault();
            definition = registry.getById("uigauge-linear");
            testCase.verifyEqual(definition.resizeConstraintFor(definition.CreationArguments), "free");
            source = strjoin(["classdef LinearPositionFixture < handle"; "properties"; ...
                "UIFigure matlab.ui.Figure"; "Control matlab.ui.control.LinearGauge"; "end"; ...
                "methods"; "function app = LinearPositionFixture"; "createComponents(app);"; "end"; ...
                "function createComponents(app)"; "app.UIFigure = uifigure(Visible='off', AutoResizeChildren='off');"; ...
                "app.Control = uigauge(app.UIFigure, 'linear');"; "app.Control.Orientation = 'horizontal';"; ...
                "app.Control.Position = [10 20 100 70];"; "end"; "end"; "end"], newline);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Control");
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            renderer = yamada.ui.PreviewRenderer(registry);
            for orientation = ["horizontal", "vertical"]
                document.setProperty(component.Id, "Orientation", orientation, registry);
                for sizes = [100 70; 100 150; 50 150]'
                    requested = [10 20 sizes'];
                    document.setProperty(component.Id, "Position", requested, registry);
                    [handles, diagnostics] = renderer.render(document, figure);
                    testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
                    testCase.verifyEqual(handles(char(component.Id)).Position, requested);
                end
            end
        end

        function aspectPoliciesMatchEveryOrientationAndBoundary(testCase)
            % aspectPoliciesMatchEveryOrientationAndBoundary Check fractional, tall, wide, and zero rectangles.
            registry = yamada.model.ComponentRegistry.createDefault();
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            vectors = [10 20 100 70; 20 30 50 150; 10.1 20.2 0.5 2.3; 10 20 0 0; 10 20 100 0];
            for id = ["uiswitch-rocker", "uiswitch-slider", "uiswitch-toggle", "uigauge-semicircular", "uigauge-linear"]
                definition = registry.getById(id);
                orientations = ["horizontal", "vertical"];
                if definition.Id == "uigauge-semicircular", orientations = ["north", "south", "east", "west"]; end
                for orientation = orientations
                    for row = 1:size(vectors, 1)
                        target = feval(definition.Factory, figure, definition.CreationArguments{:});
                        target.Orientation = orientation;
                        target.Position = vectors(row, :);
                        state = PositionGeometryRuntimeTest.resolve(definition, ...
                            {"Orientation", orientation; "Position", vectors(row, :)}, "assignment");
                        testCase.verifyTrue(state.IsKnown, id);
                        testCase.verifyEqual(state.EffectiveValue, target.Position, "AbsTol", 1e-12, id);
                        delete(target);
                    end
                end
            end
        end

        function constructorAndSetterOrderRetainNativeSizeExchange(testCase)
            % constructorAndSetterOrderRetainNativeSizeExchange Check both orders instead of assuming canonical input.
            registry = yamada.model.ComponentRegistry.createDefault();
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            for id = ["uiswitch-rocker", "uiswitch-slider", "uiswitch-toggle", "uigauge-semicircular", ...
                    "uislider-slider", "uislider-range", "uigauge-linear"]
                definition = registry.getById(id);
                orientation = "vertical";
                if definition.Id == "uigauge-semicircular", orientation = "east"; end
                for method = ["assignment", "nameValue"]
                    for reverse = [false true]
                        writes = {"Position", [10 20 100 70]; "Orientation", orientation};
                        if reverse, writes = flipud(writes); end
                        if method == "nameValue"
                            pairs = reshape(writes', 1, []);
                            target = feval(definition.Factory, figure, definition.CreationArguments{:}, pairs{:});
                        else
                            target = feval(definition.Factory, figure, definition.CreationArguments{:});
                            for row = 1:size(writes, 1), target.(writes{row, 1}) = writes{row, 2}; end
                        end
                        state = PositionGeometryRuntimeTest.resolve(definition, writes, method);
                        testCase.verifyTrue(state.IsKnown, id + ":" + method);
                        testCase.verifyEqual(state.EffectiveValue, target.Position, "AbsTol", 1e-12, id + ":" + method);
                        delete(target);
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function state = resolve(definition, writes, method)
            % resolve Replay owned occurrences while leaving their requested literals intact.
            arguments (Input)
                definition (1, 1) yamada.model.ComponentDefinition
                writes cell
                method (1, 1) string
            end
            arguments (Output)
                state (1, 1) yamada.model.PropertyState
            end
            component = yamada.model.ComponentRecord("owned", "Owned", definition.Factory, definition.DeclaredType, "parsed");
            component.CreationArguments = definition.CreationArguments;
            for index = 1:size(writes, 1)
                span = yamada.model.SourceSpan(index * 10, index * 10 + 1);
                location = struct("Method", method, "Syntax", "dot", "Sequence", index, ...
                    "StatementId", "owned-constructor", "SourceSnapshotId", "owned", ...
                    "SourceSpan", span, "ValueSpan", span);
                if method == "nameValue", location.Syntax = "quotedPair"; end
                component.recordSetting(yamada.model.PropertySetting(writes{index, 1}, writes{index, 2}, location));
            end
            states = yamada.model.PropertyStateResolver.resolve(component, definition.Properties);
            state = states(string({states.Path}) == "Position");
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
