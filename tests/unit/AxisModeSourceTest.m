classdef (TestTags = {'fast', 'parser', 'catalog', 'model', 'generation'}) AxisModeSourceTest < matlab.unittest.TestCase
    % AxisModeSourceTest Preserve mode effects through source editing, copying, and saving.
    %   Owned UIAxes fixtures retain original argument order and explicit input
    %   values even when the audited effective value is runtime-computed.

    methods (Test)
        function pendingModeIsAddedAfterExistingConstructorValue(testCase)
            % pendingModeIsAddedAfterExistingConstructorValue Keep the constructor syntax while preserving a requested final auto mode.
            for factory = ["uiaxes", "axes"]
                for syntax = ["equals", "quoted"]
                    if syntax == "equals"
                        creation = "app.Control = " + factory + "(app.UIFigure, Units='pixels', Position=[10 20 200 100], XTick=[0 1]);";
                    else
                        creation = "app.Control = " + factory + "(app.UIFigure, 'Units', 'pixels', 'Position', [10 20 200 100], 'XTick', [0 1]);";
                    end
                    [document, registry, control] = testCase.fixture(creation, factory);
                    original = control.settingSnapshot();
                    document.setProperty(control.Id, "XTickMode", "auto", registry);
                    source = macd.source.RoundTripGenerator(registry).generate(document);
                    saved = macd.source.AppSourceParser.parseText(source, registry);
                    other = saved.getComponentByName("Control");
                    setting = other.getSettings("XTickMode");
                    testCase.verifyNumElements(setting, 1);
                    testCase.verifyEqual(setting.Method, "nameValue");
                    testCase.verifyGreaterThan(setting.ValueSpan.StartOffset, other.getSettings("XTick").ValueSpan.StartOffset);
                    states = saved.getEffectivePropertyStates(registry, other.Id);
                    testCase.verifyEqual(testCase.state(states, "XTickMode").EffectiveValue, "auto");
                    testCase.verifyFalse(testCase.state(states, "XTick").IsKnown);
                    after = control.settingSnapshot();
                    testCase.verifyEqual(SourceAssertions.retained(after, original), SourceAssertions.semantics(original));
                    testCase.verifyNumElements(after, numel(original) + 1);
                    document.undo();
                    testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
                    document.redo();
                    testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
                end
            end
        end

        function assignmentModePreservesInputAndSavedPositions(testCase)
            % assignmentModePreservesInputAndSavedPositions Save a new assignment without inventing computed tick values.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "app.Control.XTick = [0 1];"]);
            original = document.OriginalText;
            document.setProperty(control.Id, "XTickMode", "auto", registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, "AxisModeFixture.m", registry);
            document.confirmSavedSource(checkpoint, registry);
            record = checkpoint.Snapshot.Records(string({checkpoint.Snapshot.Records.Name}) == "Control");
            tick = record.Settings(string({record.Settings.Path}) == "XTick");
            mode = record.Settings(string({record.Settings.Path}) == "XTickMode");
            testCase.verifyEqual(tick.Value, [0 1]);
            testCase.verifyEqual(mode.Location.Method, "assignment");
            testCase.verifyGreaterThan(mode.Location.Sequence, tick.Location.Sequence);
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEqual(document.OriginalText, original);
        end

        function originalModeBeforeValueCannotBeMovedToHideAnOverride(testCase)
            % originalModeBeforeValueCannotBeMovedToHideAnOverride Reject an unachievable replacement without adding shadow assignments.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, XTickMode='manual', XTick=[0 1]);");
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(testCase.state(states, "XTickMode").EffectiveValue, "manual");
            testCase.verifyError(@() document.setProperty(control.Id, "XTickMode", "auto", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        function automaticModeCopiesRetainedInputsWithFreshOwnership(testCase)
            % automaticModeCopiesRetainedInputsWithFreshOwnership Preserve explicit inputs and auto intent without claiming computed equality.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100], XTick=[0 1], XTickMode='auto');");
            snapshot = document.copySubtree(control.Id, registry);
            copy = document.pasteSubtree(snapshot, document.RootComponentId, registry);
            testCase.verifyEqual(copy.getProperty("XTick").LiteralValue, [0 1]);
            testCase.verifyEqual(copy.getProperty("XTickMode").LiteralValue, 'auto');
            testCase.verifyFalse(any(ismember(string({copy.Settings.Id}), string({control.Settings.Id}))));
            states = document.getEffectivePropertyStates(registry, copy.Id);
            testCase.verifyFalse(testCase.state(states, "XTick").IsKnown);
            testCase.verifyEqual(string(testCase.state(states, "XTickMode").EffectiveValue), "auto");
            testCase.verifyEqual(control.getSettings("XTick").LiteralValue, [0 1]);
        end

        function insertedWidthFollowsAnExistingManualHoldPoint(testCase)
            % insertedWidthFollowsAnExistingManualHoldPoint Keep a previously held default minor width during assignment insertion.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", ...
                "app.Control.MinorGridLineWidthMode = 'manual'; % hold default"]);
            document.setProperty(control.Id, "GridLineWidth", 4, registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            other = reopened.getComponentByName("Control");
            states = reopened.getEffectivePropertyStates(registry, other.Id);
            testCase.verifyEqual(testCase.state(states, "GridLineWidth").EffectiveValue, 4);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 0.5);
            testCase.verifyGreaterThan(other.getSettings("GridLineWidth").Sequence, ...
                other.getSettings("MinorGridLineWidthMode").Sequence);
            testCase.verifySubstring(source, "'manual'; % hold default");
        end

        function constructorInsertionPreservesAnExistingManualHoldPoint(testCase)
            % constructorInsertionPreservesAnExistingManualHoldPoint Insert verified name-value widths after a protected manual mode.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, MinorGridLineWidthMode='manual', Units='pixels', Position=[10 20 200 100]);");
            document.setProperty(control.Id, "GridLineWidth", 4, registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            other = reopened.getComponentByName("Control");
            setting = other.getSettings("GridLineWidth");
            testCase.verifyEqual(setting.Method, "nameValue");
            testCase.verifyGreaterThan(setting.ValueSpan.StartOffset, other.getSettings("MinorGridLineWidthMode").ValueSpan.StartOffset);
            states = reopened.getEffectivePropertyStates(registry, other.Id);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 0.5);
        end

        function implicitWidthsRemainSeparateThroughEditCopyAndSave(testCase)
            % implicitWidthsRemainSeparateThroughEditCopyAndSave Update the bound upstream token while retaining earlier receiver inputs.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100]);", ...
                "app.Control.LineWidth = 1;", "app.Control.GridLineWidth = 4;", ...
                "app.Control.MinorGridLineWidth = 3;", "app.Control.MinorGridLineWidthMode = 'auto';"]);
            original = control.settingSnapshot();
            document.setProperty(control.Id, "GridLineWidth", 6, registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source, "app.Control.MinorGridLineWidth = 3;");
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 6);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, "AxisModeFixture.m", registry);
            document.confirmSavedSource(checkpoint, registry);
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), document.RootComponentId, registry);
            testCase.verifyEqual(copy.getProperty("MinorGridLineWidth").LiteralValue, 6);
            testCase.verifyEqual(string({control.Settings.Id}), arrayfun(@(record) record.Location.Id, original));
            testCase.verifyEqual(control.getSettings("GridLineWidth").LiteralValue, 6);
            testCase.verifyEqual(control.getSettings("MinorGridLineWidth").LiteralValue, 3);
            document.undo();
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
        end

        function copyPreservesDefaultAutoFollowersAndConstructorHolds(testCase)
            % copyPreservesDefaultAutoFollowersAndConstructorHolds Avoid setters that would silently change a copied automatic mode.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100], LineWidth=2);");
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), document.RootComponentId, registry);
            testCase.verifyEmpty(copy.getProperty("GridLineWidth"));
            testCase.verifyEmpty(copy.getProperty("MinorGridLineWidth"));
            states = document.getEffectivePropertyStates(registry, copy.Id);
            testCase.verifyEqual(testCase.state(states, "GridLineWidth").EffectiveValue, 2);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 2);
            testCase.verifyEqual(string(testCase.state(states, "GridLineWidthMode").EffectiveValue), "auto");
            testCase.verifyEqual(string(testCase.state(states, "MinorGridLineWidthMode").EffectiveValue), "auto");
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100], GridLineWidth=4, MinorGridLineWidthMode='manual');");
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), document.RootComponentId, registry);
            testCase.verifyEqual(copy.getProperty("MinorGridLineWidth").LiteralValue, 0.5);
            states = document.getEffectivePropertyStates(registry, copy.Id);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 0.5);
            testCase.verifyEqual(string(testCase.state(states, "MinorGridLineWidthMode").EffectiveValue), "manual");
        end

        function storedColorCanBeEditedUnderAFinalAutomaticRenderingMode(testCase)
            % storedColorCanBeEditedUnderAFinalAutomaticRenderingMode Keep getter data known without claiming a rendered grid color.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, GridColor=[0.3 0.5 0.7], GridColorMode='auto');");
            document.setProperty(control.Id, "GridColor", [0.6 0.2 0.1], registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            other = reopened.getComponentByName("Control");
            states = reopened.getEffectivePropertyStates(registry, other.Id);
            testCase.verifyEqual(testCase.state(states, "GridColor").EffectiveValue, [0.6 0.2 0.1]);
            testCase.verifyEqual(string(testCase.state(states, "GridColorMode").EffectiveValue), "auto");
            testCase.verifyNumElements(other.getSettings("GridColor"), 1);
            testCase.verifyEqual(other.getSettings("GridColor").Method, "nameValue");
        end

        function laterAutomaticModePreventsPretendedLiteralEdits(testCase)
            % laterAutomaticModePreventsPretendedLiteralEdits Keep the original target when a later auto mode makes the requested value uncertain.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "app.Control.XTick = [0 1];", "app.Control.XTickMode = 'auto';"]);
            before = control.settingSnapshot();
            testCase.verifyError(@() document.setProperty(control.Id, "XTick", [0.2 0.8], registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(control.settingSnapshot(), before);
            testCase.verifyEqual(control.getProperty("XTick").LiteralValue, [0 1]);
            testCase.verifyEqual(document.HistoryIndex, 0);
        end
    end

    methods (Static, Access = private)
        function [document, registry, control] = fixture(body, factory)
            % fixture Build a complete owned initializer without executing its source.
            arguments (Input)
                body (1, :) string
                factory (1, 1) string = "uiaxes"
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                control (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            definition = registry.get(factory);
            source = strjoin(["classdef AxisModeFixture < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Control " + definition.DeclaredType, "end", "methods", ...
                "function app = AxisModeFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                body, "end", "end", "end"], sprintf('\r\n'));
            document = macd.source.AppSourceParser.parseText(source, registry);
            control = document.getComponentByName("Control");
        end

        function value = state(states, path)
            % state Select one independent effective result by property path.
            arguments (Input)
                states (1, :) struct
                path (1, 1) string
            end
            arguments (Output)
                value (1, 1) macd.model.PropertyState
            end
            value = states(arrayfun(@(item) item.Definition.Path == path, states)).Resolution;
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
