classdef (TestTags = {'fast', 'model', 'parser', 'generation'}) PropertyStateResolverTest < matlab.unittest.TestCase
    % PropertyStateResolverTest Verify source history and audited effective state separately.
    %   The fixtures contain only immutable setting records; no represented
    %   application or native control is executed by these tests.

    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Load the release catalog once for this read-only fixture class.
            testCase.Registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Test)
        function clampingDoesNotRewriteExplicitOrRequestedValues(testCase)
            % clampingDoesNotRewriteExplicitOrRequestedValues Retain the Value slot while Limits changes its effect.
            [component, definitions] = testCase.fixture("uislider-slider", {"Value", 20; "Limits", [50 100]});
            before = component.settingSnapshot();
            [states, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            value = testCase.state(states, "Value");
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(value.ExplicitValue, 20);
            testCase.verifyEqual(value.RequestedValue, 20);
            testCase.verifyEqual(value.EffectiveValue, 50);
            testCase.verifyTrue(value.IsKnown);
            testCase.verifyEqual(value.EffectSettingId, component.getSettings("Limits").Id);
            testCase.verifyNotEqual(value.LastSettingId, value.EffectSettingId);
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
        end

        function constructorUsesFinalDomainInsteadOfTextualSetterValidation(testCase)
            % constructorUsesFinalDomainInsteadOfTextualSetterValidation Admit a constructor value above default limits.
            [component, definitions] = testCase.fixture("uislider-slider", ...
                {"Value", 150; "Limits", [120 200]}, "nameValue");
            [states, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(testCase.state(states, "Value").EffectiveValue, 150);
            [component, definitions] = testCase.fixture("uislider-slider", {"Value", 150; "Limits", [120 200]});
            [~, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyTrue(any(string({diagnostics.Code}) == "invalid-property-sequence"));
        end

        function constructorModesStillFollowArgumentOrder(testCase)
            % constructorModesStillFollowArgumentOrder Preserve mode effects observed for actual R2024a constructors.
            [component, definitions] = testCase.fixture("uislider-slider", ...
                {"MajorTicksMode", "auto"; "MajorTicks", [10 90]}, "nameValue");
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "MajorTicksMode").EffectiveValue, "manual");
            [component, definitions] = testCase.fixture("uislider-slider", ...
                {"MajorTicks", [10 90]; "MajorTicksMode", "auto"}, "nameValue");
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "MajorTicksMode").EffectiveValue, "auto");
            testCase.verifyFalse(testCase.state(states, "MajorTicks").IsKnown);
        end

        function numericRoundingIsAnEffectRatherThanAnExplicitWrite(testCase)
            % numericRoundingIsAnEffectRatherThanAnExplicitWrite Model programmatic rounding without altering source history.
            [component, definitions] = testCase.fixture("uieditfield-numeric", ...
                {"Value", 2.4; "RoundFractionalValues", "on"});
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            value = testCase.state(states, "Value");
            testCase.verifyEqual(value.ExplicitValue, 2.4);
            testCase.verifyEqual(value.EffectiveValue, 2);
            [component, definitions] = testCase.fixture("uieditfield-numeric", ...
                {"Limits", [0 2]; "RoundFractionalValues", "on"; "Value", 2.4});
            [states, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(testCase.state(states, "Value").EffectiveValue, 2);
        end

        function emptyNumericValuesRequireAllowEmpty(testCase)
            % emptyNumericValuesRequireAllowEmpty Distinguish a known empty value from an unknown state.
            [component, definitions] = testCase.fixture("uieditfield-numeric", {"Value", []});
            [~, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyNotEmpty(diagnostics);
            [component, definitions] = testCase.fixture("uieditfield-numeric", {"AllowEmpty", "on"; "Value", []});
            [states, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEmpty(diagnostics);
            value = testCase.state(states, "Value");
            testCase.verifyTrue(value.IsKnown);
            testCase.verifyEmpty(value.EffectiveValue);
            component.recordSetting(testCase.setting("AllowEmpty", "off", 3));
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "Value").EffectiveValue, 0);
        end

        function characterLimitsClearOutOfRangeText(testCase)
            % characterLimitsClearOutOfRangeText Retain the explicit text while exposing its cleared effective value.
            [component, definitions] = testCase.fixture("uieditfield-text", {"Value", "Hello"; "CharacterLimits", [6 Inf]});
            [states, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEmpty(diagnostics);
            value = testCase.state(states, "Value");
            testCase.verifyEqual(value.ExplicitValue, "Hello");
            testCase.verifyEqual(string(value.EffectiveValue), "");
        end

        function replacementRequestsRemainAtTheirSourceOccurrences(testCase)
            % replacementRequestsRemainAtTheirSourceOccurrences Detect a later setter overriding a requested replacement.
            [component, definitions] = testCase.fixture("uislider-slider", {"Value", 20; "Limits", [50 100]});
            component.setProperty("Value", 30);
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            value = testCase.state(states, "Value");
            testCase.verifyEqual(value.ExplicitValue, 20);
            testCase.verifyEqual(value.RequestedValue, 30);
            testCase.verifyEqual(value.EffectiveValue, 50);
        end

        function unresolvedEffectsStayUnknownAndLaterWritesCanRestoreKnowledge(testCase)
            % unresolvedEffectsStayUnknownAndLaterWritesCanRestoreKnowledge Never fall back to an earlier literal.
            [component, definitions] = testCase.fixture("uislider-slider", {"Value", 20});
            location = testCase.setting("Limits", [], 2).toStruct().Location;
            location.SourceExpression = "readLimits()";
            component.recordSetting(macd.model.PropertySetting("Limits", [], location));
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyFalse(testCase.state(states, "Value").IsKnown);
            component.recordSetting(testCase.setting("Limits", [0 100], 3));
            component.recordSetting(testCase.setting("Value", 75, 4));
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyTrue(testCase.state(states, "Value").IsKnown);
            testCase.verifyEqual(testCase.state(states, "Value").EffectiveValue, 75);
        end

        function axesValuesSelectManualModeWithoutAddingExplicitSettings(testCase)
            % axesValuesSelectManualModeWithoutAddingExplicitSettings Preserve original histories while resolving known mode side effects.
            for id = ["axes", "uiaxes", "polaraxes", "geoaxes"]
                [component, definitions] = testCase.fixture(id, {"FontSize", 14});
                states = macd.model.PropertyStateResolver.resolve(component, definitions);
                mode = testCase.state(states, "FontSizeMode");
                testCase.verifyTrue(mode.IsKnown);
                testCase.verifyEqual(mode.EffectiveValue, "manual");
                testCase.verifyEqual(mode.ExplicitKind, "absent");
                testCase.verifyEmpty(component.getSettings("FontSizeMode"));
                testCase.verifyEqual(testCase.state(states, "FontSize").EffectiveValue, 14);
            end
        end

        function axesConstructorAndAutomaticModesRetainExecutionOrder(testCase)
            % axesConstructorAndAutomaticModesRetainExecutionOrder Distinguish final auto, final manual, and uncertain mode expressions.
            [component, definitions] = testCase.fixture("uiaxes", {"XTickMode", "auto"; "XTick", [0 1]}, "nameValue");
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "XTickMode").EffectiveValue, "manual");
            testCase.verifyEqual(testCase.state(states, "XTick").EffectiveValue, [0 1]);
            [component, definitions] = testCase.fixture("uiaxes", {"XTick", [0 1]; "XTickMode", "auto"}, "nameValue");
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyFalse(testCase.state(states, "XTick").IsKnown);
            testCase.verifyEqual(testCase.state(states, "XTick").ReasonCode, "automatic");
            location = testCase.setting("XTickMode", [], 3).toStruct().Location;
            location.SourceExpression = "chooseMode()";
            component.recordSetting(macd.model.PropertySetting("XTickMode", [], location));
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyFalse(testCase.state(states, "XTickMode").IsKnown);
            testCase.verifyFalse(testCase.state(states, "XTick").IsKnown);
            testCase.verifyEqual(testCase.state(states, "XTick").ReasonCode, "uncertain-mode");
        end

        function automaticLimitEndpointsAreNotPretendedToBeResolved(testCase)
            % automaticLimitEndpointsAreNotPretendedToBeResolved Retain the input but mark data-dependent output as unknown.
            [component, definitions] = testCase.fixture("uiaxes", {"XLim", [-Inf 10]});
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "XLim").ExplicitValue, [-Inf 10]);
            testCase.verifyFalse(testCase.state(states, "XLim").IsKnown);
            testCase.verifyEqual(testCase.state(states, "XLim").ReasonCode, "automatic-limits");
            testCase.verifyEqual(testCase.state(states, "XLimMode").EffectiveValue, "manual");
        end

        function constructorUnitConversionsAreNotReplacedByRawNumbers(testCase)
            % constructorUnitConversionsAreNotReplacedByRawNumbers Respect source argument order for position units.
            [component, definitions] = testCase.fixture("uipanel", ...
                {"Position", [1 1 200 100]; "Units", "normalized"}, "nameValue");
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyFalse(testCase.state(states, "Position").IsKnown);
            testCase.verifySubstring(testCase.state(states, "Position").Reason, "Units changed");
            [component, definitions] = testCase.fixture("uipanel", ...
                {"Units", "normalized"; "Position", [0.1 0.1 0.5 0.5]}, "nameValue");
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "Position").EffectiveValue, [0.1 0.1 0.5 0.5]);
        end

        function itemDataTransitionsUseReviewedValueAndIndexRules(testCase)
            % itemDataTransitionsUseReviewedValueAndIndexRules Preserve an index when switching between labels and data.
            [component, definitions] = testCase.fixture("uidropdown", ...
                {"Items", {'A','B'}; "Value", 'B'; "ItemsData", [10 20]});
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "Value").EffectiveValue, 20);
            component.recordSetting(testCase.setting("ItemsData", [30 40], 4));
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyEqual(testCase.state(states, "Value").EffectiveValue, 30);
        end

        function extraItemDataIsNotAnAvailableSelection(testCase)
            % extraItemDataIsNotAnAvailableSelection Ignore data entries with no corresponding visible item.
            [component, definitions] = testCase.fixture("uidropdown", ...
                {"Items", {'A','B'}; "ItemsData", [10 20 30]; "Value", 30});
            [~, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyNotEmpty(diagnostics);
        end

        function defaultsAndStateCopiesNeverMaterializeSourceSettings(testCase)
            % defaultsAndStateCopiesNeverMaterializeSourceSettings Keep derived state independent from editable records.
            [component, definitions] = testCase.fixture("uislider-slider", cell(0, 2));
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            value = testCase.state(states, "Value");
            testCase.verifyEqual(value.ExplicitKind, "absent");
            testCase.verifyEqual(value.EffectiveValue, 0);
            changed = value.withEffective(50, true, "owned-effect");
            testCase.verifyEqual(value.EffectiveValue, 0);
            testCase.verifyEqual(changed.EffectiveValue, 50);
            testCase.verifyEmpty(component.Properties);
            testCase.verifyEmpty(component.Settings);
        end
    end

    methods (Access = private)
        function [component, definitions] = fixture(testCase, id, writes, method)
            % fixture Build a source-backed record without constructing or evaluating an app.
            arguments (Input)
                testCase (1, 1) PropertyStateResolverTest
                id (1, 1) string
                writes cell
                method (1, 1) string = "assignment"
            end
            arguments (Output)
                component (1, 1) macd.model.ComponentRecord
                definitions macd.model.PropertyDefinition
            end
            definition = testCase.Registry.getById(id);
            component = macd.model.ComponentRecord("owned-component", "OwnedComponent", ...
                definition.Factory, definition.DeclaredType, "parsed");
            component.CreationArguments = definition.CreationArguments;
            for index = 1:size(writes, 1)
                component.recordSetting(testCase.setting(writes{index, 1}, writes{index, 2}, index, method));
            end
            definitions = definition.Properties;
        end
    end

    methods (Static, Access = private)
        function setting = setting(path, value, sequence, method)
            % setting Create one certain owned occurrence with stable fake token locations.
            arguments (Input)
                path (1, 1) string
                value
                sequence (1, 1) double
                method (1, 1) string = "assignment"
            end
            arguments (Output)
                setting (1, 1) macd.model.PropertySetting
            end
            syntax = "dot";
            statementId = "owned-statement-" + sequence;
            if method == "nameValue", syntax = "quotedPair"; statementId = "owned-constructor"; end
            span = macd.model.SourceSpan(10 * sequence, 10 * sequence + 1);
            setting = macd.model.PropertySetting(path, value, struct("Method", method, "Syntax", syntax, ...
                "SourceSnapshotId", "owned-state", "SourceSpan", span, "ValueSpan", span, ...
                "Sequence", sequence, "StatementId", statementId));
        end

        function state = state(states, path)
            % state Select exactly one typed effective-state fixture result.
            arguments (Input)
                states macd.model.PropertyState
                path (1, 1) string
            end
            arguments (Output)
                state (1, 1) macd.model.PropertyState
            end
            state = states(string({states.Path}) == path);
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
