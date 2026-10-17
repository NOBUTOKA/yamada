classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) PropertyInsertionPlannerTest < matlab.unittest.TestCase
    % PropertyInsertionPlannerTest Verify dependency-aware, source-preserving additions.
    %   The fixtures are owned AppBase text. Candidate parsing never executes
    %   the represented app, including its opaque calls or expressions.

    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Load one read-only release catalog for the fixture class.
            testCase.Registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Test)
        function cachedPlansRemainIndependentAndInvalidateOnDirectChange(testCase)
            % cachedPlansRemainIndependentAndInvalidateOnDirectChange Keep shared proofs private and exact.
            [document, component] = testCase.fixture("app.Control = uidropdown(app.UIFigure);");
            component.setProperty("Tooltip", "first");
            first = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            source = first.Edits;
            first.Component.setProperty("Tooltip", "private mutation");
            second = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(second.Edits, source);
            testCase.verifyEqual(string(second.Component.getProperty("Tooltip").LiteralValue), "first");
            component.setProperty("Tooltip", "second");
            third = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(string(third.Component.getProperty("Tooltip").LiteralValue), "second");
        end

        function sourceGenerationAndEffectiveStateUseTheSamePlacement(testCase)
            % sourceGenerationAndEffectiveStateUseTheSamePlacement Keep transactional edits and source output aligned.
            [document, component] = testCase.fixture(["app.Control = uidropdown(app.UIFigure);", ...
                "app.Control.Items = [""A"" ""B""];", "app.Control.ItemsData = [10 20];"]);
            document.setProperty(component.Id, "Value", 20, testCase.Registry);
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyGreaterThan(strfind(source, "app.Control.Value = 20;"), strfind(source, "app.Control.ItemsData = [10 20];"));
            states = document.getEffectivePropertyStates(testCase.Registry, component.Id);
            value = states(arrayfun(@(state) state.Definition.Path == "Value", states)).Resolution;
            testCase.verifyEqual(value.EffectiveValue, 20);
            testCase.verifyEqual(value.ExplicitKind, "pending");
            testCase.verifyEqual(value.LastSettingId, component.getSettings("Value").Id);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(testCase.Registry).generate(document), document.OriginalText);
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(testCase.Registry).generate(document), source);
        end

        function constructorAdditionsRemainEditableAfterReparse(testCase)
            % constructorAdditionsRemainEditableAfterReparse Bind the added token to a fresh immutable source occurrence.
            [document, component] = testCase.fixture("app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""], ItemsData=[10 20]);");
            document.setProperty(component.Id, "Value", 20, testCase.Registry);
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            reopened = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            selected = reopened.getComponentByName("Control");
            testCase.verifyEqual(selected.getSettings("Value").Method, "nameValue");
            reopened.setProperty(selected.Id, "Value", 10, testCase.Registry);
            modified = macd.source.RoundTripGenerator(testCase.Registry).generate(reopened);
            testCase.verifySubstring(modified, "Value=10");
            testCase.verifyFalse(contains(modified, "app.Control.Value ="));
            reopened.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(testCase.Registry).generate(reopened), source);
        end

        function insertionFailureLeavesDocumentAndHistoryUntouched(testCase)
            % insertionFailureLeavesDocumentAndHistoryUntouched Reject boundary conflicts before creating pending history.
            [document, component] = testCase.fixture(["app.Control = uidropdown(app.UIFigure);", ...
                "observed = app.Control.Value;", "app.Control.Items = [""A"" ""B""];", ...
                "app.Control.ItemsData = [10 20];"]);
            before = component.settingSnapshot();
            testCase.verifyError(@() document.setProperty(component.Id, "Value", 20, testCase.Registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(component.settingSnapshot(), before);
            testCase.verifyEmpty(component.getProperty("Value"));
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function positionalInitializationAddsAfterTheLastPrerequisite(testCase)
            % positionalInitializationAddsAfterTheLastPrerequisite Place Value after both item-domain settings.
            [document, component] = testCase.fixture(["app.Control = uidropdown(app.UIFigure);", ...
                "app.Control.Items = [""A"" ""B""];", "app.Control.ItemsData = [10 20];"]);
            component.setProperty("Value", 20);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(plan.Placements.Method, "assignment");
            testCase.verifyGreaterThanOrEqual(plan.Placements.Offset, component.getSettings("ItemsData").SourceSpan.EndOffset);
            testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 20);
            testCase.verifyFalse(contains(document.OriginalText, "app.Control.Value ="));
        end

        function constructorStylesReceiveVerifiedNameValueArguments(testCase)
            % constructorStylesReceiveVerifiedNameValueArguments Preserve both original name-value spellings.
            cases = ["app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""], ItemsData=[10 20]);", ...
                "app.Control = uidropdown(app.UIFigure, 'Items', {'A','B'}, 'ItemsData', [10 20]);"];
            for creation = cases
                [document, component] = testCase.fixture(creation);
                component.setProperty("Value", 20);
                plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
                testCase.verifyEqual(plan.Placements.Method, "nameValue");
                testCase.verifyEqual(plan.Component.getSettings("Value").Method, "nameValue");
                testCase.verifyEqual(plan.Component.getSettings("Value").Syntax, component.Settings(1).Syntax);
                testCase.verifyFalse(contains(plan.Document.OriginalText, "app.Control.Value ="));
            end
        end

        function mixedSettingsKeepNewValuesInTheAssignmentPhase(testCase)
            % mixedSettingsKeepNewValuesInTheAssignmentPhase Do not turn mixed initialization into constructor-only style.
            [document, component] = testCase.fixture([ ...
                "app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""]);", ...
                "app.Control.ItemsData = [10 20];"]);
            component.setProperty("Value", 20);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(plan.Placements.Method, "assignment");
        end

        function unknownConstructorSupportUsesAnAssignment(testCase)
            % unknownConstructorSupportUsesAnAssignment Require verified support rather than public SetAccess.
            [document, component] = testCase.fixture("app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""]);");
            component.setProperty("Tooltip", "Hint");
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(plan.Placements.Method, "assignment");
        end

        function simultaneousAdditionsUseOneStableDependencyOrder(testCase)
            % simultaneousAdditionsUseOneStableDependencyOrder Keep same-offset insertions from reversing their order.
            [document, component] = testCase.fixture("app.Control = uidropdown(app.UIFigure, FontSize=14);");
            component.setProperty("Value", 20);
            component.setProperty("ItemsData", [10 20]);
            component.setProperty("Items", ["A" "B"]);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(string({plan.Placements.Path}), ["Items", "ItemsData", "Value"]);
            testCase.verifyEqual(string({plan.Component.Settings.Path}), ["Items", "ItemsData", "Value", "FontSize"]);
        end

        function aNewRangeCanRepairAnEarlierOutOfDefaultValue(testCase)
            % aNewRangeCanRepairAnEarlierOutOfDefaultValue Validate the candidate sequence rather than pending-at-end fiction.
            [document, component] = testCase.fixture(["app.Control = uislider(app.UIFigure);", "app.Control.Value = 150;"]);
            component.setProperty("Limits", [120 200]);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyLessThan(plan.Placements.Offset, component.getSettings("Value").SourceSpan.StartOffset);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(plan.Document.Diagnostics));
        end

        function aSafeLaterRangeSetterCanClampAnEarlierValue(testCase)
            % aSafeLaterRangeSetterCanClampAnEarlierValue Do not reject a legal reverse sequence solely for canonical order.
            [document, component] = testCase.fixture(["app.Control = uislider(app.UIFigure);", "app.Control.Value = 20;"]);
            component.setProperty("Limits", [50 100]);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyGreaterThanOrEqual(plan.Placements.Offset, component.getSettings("Value").SourceSpan.EndOffset);
            states = plan.Document.getEffectivePropertyStates(testCase.Registry, plan.Component.Id);
            testCase.verifyEqual(states(arrayfun(@(state) state.Definition.Path == "Value", states)).Resolution.EffectiveValue, 50);
        end

        function observableReadsBoundTheInsertionInterval(testCase)
            % observableReadsBoundTheInsertionInterval Never jump over a property read to append after later prerequisites.
            [document, component] = testCase.fixture(["app.Control = uidropdown(app.UIFigure);", ...
                "observed = app.Control.Value;", "app.Control.Items = [""A"" ""B""];", ...
                "app.Control.ItemsData = [10 20];"]);
            component.setProperty("Value", 20);
            testCase.verifyError(@() macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry), ...
                "macd:PropertyInsertionPlanner:UnsafePlacement");
        end

        function helperOrderUsesExecutionRatherThanFileOffsets(testCase)
            % helperOrderUsesExecutionRatherThanFileOffsets Allow a later initializer that is declared earlier in the file.
            [document, component] = testCase.helperFixture(false);
            component.setProperty("Value", 20);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(plan.Placements.OwnerMethod, "configure");
            testCase.verifyLessThan(plan.Placements.Offset, component.SourceSpans.Creation.StartOffset);
            setting = component.getSettings("Items");
            testCase.verifyEqual(setting.OwnerMethod, "configure");
            testCase.verifyTrue(setting.ScopeSpan.isKnown());
            testCase.verifyNotEmpty(setting.InitializationScopeId);
        end

        function helperReturnKeepsLaterCallerInitializationReachable(testCase)
            % helperReturnKeepsLaterCallerInitializationReachable Continue insertion planning after a callee returns.
            [original, ~] = testCase.helperFixture(false);
            source = replace(original.OriginalText, "app.Control = uidropdown(app.UIFigure);", ...
                "app.Control = uidropdown(app.UIFigure);" + sprintf("\r\n") + "return;");
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            component = document.getComponentByName("Control");
            component.setProperty("Value", 20);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(plan.Placements.OwnerMethod, "configure");
            testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 20);
        end

        function repeatedHelpersUseTheFinalUniqueCallSite(testCase)
            % repeatedHelpersUseTheFinalUniqueCallSite Avoid inserting one source setting into multiple execution visits.
            [document, component] = testCase.helperFixture(true);
            component.setProperty("Value", 20);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(plan.Placements.OwnerMethod, "PlacementApp");
            testCase.verifyNumElements(plan.Component.getSettings("Value"), 1);
        end

        function trailingFactoryCommentsKeepTheirOriginalLine(testCase)
            % trailingFactoryCommentsKeepTheirOriginalLine Do not attach an existing trailing comment to a new assignment.
            [document, component] = testCase.fixture("app.Control = uislider(app.UIFigure); % creation note");
            component.setProperty("Value", 75);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifySubstring(plan.Document.OriginalText, ...
                "uislider(app.UIFigure); % creation note" + sprintf("\r\n") + "app.Control.Value = 75;");
        end

        function multilineConstructorArgumentsRetainOpaqueAndCommentTokens(testCase)
            % multilineConstructorArgumentsRetainOpaqueAndCommentTokens Edit only the inserted argument text.
            creation = ["app.Control = uidropdown(app.UIFigure, ... % factory", ...
                "    'Items', {'A','B'}, ... % labels", "    'ItemsData', [10 20] ... % data", "    );"];
            [document, component] = testCase.fixture(creation);
            component.setProperty("Value", 20);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifyEqual(plan.Placements.Method, "nameValue");
            testCase.verifySubstring(plan.Document.OriginalText, "... % factory");
            testCase.verifySubstring(plan.Document.OriginalText, "... % labels");
            testCase.verifySubstring(plan.Document.OriginalText, "... % data");
            testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 20);
        end

        function opaqueNamedArgumentsAreKeptWithoutEvaluation(testCase)
            % opaqueNamedArgumentsAreKeptWithoutEvaluation Do not rebuild a constructor from its safe literal subset.
            [document, component] = testCase.fixture( ...
                "app.Control = uidropdown(app.UIFigure, Items=[""A"" ""B""], ItemsData=[10 20], Tooltip=""Opaque"" + ""Hint"");");
            component.setProperty("Value", 20);
            plan = macd.source.PropertyInsertionPlanner.plan(document, component, testCase.Registry);
            testCase.verifySubstring(plan.Document.OriginalText, "Tooltip=""Opaque"" + ""Hint""");
            testCase.verifyEqual(plan.Component.getProperty("Tooltip").SourceExpression, """Opaque"" + ""Hint""");
            testCase.verifyEqual(plan.Component.getProperty("Value").LiteralValue, 20);
        end
    end

    methods (Access = private)
        function [document, component] = fixture(testCase, initialization)
            % fixture Parse owned initialization text without running the represented app.
            arguments (Input)
                testCase (1, 1) PropertyInsertionPlannerTest
                initialization (1, :) string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
            end
            source = strjoin(["classdef PlacementApp < matlab.apps.AppBase", "properties", ...
                "UIFigure matlab.ui.Figure", "Control", "end", "methods", ...
                "function app = PlacementApp", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                initialization, "end", "end", "end"], sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            component = document.getComponentByName("Control");
        end

        function [document, component] = helperFixture(testCase, repeated)
            % helperFixture Keep helper declaration order different from the constructor call trace.
            arguments (Input)
                testCase (1, 1) PropertyInsertionPlannerTest
                repeated (1, 1) logical
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
            end
            calls = ["createComponents(app);", "configure(app);"];
            if repeated, calls(end + 1) = "configure(app);"; end
            source = strjoin(["classdef PlacementApp < matlab.apps.AppBase", "properties", ...
                "UIFigure matlab.ui.Figure", "Control", "end", "methods", ...
                "function app = PlacementApp", calls, "end", ...
                "function configure(app)", "app.Control.Items = [""A"" ""B""];", ...
                "app.Control.ItemsData = [10 20];", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Control = uidropdown(app.UIFigure);", "end", "end", "end"], sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            component = document.getComponentByName("Control");
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
