classdef (TestTags = {'fast', 'catalog', 'model', 'parser', 'generation'}) PropertyEffectBoundaryTest < matlab.unittest.TestCase
    % PropertyEffectBoundaryTest Separate unaudited editability from proven unsupported effects.
    %   Owned records and source fixtures exercise atomic refusal and exact preservation.

    methods (Test)
        function missingPolicyAllowsStoredLiteralWithoutClaimingIndependence(testCase)
            % missingPolicyAllowsStoredLiteralWithoutClaimingIndependence Retain legacy editability while keeping its audit status unknown.
            component = yamada.model.ComponentRecord("owned", "Owned", "uilabel", "matlab.ui.control.Label", "parsed");
            component.setProperty("Text", "literal");
            state = yamada.model.PropertyStateResolver.resolve(component, yamada.model.PropertyDefinition("Text"));
            testCase.verifyTrue(state.IsKnown);
            testCase.verifyTrue(state.IsEditable);
            testCase.verifyEqual(state.EffectStatus, "unknown");
            testCase.verifyEqual(state.RequestedValue, "literal");
            testCase.verifyEqual(state.EffectiveValue, "literal");
        end

        function unknownLiteralPreservesOtherStatesAndCatalogRestrictions(testCase)
            % unknownLiteralPreservesOtherStatesAndCatalogRestrictions Keep review status separate from product intent.
            component = yamada.model.ComponentRecord("owned", "Owned", "uilabel", "matlab.ui.control.Label");
            component.setProperty("Unreviewed", 2);
            definitions = [yamada.model.PropertyDefinition("Unreviewed"), ...
                yamada.model.PropertyDefinition("Text", "kept", true, true, ...
                struct("application", struct("effectStatus", "independent"))), ...
                yamada.model.PropertyDefinition("ReadOnly", 1, true, false), ...
                yamada.model.PropertyDefinition("Omitted", 1, true, true, struct("auditDisposition", "omitted"))];
            states = yamada.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyTrue(states(1).IsEditable);
            testCase.verifyEqual(states(1).EffectiveValue, 2);
            testCase.verifyEqual(states(2).EffectiveValue, "kept");
            testCase.verifyFalse(states(3).IsEditable);
            testCase.verifyFalse(states(4).IsEditable);
        end

        function unreviewedDateOptionsSupportEditCopyAndHistory(testCase)
            % unreviewedDateOptionsSupportEditCopyAndHistory Exercise both date options through document preflight.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture(["app.Date = uidatepicker(app.UIFigure);"; ...
                "app.Date.Position = [10 20 150 22];"]);
            source = replace(source, "Label matlab.ui.control.Label", ...
                "Label matlab.ui.control.Label" + newline + "Date matlab.ui.control.DatePicker");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            picker = document.getComponentByName("Date");
            dates = datetime(2026, 10, [17; 18]);
            document.setProperty(picker.Id, "DisabledDates", dates, registry);
            document.setProperty(picker.Id, "DisabledDaysOfWeek", [1 7], registry);
            emitted = yamada.source.RoundTripGenerator(registry).generate(document);
            parsed = yamada.source.AppSourceParser.parseText(emitted, registry);
            target = parsed.getComponentByName("Date");
            testCase.verifyEqual(target.getProperty("DisabledDates").LiteralValue, dates);
            testCase.verifyEqual(target.getProperty("DisabledDaysOfWeek").LiteralValue, [1 7]);
            snapshot = document.copySubtree(picker.Id, registry);
            testCase.verifyNotEmpty(snapshot);
            document.undo();
            testCase.verifyEmpty(document.getComponent(picker.Id).getProperty("DisabledDaysOfWeek"));
            document.redo();
            testCase.verifyEqual(document.getComponent(picker.Id).getProperty("DisabledDaysOfWeek").LiteralValue, [1 7]);
            checkpoint = yamada.model.SavedSourceCheckpoint(document, emitted, fullfile(tempdir, "EffectApp.m"), registry);
            testCase.verifyEqual(checkpoint.SourceText, emitted);
            document.setProperty(picker.Id, "DisabledDaysOfWeek", [2 6], registry);
            updated = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(updated, "app.Date.DisabledDaysOfWeek = [2 6];");
        end

        function unsupportedSetterInvalidatesOnlyDeclaredAffectedPaths(testCase)
            % unsupportedSetterInvalidatesOnlyDeclaredAffectedPaths Preserve independent unaffected stored inputs.
            component = yamada.model.ComponentRecord("owned", "Owned", "uilabel", "matlab.ui.control.Label", "parsed");
            component.setProperty("Text", "retained");
            component.setProperty("Geometry", [1 2]);
            definitions = [yamada.model.PropertyDefinition("Text", [], false, true, ...
                struct("application", struct("effectStatus", "independent"))), ...
                yamada.model.PropertyDefinition("Geometry", [], false, true, ...
                struct("application", struct("effectStatus", "unsupported", ...
                "affectedPaths", {{"Geometry"}}, "effectReason", "Native layout is not modeled.")))];
            states = yamada.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyTrue(states(1).IsKnown);
            testCase.verifyEqual(states(1).EffectiveValue, "retained");
            testCase.verifyFalse(states(2).IsKnown);
            testCase.verifyEqual(states(2).Reason, "Native layout is not modeled.");
        end

        function laterCoupledSetterCannotEraseUnreviewedUpstream(testCase)
            % laterCoupledSetterCannotEraseUnreviewedUpstream Keep modeled values unknown despite later literals.
            component = yamada.model.ComponentRecord("owned", "Owned", "uilabel", "matlab.ui.control.Label");
            component.setProperty("UnknownMode", 1);
            component.setProperty("Value", 7);
            component.setProperty("Text", "restored");
            definitions = [yamada.model.PropertyDefinition("UnknownMode", [], false, true, ...
                struct("application", struct("effectStatus", "unsupported", "affectedPaths", {{"Value", "Text"}}, ...
                "effectReason", "An upstream mode is not modeled."))), ...
                yamada.model.PropertyDefinition("Value", [], false, true, struct("application", struct("effectStatus", "modeled"))), ...
                yamada.model.PropertyDefinition("Text", [], false, true, struct("application", struct("effectStatus", "independent")))];
            states = yamada.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyFalse(states(2).IsKnown);
            testCase.verifyFalse(states(2).IsEditable);
            testCase.verifyEqual(states(2).ReadOnlyReason, "An upstream mode is not modeled.");
            testCase.verifyTrue(states(3).IsKnown);
            testCase.verifyEqual(states(3).EffectiveValue, "restored");
        end

        function unresolvedInitializerPreservesSourceAndPermitsOwnedEdits(testCase)
            % unresolvedInitializerPreservesSourceAndPermitsOwnedEdits Leave unknown-call effects to the source author.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("externalSetup(app);");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            text = states(arrayfun(@(item) item.Definition.Path == "Text", states)).Resolution;
            testCase.verifyTrue(text.IsKnown);
            testCase.verifyTrue(text.IsEditable);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            document.setProperty(label.Id, "Text", "changed", registry);
            testCase.verifyTrue(document.IsDirty);
            testCase.verifyEqual(label.getProperty("Text").LiteralValue, "changed");
            testCase.verifySubstring(yamada.source.RoundTripGenerator(registry).generate(document), "externalSetup(app);");
        end

        function componentHandleCallIsPreservedWithoutBlockingEdits(testCase)
            % componentHandleCallIsPreservedWithoutBlockingEdits Do not execute or infer effects of external consumers.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.source.AppSourceParser.parseText(PropertyEffectBoundaryTest.fixture("externalSetup(app.Label);"), registry);
            label = document.getComponentByName("Label");
            document.setProperty(label.Id, "Text", "changed", registry);
            testCase.verifyTrue(document.IsDirty);
        end

        function constructionCallbackKeepsEarlierComponentsUnknown(testCase)
            % constructionCallbackKeepsEarlierComponentsUnknown Preserve source and refuse unproven callback effects.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("");
            source = replace(source, "uilabel(app.UIFigure)", "uilabel(app.UIFigure, CreateFcn=@(~,~) externalSetup(app))");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnresolvedLifecycleEffects);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
        end

        function unrecognizedSetterCannotDisappearFromProof(testCase)
            % unrecognizedSetterCannotDisappearFromProof Refuse edits when an uncataloged setter is present.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("app.Label.FutureProperty = 1;");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnrecognizedSetter);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
        end

        function toggleToolStateDoesNotProveOtherComponentValues(testCase)
            % toggleToolStateDoesNotProveOtherComponentValues Treat programmatic callback execution as document-wide.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture(["app.Tools = uitoolbar(app.UIFigure);"; ...
                "app.Tool = uitoggletool(app.Tools, OnCallback=@(~,~) externalSetup(app));"; ...
                "app.Tool.State = 'on';"]);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnresolvedExecutableEffects);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyFalse(document.IsDirty);
        end

        function externalHtmlEffectsDoNotProveOtherComponentValues(testCase)
            % externalHtmlEffectsDoNotProveOtherComponentValues Preserve external sources without running their code.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("app.HTML = uihtml(app.UIFigure, HTMLSource='owned.html');");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnresolvedExecutableEffects);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyFalse(document.IsDirty);
        end

        function unknownStatementsAndPropertyExpressionsHaveSeparateContracts(testCase)
            % unknownStatementsAndPropertyExpressionsHaveSeparateContracts Keep expression-backed setter limits explicit.
            registry = yamada.model.ComponentRegistry.createDefault();
            for tail = ["app.Extra = externalSetup(app.Label);", ...
                    "app.Label.Text = externalText(app.UIFigure);"]
                document = yamada.source.AppSourceParser.parseText(PropertyEffectBoundaryTest.fixture(tail), registry);
                label = document.getComponentByName("Label");
                if startsWith(tail, "app.Label.Text")
                    testCase.verifyTrue(yamada.model.PropertyStateResolver.hasUnresolvedExecution(document));
                    testCase.verifyError(@() document.setProperty(label.Id, "Tooltip", "changed", registry), ...
                        "yamada:DocumentModel:UnsafePropertyEdit");
                    testCase.verifyFalse(document.IsDirty);
                else
                    testCase.verifyFalse(yamada.model.PropertyStateResolver.hasUnresolvedExecution(document));
                    document.setProperty(label.Id, "Tooltip", "changed", registry);
                    testCase.verifyTrue(document.IsDirty);
                end
            end
        end

        function throwingConstructorCallsAreNotHiddenByLaterLiterals(testCase)
            % throwingConstructorCallsAreNotHiddenByLaterLiterals Preserve source while refusing unverified execution atomically.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = replace(PropertyEffectBoundaryTest.fixture(""), "app.Label = uilabel(app.UIFigure);", ...
                "app.Label = uilabel(app.UIFigure, Text=error('must not execute'));");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(yamada.model.PropertyStateResolver.hasUnresolvedExecution(document));
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyError(@() document.copySubtree(label.Id, registry), ...
                "yamada:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function hierarchyWritesInvalidateDestinationStateAndRejectEdits(testCase)
            % hierarchyWritesInvalidateDestinationStateAndRejectEdits Bound Parent and Children effects across modeled ownership.
            registry = yamada.model.ComponentRegistry.createDefault();
            prefix = ["app.Left = uibuttongroup(app.UIFigure);"; "app.Right = uibuttongroup(app.UIFigure);"; ...
                "app.Moved = uiradiobutton(app.Left);"; "app.Other = uiradiobutton(app.Right);"];
            for tail = { [prefix; "app.Moved.Parent = app.Right;"; "app.Moved.Value = true;"]; ...
                    [prefix; "app.Right.Children = [app.Moved app.Other];"] }'
                source = PropertyEffectBoundaryTest.fixture(tail{1});
                document = yamada.source.AppSourceParser.parseText(source, registry);
                other = document.getComponentByName("Other");
                states = document.getEffectivePropertyStates(registry, other.Id);
                value = states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution;
                testCase.verifyFalse(value.IsKnown);
                testCase.verifyFalse(value.IsEditable);
                testCase.verifyTrue(yamada.model.PropertyStateResolver.hasUnresolvedExecution(document));
                testCase.verifyError(@() document.setProperty(other.Id, "Value", true, registry), ...
                    "yamada:DocumentModel:UnsafePropertyEdit");
                testCase.verifyError(@() document.copySubtree(other.Id, registry), ...
                    "yamada:DocumentModel:UnsafeSubtreeCopy");
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
                testCase.verifyEqual(document.HistoryIndex, 0);
                testCase.verifyFalse(document.IsDirty);
            end
        end

        function conditionalCreationDoesNotProveDefaultOrLaterValues(testCase)
            % conditionalCreationDoesNotProveDefaultOrLaterValues Keep uncertain object existence explicit.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("");
            source = replace(source, "app.Label = uilabel(app.UIFigure);", ...
                "if unknownFlag" + newline + "app.Label = uilabel(app.UIFigure);" + newline + "end");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            text = states(arrayfun(@(item) item.Definition.Path == "Text", states)).Resolution;
            testCase.verifyFalse(text.IsKnown);
            testCase.verifyFalse(text.IsEditable);
            testCase.verifyEqual(text.ReasonCode, "source-creation");
            testCase.verifyEqual(text.RequestedValue, "original");
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
        end

        function unknownCallsWithoutAppArgumentsAreUserOwned(testCase)
            % unknownCallsWithoutAppArgumentsAreUserOwned Preserve calls without claiming their effects are modeled.
            registry = yamada.model.ComponentRegistry.createDefault();
            for tail = ["externalSetup();", "app.Label.Text = externalText();", "drawnow;"]
                document = yamada.source.AppSourceParser.parseText(PropertyEffectBoundaryTest.fixture(tail), registry);
                label = document.getComponentByName("Label");
                if startsWith(tail, "app.Label.Text")
                    testCase.verifyTrue(yamada.model.PropertyStateResolver.hasUnresolvedExecution(document));
                    testCase.verifyError(@() document.setProperty(label.Id, "Tooltip", "changed", registry), ...
                        "yamada:DocumentModel:UnsafePropertyEdit");
                else
                    testCase.verifyFalse(yamada.model.PropertyStateResolver.hasUnresolvedExecution(document));
                    document.setProperty(label.Id, "Tooltip", "changed", registry);
                end
            end
        end

        function ancestorResizeInvalidatesOnlyGeometry(testCase)
            % ancestorResizeInvalidatesOnlyGeometry Do not equate a stored child input with reflowed layout.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture(["app.Label.Position = [10 20 100 30];"; ...
                "app.UIFigure.Position = [50 50 800 600];"]);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            position = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
            text = states(arrayfun(@(item) item.Definition.Path == "Text", states)).Resolution;
            testCase.verifyFalse(position.IsKnown);
            testCase.verifyEqual(position.ReasonCode, "ancestor-geometry");
            testCase.verifyTrue(text.IsKnown);
            source = replace(source, "app.UIFigure.Position =", "app.UIFigure.AutoResizeChildren = 'off';" + newline + "app.UIFigure.Position =");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            position = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
            testCase.verifyTrue(position.IsKnown);
            testCase.verifyEqual(position.EffectiveValue, [10 20 100 30]);
        end

        function deferredCallbackRegistrationIsNotAnExecutionBarrier(testCase)
            % deferredCallbackRegistrationIsNotAnExecutionBarrier Keep anonymous callback bodies unexecuted.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("callback = @(~,~) externalSetup(app);");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            document.setProperty(label.Id, "Text", "changed", registry);
            testCase.verifyTrue(document.IsDirty);
        end
    end

    methods (Static, Access = private)
        function source = fixture(tail)
            % fixture Return owned source without evaluating its initializer or callback.
            arguments (Input)
                tail string
            end
            arguments (Output)
                source (1, 1) string
            end
            source = strjoin(["classdef EffectApp < handle"; "properties"; ...
                "UIFigure matlab.ui.Figure"; "Label matlab.ui.control.Label"; "end"; ...
                "methods"; "function app = EffectApp"; "createComponents(app);"; "end"; ...
                "function createComponents(app)"; "app.UIFigure = uifigure(Visible='off');"; ...
                "app.Label = uilabel(app.UIFigure);"; "app.Label.Text = ""original"";"; ...
                reshape(tail, [], 1); "end"; "end"; "end"], newline) + newline;
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
