classdef (TestTags = {'fast', 'model', 'generation'}) PropertyEditTransactionTest < matlab.unittest.TestCase
    % PropertyEditTransactionTest Verify atomic source preflight and stable setting targets.
    %   The tests exercise requested values and history without executing the
    %   represented application or replacing its immutable source baseline.

    methods (Test)
        function laterSetterCannotSilentlyDiscardARequestedValue(testCase)
            % laterSetterCannotSilentlyDiscardARequestedValue Preserve all live state when a replacement is clamped later.
            [document, registry, component] = testCase.sliderFixture();
            before = component.settingSnapshot();
            diagnostics = document.Diagnostics;
            testCase.verifyError(@() document.setProperty(component.Id, "Value", 30, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(document.Diagnostics, diagnostics);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function rawNoOpsStillCheckTheRequestedEffectiveValue(testCase)
            % rawNoOpsStillCheckTheRequestedEffectiveValue Do not silently accept the old literal when its actual effect differs.
            [document, registry, component] = testCase.sliderFixture();
            testCase.verifyError(@() document.setProperty(component.Id, "Value", 20, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            changes = [macd.model.PropertyTransaction.singleChange("Value", 20), ...
                macd.model.PropertyTransaction.singleChange("Limits", [60 100])];
            testCase.verifyError(@() document.setPropertyBatch(component.Id, changes, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(component.getProperty("Limits").LiteralValue, [50 100]);
            testCase.verifyEqual(document.HistoryIndex, 0);
        end

        function validBatchRetainsOneHistoryUnitAndOriginalSettingIds(testCase)
            % validBatchRetainsOneHistoryUnitAndOriginalSettingIds Resolve safe replacements through Undo and Redo.
            [document, registry, component] = testCase.sliderFixture();
            original = component.getSettings("Value");
            changes = [macd.model.PropertyTransaction.singleChange("Value", 75), ...
                macd.model.PropertyTransaction.singleChange("Limits", [60 100])];
            document.setPropertyBatch(component.Id, changes, registry);
            testCase.verifyEqual(document.HistoryIndex, 1);
            states = document.getEffectivePropertyStates(registry, component.Id);
            state = states(arrayfun(@(entry) entry.Definition.Path == "Value", states)).Resolution;
            testCase.verifyEqual(state.EffectiveValue, 75);
            testCase.verifyEqual(state.ExplicitValue, 75);
            testCase.verifyEqual(state.LastSettingId, original.Id);
            document.undo();
            states = document.getEffectivePropertyStates(registry, component.Id);
            testCase.verifyEqual(states(arrayfun(@(entry) entry.Definition.Path == "Value", states)).Resolution.EffectiveValue, 50);
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEqual(component.getSettings("Value").LiteralValue, 75);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 75);
        end

        function finalRangeDoesNotHideAnInvalidIntermediateAssignment(testCase)
            % finalRangeDoesNotHideAnInvalidIntermediateAssignment Reject a value outside the range at its fixed source slot.
            [document, registry, component] = testCase.sliderFixture();
            changes = [macd.model.PropertyTransaction.singleChange("Value", 150), ...
                macd.model.PropertyTransaction.singleChange("Limits", [120 200])];
            testCase.verifyError(@() document.setPropertyBatch(component.Id, changes, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.HistoryIndex, 0);
        end

        function constructorBatchUsesItsFinalDomain(testCase)
            % constructorBatchUsesItsFinalDomain Keep constructor grouping distinct from sequential assignment checks.
            [document, registry, component] = testCase.sliderFixture( ...
                "app.Slider = uislider(app.UIFigure, Value=75, Limits=[50 100]);");
            changes = [macd.model.PropertyTransaction.singleChange("Value", 150), ...
                macd.model.PropertyTransaction.singleChange("Limits", [120 200])];
            document.setPropertyBatch(component.Id, changes, registry);
            generated = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(generated, "Value=150, Limits=[120 200]");
            testCase.verifyFalse(contains(generated, "app.Slider.Value ="));
            testCase.verifyEqual(document.HistoryIndex, 1);
        end

        function rootOnlyDocumentsCanPreflightCanvasResize(testCase)
            % rootOnlyDocumentsCanPreflightCanvasResize Handle empty child collections independent of orientation.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CanvasEdit", registry);
            document.setProperty(document.RootComponentId, "Position", [100 80 640 500], registry);
            testCase.verifyEqual(document.getComponent(document.RootComponentId).getProperty("Position").LiteralValue, ...
                [100 80 640 500]);
            testCase.verifyEqual(document.HistoryIndex, 1);
        end

        function tableColumnWidthsUseTheirOwnSchema(testCase)
            % tableColumnWidthsUseTheirOwnSchema Distinguish table widths from grid track settings.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("TableWidths", registry);
            component = document.insertComponent(registry, "uitable", document.RootComponentId);
            document.setProperty(component.Id, "Data", reshape(1:6, 2, 3));
            changes = [macd.model.PropertyTransaction.singleChange("ColumnWidth", 'fit'), ...
                macd.model.PropertyTransaction.singleChange("ColumnEditable", true), ...
                macd.model.PropertyTransaction.singleChange("ColumnSortable", true), ...
                macd.model.PropertyTransaction.singleChange("ColumnFormat", {'bank'})];
            document.setPropertyBatch(component.Id, changes, registry);
            testCase.verifyEqual(component.getProperty("ColumnWidth").LiteralValue, 'fit');
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors( ...
                macd.validation.ModelValidator.validate(document, registry)));
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            testCase.verifyError(@() document.setProperty(grid.Id, "ColumnWidth", 'fit', registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
        end

        function rejectedBatchDoesNotChangeLiveValuesHistoryOrDiagnostics(testCase)
            % rejectedBatchDoesNotChangeLiveValuesHistoryOrDiagnostics Keep candidate failures isolated.

            [document, registry, component] = testCase.fixture();
            originalDiagnostics = document.Diagnostics;
            before = component.settingSnapshot();
            changes = [macd.model.PropertyTransaction.singleChange("Text", "Changed"), ...
                macd.model.PropertyTransaction.singleChange("Position", [1 2 3])];
            testCase.verifyError(@() document.setPropertyBatch(component.Id, changes, registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(component.getProperty("Text").LiteralValue, "First");
            testCase.verifyEqual(component.getProperty("Position").LiteralValue, [10 20 100 30]);
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEqual(document.Diagnostics, originalDiagnostics);
            testCase.verifyEqual(document.GeneratedText, "");
        end

        function acceptedEditKeepsOriginalOccurrenceAndIgnoresNoOpRequests(testCase)
            % acceptedEditKeepsOriginalOccurrenceAndIgnoresNoOpRequests Record one change against the same source slot.

            [document, registry, component] = testCase.fixture();
            original = component.getSettings("Text");
            document.setProperty(component.Id, "Text", "Changed", registry);
            testCase.verifyEqual(component.getSettings("Text").Id, original.Id);
            testCase.verifyEqual(component.getSettings("Text").LiteralValue, "Changed");
            document.setProperty(component.Id, "Text", "Changed", registry);
            document.setPropertyBatch(component.Id, ...
                macd.model.PropertyTransaction.singleChange("Text", "Changed"), registry);
            testCase.verifyEqual(document.HistoryIndex, 1);
            document.undo();
            testCase.verifyEqual(component.getProperty("Text").LiteralValue, "First");
            testCase.verifyFalse(document.IsDirty);
        end

        function changedSourceBaselineIsRejectedBeforeUsingOldTokenLocations(testCase)
            % changedSourceBaselineIsRejectedBeforeUsingOldTokenLocations Detect a source-version mismatch.

            [document, registry, component] = testCase.fixture();
            document.OriginalText = "% changed outside parser" + newline + document.OriginalText;
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyEqual(source, "");
            testCase.verifyTrue(any(string({diagnostics.Code}) == "stale-source-snapshot"));
            testCase.verifyError(@() document.setProperty(component.Id, "Text", "Changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(component.getProperty("Text").LiteralValue, "First");
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function pendingSettingsRetainOriginalValuesAcrossResetUndo(testCase)
            % pendingSettingsRetainOriginalValuesAcrossResetUndo Preserve generated occurrence identity.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("PendingApp", registry);
            component = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.setProperty(component.Id, "Text", "First");
            original = component.getSettings("Text");
            testCase.verifyEqual(original.Method, "assignment");
            testCase.verifyNotEmpty(original.SourceSpan);
            document.setProperty(component.Id, "Text", "Second");
            document.resetProperty(component.Id, "Text");
            testCase.verifyEmpty(component.getSettings("Text"));
            document.undo();
            testCase.verifyEqual(component.getSettings("Text").Id, original.Id);
            testCase.verifyEqual(component.getSettings("Text").LiteralValue, "Second");
            testCase.verifyEqual(component.getProperty("Text").LiteralValue, "Second");
            document.undo();
            testCase.verifyEqual(component.getProperty("Text").LiteralValue, "First");
            document.redo();
            document.redo();
            testCase.verifyEmpty(component.getProperty("Text"));
        end

        function historyRefusesAReboundSourceOccurrence(testCase)
            % historyRefusesAReboundSourceOccurrence Leave the history cursor unchanged on stale targets.

            [document, ~, component] = testCase.fixture();
            document.setProperty(component.Id, "Text", "Changed");
            entry = component.getProperty("Text");
            entry.Metadata.SourceSettingId = "different occurrence";
            testCase.verifyError(@() document.undo(), "macd:DocumentModel:StalePropertySetting");
            testCase.verifyEqual(document.HistoryIndex, 1);
            testCase.verifyEqual(entry.LiteralValue, "Changed");
        end
    end

    methods (Static, Access = private)
        function [document, registry, component] = sliderFixture(initialization)
            % sliderFixture Parse an owned range-dependent component without executing its app.
            arguments (Input)
                initialization (1, :) string = ["app.Slider = uislider(app.UIFigure);", ...
                    "app.Slider.Value = 20;", "app.Slider.Limits = [50 100];"]
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                component (1, 1) macd.model.ComponentRecord
            end
            source = strjoin(["classdef StateEditApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Slider matlab.ui.control.Slider", "end", "methods", ...
                "function app = StateEditApp", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                initialization, "end", "end", "end"], sprintf("\r\n"));
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Slider");
        end

        function [document, registry, component] = fixture()
            % fixture Parse an owned label initializer without constructing its UI.
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                component (1, 1) macd.model.ComponentRecord
            end

            source = strjoin(["classdef EditApp < handle", ...
                "    properties", "        UIFigure matlab.ui.Figure", ...
                "        Label matlab.ui.control.Label", "    end", "    methods", ...
                "        function app = EditApp", "            createComponents(app);", "        end", ...
                "        function createComponents(app)", ...
                "            app.UIFigure = uifigure(""Visible"", ""off"");", ...
                "            app.Label = uilabel(app.UIFigure, Text=""First"");", ...
                "            app.Label.Position = [10 20 100 30];", ...
                "        end", "    end", "end"], sprintf("\r\n"));
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Label");
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
