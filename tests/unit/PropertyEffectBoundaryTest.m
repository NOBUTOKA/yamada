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
