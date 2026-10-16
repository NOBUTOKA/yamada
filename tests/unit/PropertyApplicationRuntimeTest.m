classdef (TestTags = {'catalog', 'model', 'generation', 'preview', 'ui'}) PropertyApplicationRuntimeTest < matlab.unittest.TestCase
    % PropertyApplicationRuntimeTest Check reviewed rules against owned R2024a controls.
    %   Only test-authored factory arguments and literals reach native setters.
    %   These tests never execute opened app source or undocumented callbacks.

    methods (Test)
        function itemDomainsAreEstablishedBeforeSelection(testCase)
            % itemDomainsAreEstablishedBeforeSelection Verify all six item-backed variants.
            [figure, registry] = testCase.environment();
            cases = {"uidropdown", {}; "uilistbox", {}; ...
                "uiknob", {"discrete"}; "uiswitch", {"rocker"}; ...
                "uiswitch", {"slider"}; "uiswitch", {"toggle"}};
            for index = 1:size(cases, 1)
                entries = [macd.model.PropertyEntry("Value", 20), ...
                    macd.model.PropertyEntry("ItemsData", [10 20]), ...
                    macd.model.PropertyEntry("Items", ["Low", "High"])];
                target = testCase.apply(figure, registry, cases{index, 1}, cases{index, 2}, entries);
                testCase.verifyEqual(target.Value, 20);
                testCase.verifyEqual(string(target.Items), ["Low", "High"]);
                delete(target);
            end
        end

        function rangesAndNumericOptionsPrecedeRequestedValues(testCase)
            % rangesAndNumericOptionsPrecedeRequestedValues Apply values outside the default slider range safely.
            [figure, registry] = testCase.environment();
            cases = {"uislider", {"slider"}, 150; ...
                "uislider", {"range"}, [140 180]; ...
                "uiknob", {"continuous"}, 150; ...
                "uieditfield", {"numeric"}, 150; "uispinner", {}, 150};
            for index = 1:size(cases, 1)
                entries = [macd.model.PropertyEntry("Value", cases{index, 3}), ...
                    macd.model.PropertyEntry("Limits", [120 200])];
                target = testCase.apply(figure, registry, cases{index, 1}, cases{index, 2}, entries);
                testCase.verifyEqual(target.Value, cases{index, 3});
                delete(target);
            end
            for factory = ["uieditfield", "uispinner"]
                style = {};
                if factory == "uieditfield", style = {"numeric"}; end
                entries = [macd.model.PropertyEntry("Value", []), ...
                    macd.model.PropertyEntry("AllowEmpty", "on")];
                target = testCase.apply(figure, registry, factory, style, entries);
                testCase.verifyEmpty(target.Value);
                delete(target);
            end
        end

        function gaugesAllowOffScaleValuesWithoutClamping(testCase)
            % gaugesAllowOffScaleValuesWithoutClamping Distinguish all gauge variants from slider behavior.
            [figure, registry] = testCase.environment();
            for style = ["circular", "linear", "ninetydegree", "semicircular"]
                entries = [macd.model.PropertyEntry("Value", 20), ...
                    macd.model.PropertyEntry("Limits", [50 100])];
                target = testCase.apply(figure, registry, "uigauge", {style}, entries);
                testCase.verifyEqual(target.Value, 20);
                target.Value = 150;
                testCase.verifyEqual(target.Value, 150);
                delete(target);
            end
        end

        function explicitFinalModesSurviveTickSetterEffects(testCase)
            % explicitFinalModesSurviveTickSetterEffects Restore final automatic modes after explicit tick arrays.
            [figure, registry] = testCase.environment();
            cases = {"uislider", {"slider"}; "uislider", {"range"}; ...
                "uiknob", {"continuous"}; "uigauge", {"circular"}; ...
                "uigauge", {"linear"}; "uigauge", {"ninetydegree"}; ...
                "uigauge", {"semicircular"}};
            for index = 1:size(cases, 1)
                entries = [macd.model.PropertyEntry("MajorTicksMode", "auto"), ...
                    macd.model.PropertyEntry("MinorTicksMode", "auto"), ...
                    macd.model.PropertyEntry("MajorTickLabelsMode", "auto"), ...
                    macd.model.PropertyEntry("MajorTickLabels", ["Low", "High"]), ...
                    macd.model.PropertyEntry("MajorTicks", [0 100]), ...
                    macd.model.PropertyEntry("MinorTicks", [25 75]), ...
                    macd.model.PropertyEntry("Limits", [0 100])];
                target = testCase.apply(figure, registry, cases{index, 1}, cases{index, 2}, entries);
                testCase.verifyEqual(string(target.MajorTicksMode), "auto");
                testCase.verifyEqual(string(target.MinorTicksMode), "auto");
                testCase.verifyEqual(string(target.MajorTickLabelsMode), "auto");
                delete(target);
            end
        end

        function axisValueModesAreOrderedAndPreserved(testCase)
            % axisValueModesAreOrderedAndPreserved Compare all reviewed axes mode pairs with native setters and constructors.
            [figure, registry] = testCase.environment();
            projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            oldPath = path;
            pathCleanup = onCleanup(@() path(oldPath));
            addpath(fullfile(projectRoot, "dev", "component-data"));
            output = string(tempname) + ".json";
            fileCleanup = onCleanup(@() delete(output));
            results = ProbeAxisModeInteractions(output);
            checked = 0;
            for result = results
                testCase.assertEqual(result.Error, "");
                definition = registry.getById(result.Factory);
                property = definition.Properties(string({definition.Properties.Path}) == result.Path);
                if property.Application.EffectPolicy ~= "valueMode", continue, end
                testCase.verifyEqual(result.DefaultMode, "auto");
                testCase.verifyEqual(result.ManualMode, "manual");
                testCase.verifyTrue(result.ManualMatches, result.Factory + "." + result.Path);
                testCase.verifyEqual(result.ConstructorValueLastMode, "manual");
                testCase.verifyEqual(result.ConstructorModeLastMode, "auto");
                entries = [macd.model.PropertyEntry(result.Path + "Mode", "auto"), ...
                    macd.model.PropertyEntry(result.Path, result.RequestedValue)];
                creation = {};
                if result.Factory == "geoaxes", creation = {"Basemap", "none"}; end
                target = testCase.apply(figure, registry, result.Factory, creation, entries);
                testCase.verifyEqual(string(target.(result.Path + "Mode")), "auto");
                delete(target);
                checked = checked + 1;
            end
            testCase.verifyEqual(checked, 49);
        end

        function unitsAreEstablishedBeforeCoordinatesAndFontSize(testCase)
            % unitsAreEstablishedBeforeCoordinatesAndFontSize Avoid conversion of values assigned in old units.
            [figure, registry] = testCase.environment();
            for factory = ["uipanel", "uibuttongroup", "uitable", "uiaxes", "axes", "polaraxes"]
                entries = [macd.model.PropertyEntry("Position", [1 1 8 6]), ...
                    macd.model.PropertyEntry("Units", "centimeters"), ...
                    macd.model.PropertyEntry("FontSize", 14), ...
                    macd.model.PropertyEntry("FontUnits", "points")];
                target = testCase.apply(figure, registry, factory, {}, entries);
                testCase.verifyEqual(target.Position, [1 1 8 6], "AbsTol", 1e-8);
                testCase.verifyEqual(target.FontSize, 14, "AbsTol", 1e-8);
                delete(target);
            end
        end

        function implicitValueChangesAreSeparateFromExplicitWrites(testCase)
            % implicitValueChangesAreSeparateFromExplicitWrites Pin documented side effects for future state resolution.
            [figure, ~] = testCase.environment();
            slider = uislider(figure, "Value", 20);
            slider.Limits = [50 100];
            testCase.verifyEqual(slider.Value, 50);
            field = uieditfield(figure, "numeric", "Value", 2.4);
            field.RoundFractionalValues = "on";
            testCase.verifyEqual(field.Value, 2);
            textField = uieditfield(figure, "text", "Value", "Hello");
            textField.CharacterLimits = [6 Inf];
            testCase.verifyEqual(string(textField.Value), "");
        end

        function previewPlanPreservesParsedSetterEffectsAndEarlierWrites(testCase)
            % previewPlanPreservesParsedSetterEffectsAndEarlierWrites Avoid treating canonical order as original execution order.
            [figure, registry] = testCase.environment();
            definition = registry.get("uislider");
            component = macd.model.ComponentRecord("owned-slider", "Slider", ...
                "uislider", definition.DeclaredType, "parsed");
            writes = {"Value", 20; "Limits", [50 100]; "Value", 75; "Limits", [80 100]};
            for index = 1:size(writes, 1)
                location = struct("Method", "assignment", "Syntax", "dot", ...
                    "SourceSnapshotId", "owned-preview", "Sequence", index, ...
                    "SourceSpan", macd.model.SourceSpan(index, index));
                component.recordSetting(macd.model.PropertySetting(writes{index, 1}, writes{index, 2}, location));
            end
            document = macd.model.NewAppFactory.createEmpty("OwnedReplayApp", registry);
            entries = macd.model.PropertyApplicationPlanner.forPreview(component, document, registry);
            testCase.verifyEqual(string({entries.Path}), ["Value", "Limits", "Value", "Limits"]);
            target = uislider(figure);
            for entry = entries
                target.(entry.Path) = entry.LiteralValue;
            end
            testCase.verifyEqual(target.Value, 80);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 75);
            settings = component.getSettings("Value");
            testCase.verifyEqual(settings(1).LiteralValue, 20);
        end
    end

    methods (Access = private)
        function [figure, registry] = environment(testCase)
            % environment Own one invisible figure and the release-backed registry per test.
            arguments (Input)
                testCase (1, 1) PropertyApplicationRuntimeTest
            end
            arguments (Output)
                figure (1, 1) matlab.ui.Figure
                registry (1, 1) macd.model.ComponentRegistry
            end
            figure = uifigure("Visible", "off");
            testCase.addTeardown(@() delete(figure));
            registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Static, Access = private)
        function target = apply(figure, registry, factory, creationArguments, entries)
            % apply Run only owned literal setters in the shared planner's order.
            arguments (Input)
                figure (1, 1) matlab.ui.Figure
                registry (1, 1) macd.model.ComponentRegistry
                factory (1, 1) string
                creationArguments cell
                entries macd.model.PropertyEntry
            end
            arguments (Output)
                target
            end
            definition = registry.get(factory, creationArguments);
            entries = macd.model.PropertyApplicationPlanner.order(entries, definition.Properties);
            target = feval(factory, figure, creationArguments{:});
            for entry = entries
                target.(entry.Path) = entry.LiteralValue;
            end

            % Independently check constructor support and its grouped setter behavior.
            pairs = cell(1, 2 * numel(entries));
            for index = 1:numel(entries)
                pairs{2 * index - 1} = entries(index).Path;
                pairs{2 * index} = entries(index).LiteralValue;
            end
            constructed = feval(factory, figure, creationArguments{:}, pairs{:});
            cleanup = onCleanup(@() delete(constructed));
            for entry = entries
                assert(isequaln(constructed.(entry.Path), target.(entry.Path)), ...
                    "macd:PropertyApplicationRuntimeTest:ConstructorMismatch", ...
                    "Constructor and ordered setters disagree for %s.%s.", factory, entry.Path);
            end
            clear cleanup
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
