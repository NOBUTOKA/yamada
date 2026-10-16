classdef (TestTags = {'fast', 'catalog', 'model', 'parser', 'generation'}) PropertyEffectBoundaryTest < matlab.unittest.TestCase
    % PropertyEffectBoundaryTest Verify missing effect evidence never proves native independence.
    %   Owned records and source fixtures exercise atomic refusal and exact preservation.

    methods (Test)
        function missingPolicyDoesNotProveLiteralEffectiveValue(testCase)
            % missingPolicyDoesNotProveLiteralEffectiveValue Keep legacy metadata readable and unresolved.
            component = macd.model.ComponentRecord("owned", "Owned", "uilabel", "matlab.ui.control.Label", "parsed");
            component.setProperty("Text", "literal");
            state = macd.model.PropertyStateResolver.resolve(component, macd.model.PropertyDefinition("Text"));
            testCase.verifyFalse(state.IsKnown);
            testCase.verifyEqual(state.RequestedValue, "literal");
            testCase.verifyEqual(state.ReasonCode, "unreviewed-effect");
        end

        function unknownSetterInvalidatesOnlyDeclaredAffectedPaths(testCase)
            % unknownSetterInvalidatesOnlyDeclaredAffectedPaths Preserve independent unaffected stored inputs.
            component = macd.model.ComponentRecord("owned", "Owned", "uilabel", "matlab.ui.control.Label", "parsed");
            component.setProperty("Text", "retained");
            component.setProperty("Geometry", [1 2]);
            definitions = [macd.model.PropertyDefinition("Text", [], false, true, ...
                struct("application", struct("effectStatus", "independent"))), ...
                macd.model.PropertyDefinition("Geometry", [], false, true, ...
                struct("application", struct("effectStatus", "unsupported", ...
                "affectedPaths", {{"Geometry"}}, "effectReason", "Native layout is not modeled.")))];
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyTrue(states(1).IsKnown);
            testCase.verifyEqual(states(1).EffectiveValue, "retained");
            testCase.verifyFalse(states(2).IsKnown);
            testCase.verifyEqual(states(2).Reason, "Native layout is not modeled.");
        end

        function laterCoupledSetterCannotEraseUnreviewedUpstream(testCase)
            % laterCoupledSetterCannotEraseUnreviewedUpstream Keep modeled values unknown despite later literals.
            component = macd.model.ComponentRecord("owned", "Owned", "uilabel", "matlab.ui.control.Label");
            component.setProperty("UnknownMode", 1);
            component.setProperty("Value", 7);
            component.setProperty("Text", "restored");
            definitions = [macd.model.PropertyDefinition("UnknownMode", [], false, true, ...
                struct("application", struct("effectStatus", "unsupported", "affectedPaths", {{"Value", "Text"}}, ...
                "effectReason", "An upstream mode is not modeled."))), ...
                macd.model.PropertyDefinition("Value", [], false, true, struct("application", struct("effectStatus", "modeled"))), ...
                macd.model.PropertyDefinition("Text", [], false, true, struct("application", struct("effectStatus", "independent")))];
            states = macd.model.PropertyStateResolver.resolve(component, definitions);
            testCase.verifyFalse(states(2).IsKnown);
            testCase.verifyFalse(states(2).IsEditable);
            testCase.verifyEqual(states(2).ReadOnlyReason, "An upstream mode is not modeled.");
            testCase.verifyTrue(states(3).IsKnown);
            testCase.verifyEqual(states(3).EffectiveValue, "restored");
        end

        function unresolvedInitializerPreservesSourceAndRejectsEdits(testCase)
            % unresolvedInitializerPreservesSourceAndRejectsEdits Do not treat warning-only reparsing as proof.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("externalSetup(app);");
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            text = states(arrayfun(@(item) item.Definition.Path == "Text", states)).Resolution;
            testCase.verifyFalse(text.IsKnown);
            testCase.verifyEqual(text.ReasonCode, "initialization-call");
            testCase.verifyFalse(text.IsEditable);
            testCase.verifyNotEmpty(text.ReadOnlyReason);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEqual(label.getProperty("Text").LiteralValue, "original");
        end

        function componentHandleCallIsAnExecutionBarrier(testCase)
            % componentHandleCallIsAnExecutionBarrier Do not assume an external handle consumer is pure.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(PropertyEffectBoundaryTest.fixture("externalSetup(app.Label);"), registry);
            label = document.getComponentByName("Label");
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyFalse(document.IsDirty);
        end

        function constructionCallbackKeepsEarlierComponentsUnknown(testCase)
            % constructionCallbackKeepsEarlierComponentsUnknown Preserve source and refuse unproven callback effects.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("");
            source = replace(source, "uilabel(app.UIFigure)", "uilabel(app.UIFigure, CreateFcn=@(~,~) externalSetup(app))");
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnresolvedLifecycleEffects);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
        end

        function unrecognizedSetterCannotDisappearFromProof(testCase)
            % unrecognizedSetterCannotDisappearFromProof Refuse edits when an uncataloged setter is present.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("app.Label.FutureProperty = 1;");
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnrecognizedSetter);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
        end

        function toggleToolStateDoesNotProveOtherComponentValues(testCase)
            % toggleToolStateDoesNotProveOtherComponentValues Treat programmatic callback execution as document-wide.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture(["app.Tools = uitoolbar(app.UIFigure);"; ...
                "app.Tool = uitoggletool(app.Tools, OnCallback=@(~,~) externalSetup(app));"; ...
                "app.Tool.State = 'on';"]);
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnresolvedExecutableEffects);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyFalse(document.IsDirty);
        end

        function externalHtmlEffectsDoNotProveOtherComponentValues(testCase)
            % externalHtmlEffectsDoNotProveOtherComponentValues Preserve external sources without running their code.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("app.HTML = uihtml(app.UIFigure, HTMLSource='owned.html');");
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(document.Metadata.HasUnresolvedExecutableEffects);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyFalse(document.IsDirty);
        end

        function assignedHandleConsumersRemainExecutionBarriers(testCase)
            % assignedHandleConsumersRemainExecutionBarriers Cover component assignments and opaque property expressions.
            registry = macd.model.ComponentRegistry.createDefault();
            for tail = ["app.Extra = externalSetup(app.Label);", ...
                    "app.Label.Text = externalText(app.UIFigure);"]
                document = macd.source.AppSourceParser.parseText(PropertyEffectBoundaryTest.fixture(tail), registry);
                label = document.getComponentByName("Label");
                testCase.verifyTrue(macd.model.PropertyStateResolver.hasUnresolvedExecution(document));
                testCase.verifyError(@() document.setProperty(label.Id, "Tooltip", "changed", registry), ...
                    "macd:DocumentModel:UnsafePropertyEdit");
                testCase.verifyFalse(document.IsDirty);
            end
        end

        function throwingConstructorCallsAreNotHiddenByLaterLiterals(testCase)
            % throwingConstructorCallsAreNotHiddenByLaterLiterals Preserve source while refusing unverified execution atomically.
            registry = macd.model.ComponentRegistry.createDefault();
            source = replace(PropertyEffectBoundaryTest.fixture(""), "app.Label = uilabel(app.UIFigure);", ...
                "app.Label = uilabel(app.UIFigure, Text=error('must not execute'));");
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            testCase.verifyTrue(macd.model.PropertyStateResolver.hasUnresolvedExecution(document));
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "changed", registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyError(@() document.copySubtree(label.Id, registry), ...
                "macd:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function hierarchyWritesInvalidateDestinationStateAndRejectEdits(testCase)
            % hierarchyWritesInvalidateDestinationStateAndRejectEdits Bound Parent and Children effects across modeled ownership.
            registry = macd.model.ComponentRegistry.createDefault();
            prefix = ["app.Left = uibuttongroup(app.UIFigure);"; "app.Right = uibuttongroup(app.UIFigure);"; ...
                "app.Moved = uiradiobutton(app.Left);"; "app.Other = uiradiobutton(app.Right);"];
            for tail = { [prefix; "app.Moved.Parent = app.Right;"; "app.Moved.Value = true;"]; ...
                    [prefix; "app.Right.Children = [app.Moved app.Other];"] }'
                source = PropertyEffectBoundaryTest.fixture(tail{1});
                document = macd.source.AppSourceParser.parseText(source, registry);
                other = document.getComponentByName("Other");
                states = document.getEffectivePropertyStates(registry, other.Id);
                value = states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution;
                testCase.verifyFalse(value.IsKnown);
                testCase.verifyFalse(value.IsEditable);
                testCase.verifyTrue(macd.model.PropertyStateResolver.hasUnresolvedExecution(document));
                testCase.verifyError(@() document.setProperty(other.Id, "Value", true, registry), ...
                    "macd:DocumentModel:UnsafePropertyEdit");
                testCase.verifyError(@() document.copySubtree(other.Id, registry), ...
                    "macd:DocumentModel:UnsafeSubtreeCopy");
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
                testCase.verifyEqual(document.HistoryIndex, 0);
                testCase.verifyFalse(document.IsDirty);
            end
        end

        function conditionalCreationDoesNotProveDefaultOrLaterValues(testCase)
            % conditionalCreationDoesNotProveDefaultOrLaterValues Keep uncertain object existence explicit.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("");
            source = replace(source, "app.Label = uilabel(app.UIFigure);", ...
                "if unknownFlag" + newline + "app.Label = uilabel(app.UIFigure);" + newline + "end");
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            text = states(arrayfun(@(item) item.Definition.Path == "Text", states)).Resolution;
            testCase.verifyFalse(text.IsKnown);
            testCase.verifyFalse(text.IsEditable);
            testCase.verifyEqual(text.ReasonCode, "source-creation");
            testCase.verifyEqual(text.RequestedValue, "original");
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
        end

        function callsWithoutAppArgumentsStillNeedAnEffectContract(testCase)
            % callsWithoutAppArgumentsStillNeedAnEffectContract Do not infer purity from a missing receiver argument.
            registry = macd.model.ComponentRegistry.createDefault();
            for tail = ["externalSetup();", "app.Label.Text = externalText();", "drawnow;"]
                document = macd.source.AppSourceParser.parseText(PropertyEffectBoundaryTest.fixture(tail), registry);
                label = document.getComponentByName("Label");
                testCase.verifyTrue(macd.model.PropertyStateResolver.hasUnresolvedExecution(document));
                testCase.verifyError(@() document.setProperty(label.Id, "Tooltip", "changed", registry), ...
                    "macd:DocumentModel:UnsafePropertyEdit");
            end
        end

        function ancestorResizeInvalidatesOnlyGeometry(testCase)
            % ancestorResizeInvalidatesOnlyGeometry Do not equate a stored child input with reflowed layout.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture(["app.Label.Position = [10 20 100 30];"; ...
                "app.UIFigure.Position = [50 50 800 600];"]);
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            position = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
            text = states(arrayfun(@(item) item.Definition.Path == "Text", states)).Resolution;
            testCase.verifyFalse(position.IsKnown);
            testCase.verifyEqual(position.ReasonCode, "ancestor-geometry");
            testCase.verifyTrue(text.IsKnown);
            source = replace(source, "app.UIFigure.Position =", "app.UIFigure.AutoResizeChildren = 'off';" + newline + "app.UIFigure.Position =");
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName("Label");
            states = document.getEffectivePropertyStates(registry, label.Id);
            position = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
            testCase.verifyTrue(position.IsKnown);
            testCase.verifyEqual(position.EffectiveValue, [10 20 100 30]);
        end

        function deferredCallbackRegistrationIsNotAnExecutionBarrier(testCase)
            % deferredCallbackRegistrationIsNotAnExecutionBarrier Keep anonymous callback bodies unexecuted.
            registry = macd.model.ComponentRegistry.createDefault();
            source = PropertyEffectBoundaryTest.fixture("callback = @(~,~) externalSetup(app);");
            document = macd.source.AppSourceParser.parseText(source, registry);
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
            source = strjoin(["classdef EffectApp < matlab.apps.AppBase"; "properties"; ...
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
