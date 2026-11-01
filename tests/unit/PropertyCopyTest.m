classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) PropertyCopyTest < matlab.unittest.TestCase
    % PropertyCopyTest Copy effective configurations without reusing source identities.
    %   Owned fixtures exercise constructor arguments, implicit setter effects,
    %   independent clipboard data, and atomic generation preflight.

    methods (Test)
        function copiesClampedValueAndRetainsOriginalHistory(testCase)
            % copiesClampedValueAndRetainsOriginalHistory Separate frozen source records from the resulting copy configuration.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 20;", "app.Control.Limits = [50 100];"]);
            before = component.settingSnapshot();
            history = document.HistoryIndex;
            snapshot = document.copySubtree(component.Id, registry);
            testCase.verifyEqual(snapshot.Records.Properties(string({snapshot.Records.Properties.Path}) == "Value").LiteralValue, 20);
            values = snapshot.CopyConfiguration.Properties;
            testCase.verifyEqual(values(string({values.Path}) == "Value").LiteralValue, 50);
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyFalse(document.IsDirty);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 50);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            ids = string({pasted.Settings.Id});
            testCase.verifyFalse(any(ismember(ids, string({component.Settings.Id}))));
            testCase.verifyTrue(all(string({pasted.Settings.Method}) == "assignment"));
            testCase.verifyTrue(all(arrayfun(@(setting) ~isempty(setting.SourceSpan), pasted.Settings)));
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            document.redo();
            testCase.verifyEqual(document.getComponent(pasted.Id).getProperty("Value").LiteralValue, 50);
        end

        function constructorValuesBecomeOneCanonicalCopySetting(testCase)
            % constructorValuesBecomeOneCanonicalCopySetting Remove both named spellings from copied factory arguments.
            for creation = ["app.Control = uislider(app.Left, Value=150, Limits=[120 200]);", ...
                    "app.Control = uislider(app.Left, 'Value', 150, 'Limits', [120 200]);"]
                [document, registry, component, target] = testCase.fixture(creation);
                snapshot = document.copySubtree(component.Id, registry);
                testCase.verifyEmpty(snapshot.CopyConfiguration.CreationArguments);
                pasted = document.pasteSubtree(snapshot, target.Id, registry);
                source = document.GeneratedText;
                testCase.verifySubstring(source, "app." + pasted.Name + " = uislider(app.Right);");
                limits = strfind(source, "app." + pasted.Name + ".Limits = [120 200];");
                value = strfind(source, "app." + pasted.Name + ".Value = 150;");
                testCase.verifyLessThan(limits, value);
                testCase.verifyNumElements(value, 1);
                reopened = macd.source.AppSourceParser.parseText(source, registry);
                copied = reopened.getComponentByName(pasted.Name);
                testCase.verifyNumElements(copied.getSettings("Value"), 1);
                testCase.verifyEqual(copied.getSettings("Value").Method, "assignment");
            end
        end

        function mixedItemDomainCopiesFallbackSelection(testCase)
            % mixedItemDomainCopiesFallbackSelection Copy the selected data after a domain change rather than the old explicit Value.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20], Value=20);", ...
                "app.Control.ItemsData = [100 200];"]);
            snapshot = document.copySubtree(component.Id, registry);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 100);
            testCase.verifyEqual(pasted.getProperty("ItemsData").LiteralValue, [100 200]);
            testCase.verifyEmpty(pasted.CreationArguments);
        end

        function numericStyleSurvivesArgumentProjection(testCase)
            % numericStyleSurvivesArgumentProjection Retain positional style arguments while copying a rounded effective value.
            [document, registry, component, target] = testCase.fixture( ...
                "app.Control = uieditfield(app.Left, 'numeric', Value=3.4, RoundFractionalValues='on');");
            pasted = document.pasteSubtree(document.copySubtree(component.Id, registry), target.Id, registry);
            testCase.verifyEqual(pasted.CreationArguments, {'numeric'});
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 3);
            testCase.verifySubstring(document.GeneratedText, "uieditfield(app.Right, 'numeric')");
        end

        function styleSpecificNamedArgumentsUseTheirConcreteSurface(testCase)
            % styleSpecificNamedArgumentsUseTheirConcreteSurface Preserve state, discrete, and range factory styles through copying.
            cases = {"app.Control = uibutton(app.Left, 'state', Value=true);", "matlab.ui.control.StateButton", 'state', true; ...
                "app.Control = uiknob(app.Left, 'discrete', Items={'A','B'}, Value='B');", "matlab.ui.control.DiscreteKnob", 'discrete', 'B'; ...
                "app.Control = uislider(app.Left, 'range', Value=[10 20], Limits=[5 25]);", "matlab.ui.control.RangeSlider", 'range', [10 20]};
            for index = 1:size(cases, 1)
                [document, registry, component, target] = testCase.fixture(cases{index, 1}, cases{index, 2});
                pasted = document.pasteSubtree(document.copySubtree(component.Id, registry), target.Id, registry);
                testCase.verifyEqual(pasted.CreationArguments, cases(index, 3));
                testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, cases{index, 4});
            end
        end

        function rawSnapshotPreparationUsesFrozenRecords(testCase)
            % rawSnapshotPreparationUsesFrozenRecords Resolve a source snapshot rather than later changes to its live component.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 20;", "app.Control.Limits = [50 100];"]);
            snapshot = macd.model.SubtreeSnapshot(document, component.Id);
            document.setProperty(component.Id, "Limits", [0 100], registry);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("Limits").LiteralValue, [50 100]);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 50);
            other = macd.source.AppSourceParser.parseText(document.OriginalText, registry);
            otherTarget = other.getComponentByName("Right");
            testCase.verifyError(@() other.pasteSubtree(snapshot, otherTarget.Id, registry), "macd:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(other.HistoryIndex, 0);
        end

        function implicitSelectionGetsFreshExplicitCopyIdentity(testCase)
            % implicitSelectionGetsFreshExplicitCopyIdentity Materialize a copy value without adding a source occurrence to the original.
            [document, registry, component, target] = testCase.fixture( ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], ItemsData=[10 20]);");
            testCase.verifyEmpty(component.getSettings("Value"));
            pasted = document.pasteSubtree(document.copySubtree(component.Id, registry), target.Id, registry);
            testCase.verifyEmpty(component.getSettings("Value"));
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 10);
            testCase.verifyNumElements(pasted.getSettings("Value"), 1);
            testCase.verifyEqual(pasted.getSettings("Value").Method, "assignment");
        end

        function clipboardConfigurationStaysFrozenAfterLaterEdits(testCase)
            % clipboardConfigurationStaysFrozenAfterLaterEdits Keep copied effective values independent of live settings and handles.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 20;", "app.Control.Limits = [50 100];"]);
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, component.Id, registry);
            document.setProperty(component.Id, "Limits", [0 100], registry);
            pasted = clipboard.paste(document, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("Limits").LiteralValue, [50 100]);
            testCase.verifyEqual(pasted.getProperty("Value").LiteralValue, 50);
            pasted.getProperty("Value").setLiteral(75);
            second = clipboard.paste(document, target.Id, registry);
            testCase.verifyEqual(second.getProperty("Value").LiteralValue, 50);
        end

        function automaticTicksRetainModeWithoutInventingComputedValues(testCase)
            % automaticTicksRetainModeWithoutInventingComputedValues Retain the last input and mode without asserting a computed array.
            [document, registry, component, target] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.MajorTicks = [0 25 100];", ...
                "app.Control.MajorTicksMode = 'auto';"]);
            snapshot = document.copySubtree(component.Id, registry);
            pasted = document.pasteSubtree(snapshot, target.Id, registry);
            testCase.verifyEqual(pasted.getProperty("MajorTicks").LiteralValue, [0 25 100]);
            testCase.verifyEqual(pasted.getProperty("MajorTicksMode").LiteralValue, 'auto');
            testCase.verifyFalse(any(string({snapshot.CopyConfiguration.Expected.Path}) == "MajorTicks"));
            states = document.getEffectivePropertyStates(registry, pasted.Id);
            tick = states(arrayfun(@(state) state.Definition.Path == "MajorTicks", states)).Resolution;
            testCase.verifyFalse(tick.IsKnown);
            testCase.verifyEqual(tick.ReasonCode, "automatic");
        end

        function unresolvedConversionRejectsCopyWithoutChangingHistory(testCase)
            % unresolvedConversionRejectsCopyWithoutChangingHistory Refuse unknown native adjustments without fabricating an effective value.
            [document, registry, component] = testCase.fixture([ ...
                "app.Control = uieditfield(app.Left, 'numeric');", "app.Control.Limits = [0 1];", ...
                "app.Control.Value = 0;", "app.Control.LowerLimitInclusive = 'off';"]);
            before = component.settingSnapshot();
            testCase.verifyError(@() document.copySubtree(component.Id, registry), "macd:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end
    end

    methods (Static, Access = private)
        function [document, registry, component, target] = fixture(body, declaredType)
            % fixture Build owned handle-based source with explicit geometry and independent destination.
            arguments (Input)
                body (1, :) string
                declaredType (1, 1) string = ""
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                component (1, 1) macd.model.ComponentRecord
                target (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
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
