classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) PropertyCopyTest < matlab.unittest.TestCase
    % PropertyCopyTest Copy source settings without reusing source identities.
    %   Owned fixtures exercise constructor arguments, implicit setter effects,
    %   independent clipboard data, and atomic generation preflight.

    methods (Test)
        % Guarantee: copied settings reproduce the original's effective state without inventing values native code computes.
        % Failure mode: Paste copies a stale explicit Value instead of the clamped or fallback value, or writes computed ticks as literals.
        function copiesClampedValueAndRetainsOriginalHistory(testCase)
            % copiesClampedValueAndRetainsOriginalHistory Preserve original setters and their resulting clamped value.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 20;", "app.Control.Limits = [50 100];"]);
            before = component.settingSnapshot();
            history = document.HistoryIndex;
            snapshot = document.copySubtree(component.Id, registry);
            testCase.verifyEqual(snapshot.Records.Properties(string({snapshot.Records.Properties.Path}) == "Value").LiteralValue, 20);
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyFalse(document.IsDirty);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(PropertyCopyTest.effectiveValue(document, registry, pasted.Id), 50);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            ids = string({pasted.Settings.Id});
            testCase.verifyFalse(any(ismember(ids, string({component.Settings.Id}))));
            testCase.verifyTrue(all(string({pasted.Settings.Method}) == "assignment"));
            testCase.verifyTrue(all(arrayfun(@(setting) ~isempty(setting.SourceSpan), pasted.Settings)));
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            document.redo();
            testCase.verifyEqual(PropertyCopyTest.effectiveValue(document, registry, pasted.Id), 50);
        end

        % Guarantee: copied constructor arguments keep their spelling, order, and style-specific names.
        % Failure mode: Paste normalizes constructor arguments or uses names that the concrete style does not accept.
        function constructorValuesKeepTheirSpellingAndOrder(testCase)
            % constructorValuesKeepTheirSpellingAndOrder Copy each named spelling in its original constructor argument order.
            for creation = ["app.Control = uislider(app.Left, Value=150, Limits=[120 200]);", ...
                    "app.Control = uislider(app.Left, 'Value', 150, 'Limits', [120 200]);"]
                [document, registry, component, target] = testCase.fixture(creation);
                snapshot = document.copySubtree(component.Id, registry);
                pasted = document.pasteSubtree(snapshot, target.Id, registry);
                source = document.GeneratedText;
                copiedCreation = replace(creation, ["app.Control", "app.Left"], ["app." + pasted.Name, "app.Right"]);
                testCase.verifySubstring(source, copiedCreation);
                reopened = yamada.source.AppSourceParser.parseText(source, registry);
                copied = reopened.getComponentByName(pasted.Name);
                testCase.verifyNumElements(copied.getSettings("Value"), 1);
                testCase.verifyEqual(copied.getSettings("Value").Method, "nameValue");
            end
        end

        function mixedItemDomainCopiesFallbackSelection(testCase)
            % mixedItemDomainCopiesFallbackSelection Copy the selected data after a domain change rather than the old explicit Value.
            % Guarantee and failure mode: shared with copiesClampedValueAndRetainsOriginalHistory.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20], Value=20);", ...
                "app.Control.ItemsData = [100 200];"]);
            snapshot = document.copySubtree(component.Id, registry);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(PropertyCopyTest.effectiveValue(document, registry, pasted.Id), 100);
            testCase.verifyEqual(pasted.getProperty("ItemsData").LiteralValue, [100 200]);
            testCase.verifyEqual(pasted.CreationArguments, component.CreationArguments);
        end

        function numericStyleSurvivesArgumentProjection(testCase)
            % numericStyleSurvivesArgumentProjection Retain positional style arguments while copying a rounded effective value.
            [document, registry, component, target] = testCase.fixture( ...
                "app.Control = uieditfield(app.Left, 'numeric', Value=3.4, RoundFractionalValues='on');");
            pasted = document.pasteSubtree(document.copySubtree(component.Id, registry), target.Id, registry);
            testCase.verifyEqual(pasted.CreationArguments, component.CreationArguments);
            testCase.verifyEqual(PropertyCopyTest.effectiveValue(document, registry, pasted.Id), 3);
            testCase.verifySubstring(document.GeneratedText, "uieditfield(app.Right, 'numeric',");
        end

        function styleSpecificNamedArgumentsUseTheirConcreteSurface(testCase)
            % styleSpecificNamedArgumentsUseTheirConcreteSurface Preserve state, discrete, and range factory styles through copying.
            % Guarantee and failure mode: shared with constructorValuesKeepTheirSpellingAndOrder.
            cases = {"app.Control = uibutton(app.Left, 'state', Value=true);", "matlab.ui.control.StateButton", 'state', true, "uibutton-state"; ...
                "app.Control = uiknob(app.Left, 'discrete', Items={'A','B'}, Value='B');", "matlab.ui.control.DiscreteKnob", 'discrete', 'B', "uiknob-discrete"; ...
                "app.Control = uislider(app.Left, 'range', Value=[10 20], Limits=[5 25]);", "matlab.ui.control.RangeSlider", 'range', [10 20], "uislider-range"};
            % Styles missing from the running release's catalog are reported after the others run.
            available = yamada.model.ComponentRegistry.createDefault().listVariantIds();
            supported = ismember([cases{:, 5}], available);
            for index = find(supported)
                [document, registry, component, target] = testCase.fixture(cases{index, 1}, cases{index, 2});
                pasted = document.pasteSubtree(document.copySubtree(component.Id, registry), target.Id, registry);
                testCase.verifyEqual(pasted.CreationArguments, component.CreationArguments);
                testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, cases{index, 4});
            end
            for index = find(~supported), assumeCatalogSupports(testCase, cases{index, 5}); end
        end

        % Guarantee: Paste uses the configuration frozen at Copy and never changes history while preparing.
        % Failure mode: edits after Copy leak into Paste, or an unresolved conversion mutates the source document.
        function rawSnapshotPreparationUsesFrozenRecords(testCase)
            % rawSnapshotPreparationUsesFrozenRecords Resolve a source snapshot rather than later changes to its live component.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 20;", "app.Control.Limits = [50 100];"]);
            snapshot = yamada.model.SubtreeSnapshot(document, component.Id);
            document.setProperty(component.Id, "Limits", [0 100], registry);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("Limits").LiteralValue, [50 100]);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 50);
            other = yamada.source.AppSourceParser.parseText(document.OriginalText, registry);
            otherTarget = other.getComponentByName("Right");
            testCase.verifyError(@() other.pasteSubtree(snapshot, otherTarget.Id, registry), "yamada:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(other.HistoryIndex, 0);
        end

        function implicitSelectionRemainsImplicit(testCase)
            % implicitSelectionRemainsImplicit Preserve both effective selection and absence of an explicit Value assignment.
            % Guarantee and failure mode: shared with copiesClampedValueAndRetainsOriginalHistory.
            [document, registry, component, target] = testCase.fixture( ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20]);");
            testCase.verifyEmpty(component.getSettings("Value"));
            pasted = document.pasteSubtree(document.copySubtree(component.Id, registry), target.Id, registry);
            testCase.verifyEmpty(component.getSettings("Value"));
            testCase.verifyEmpty(pasted.getSettings("Value"));
            testCase.verifyEqual(PropertyCopyTest.effectiveValue(document, registry, pasted.Id), 10);
        end

        function clipboardConfigurationStaysFrozenAfterLaterEdits(testCase)
            % clipboardConfigurationStaysFrozenAfterLaterEdits Keep copied effective values independent of live settings and handles.
            % Guarantee and failure mode: shared with rawSnapshotPreparationUsesFrozenRecords.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 20;", "app.Control.Limits = [50 100];"]);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, component.Id, registry);
            document.setProperty(component.Id, "Limits", [0 100], registry);
            pasted = clipboard.paste(document, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("Limits").LiteralValue, [50 100]);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(PropertyCopyTest.effectiveValue(document, registry, pasted.Id), 50);
            pasted.getProperty("Value").setLiteral(75);
            second = clipboard.paste(document, target.Id, registry);
            testCase.verifyEqual(second.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(PropertyCopyTest.effectiveValue(document, registry, second.Id), 50);
        end

        function automaticTicksRetainModeWithoutInventingComputedValues(testCase)
            % automaticTicksRetainModeWithoutInventingComputedValues Retain the last input and mode without asserting a computed array.
            % Guarantee and failure mode: shared with copiesClampedValueAndRetainsOriginalHistory.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.MajorTicks = [0 25 100];", ...
                "app.Control.MajorTicksMode = 'auto';"]);
            snapshot = document.copySubtree(component.Id, registry);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("MajorTicks").LiteralValue, [0 25 100]);
            testCase.verifyEqual(pasted.getProperty("MajorTicksMode").LiteralValue, 'auto');
            states = document.getEffectivePropertyStates(registry, pasted.Id);
            tick = states(arrayfun(@(state) state.Definition.Path == "MajorTicks", states)).Resolution;
            testCase.verifyFalse(tick.IsKnown);
            testCase.verifyEqual(tick.ReasonCode, "automatic");
        end

        function unresolvedConversionKeepsSourceWithoutChangingHistory(testCase)
            % unresolvedConversionKeepsSourceWithoutChangingHistory Retain input values without resolving native adjustments.
            % Guarantee and failure mode: shared with rawSnapshotPreparationUsesFrozenRecords.
            [document, registry, component] = testCase.fixture([ ...
                "app.Control = uieditfield(app.Left, 'numeric');", "app.Control.Limits = [0 1];", ...
                "app.Control.Value = 0;", "app.Control.LowerLimitInclusive = 'off';"]);
            before = component.settingSnapshot();
            testCase.verifyNotEmpty(document.copySubtree(component.Id, registry));
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end
    end

    methods (Static, Access = private)
        function value = effectiveValue(document, registry, id)
            % effectiveValue Read the Value getter without changing explicit settings.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                id (1, 1) string
            end
            arguments (Output)
                value
            end
            states = document.getEffectivePropertyStates(registry, id);
            state = states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution;
            value = state.EffectiveValue;
        end

        function [document, registry, component, target] = fixture(body, declaredType)
            % fixture Build owned handle-based source with explicit geometry and independent destination.
            arguments (Input)
                body (1, :) string
                declaredType (1, 1) string = ""
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                component (1, 1) yamada.model.ComponentRecord
                target (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            if strlength(declaredType) == 0
                declaredType = "matlab.ui.control.Slider";
                if any(contains(body, "uidropdown")), declaredType = "matlab.ui.control.DropDown"; end
                if any(contains(body, "uieditfield")), declaredType = "matlab.ui.control.NumericEditField"; end
            end
            source = strjoin(["classdef PropertyCopyApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Left matlab.ui.container.Panel", "Right matlab.ui.container.Panel", ...
                "Control " + declaredType, "end", "methods", "function app = PropertyCopyApp", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Left = uipanel(app.UIFigure);", body, "app.Control.Position = [10 20 100 22];", ...
                "app.Right = uipanel(app.UIFigure);", "end", "end", "end"], sprintf("\r\n"));
            document = yamada.source.AppSourceParser.parseText(source, registry);
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
