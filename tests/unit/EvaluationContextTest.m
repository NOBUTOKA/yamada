classdef (TestTags = {'fast', 'model', 'generation'}) EvaluationContextTest < matlab.unittest.TestCase
    % EvaluationContextTest Verify exact-input caching without shared mutable results.
    %   Direct changes and history branching must not reuse an obsolete evaluation.
    methods (Test)
        function detectsDirectEntryChangesWithoutHistory(testCase)
            % detectsDirectEntryChangesWithoutHistory Compare current values even outside document commands.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            label.setProperty("FontSize", 13);
            context = document.evaluationContext(registry);
            context.remember("sample", struct("value", 13));
            [value, found] = context.lookup("sample");
            testCase.verifyTrue(found);
            testCase.verifyEqual(value.value, 13);
            label.getProperty("FontSize").setLiteral(17);
            testCase.verifyFalse(context.matches(document, registry));
            replacement = document.evaluationContext(registry);
            [~, found] = replacement.lookup("sample");
            testCase.verifyFalse(found);
        end

        function derivedOutputsDoNotInvalidateInputs(testCase)
            % derivedOutputsDoNotInvalidateInputs Exclude generated text and display diagnostics.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            document.GeneratedText = "derived output";
            document.Diagnostics = macd.model.Diagnostic("example", "warning", "Derived diagnostic.");
            testCase.verifyTrue(context.matches(document, registry));
            document.Metadata.DirectInput = 1;
            testCase.verifyFalse(context.matches(document, registry));
        end

        function doesNotExposeSharedConfigurationHandles(testCase)
            % doesNotExposeSharedConfigurationHandles Copy a cached plan for each mutable caller.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            context.rememberConfiguration("plan", document);
            [first, found] = context.configuration("plan", "UIFigure");
            testCase.verifyTrue(found);
            first.Component.setProperty("Name", "Changed privately");
            [second, found] = context.configuration("plan", "UIFigure");
            testCase.verifyTrue(found);
            testCase.verifyNotEqual(second.Component.getProperty("Name").LiteralValue, "Changed privately");
        end

        function liveMetadataBypassesCache(testCase)
            % liveMetadataBypassesCache Do not assume unrecognized mutable metadata is immutable.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            document.Metadata.Live = containers.Map("a", 1);
            context = document.evaluationContext(registry);
            context.remember("sample", 1);
            [~, found] = context.lookup("sample");
            testCase.verifyFalse(found);
            testCase.verifyFalse(context.matches(document, registry));
        end

        function registryChangesInvalidateContext(testCase)
            % registryChangesInvalidateContext Detect registration even when its values are equal.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            context = document.evaluationContext(registry);
            registry.register(registry.get("uilabel"));
            testCase.verifyFalse(context.matches(document, registry));
        end

        function cyclicLiveMetadataBypassesWithoutRetainingHandles(testCase)
            % cyclicLiveMetadataBypassesWithoutRetainingHandles Do not recursively snapshot arbitrary model references.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            root = document.getComponent(document.RootComponentId);
            root.Metadata.Live = root;
            context = document.evaluationContext(registry);
            [inputs, safe] = context.inputs();
            testCase.verifyFalse(safe);
            testCase.verifyEmpty(fieldnames(inputs));
            testCase.verifyFalse(context.matches(document, registry));
            root.Metadata = struct();
        end

        function historyBranchAndSourceConventionsInvalidateContext(testCase)
            % historyBranchAndSourceConventionsInvalidateContext Never identify input by history index alone.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CacheFixture", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.setProperty(label.Id, "FontSize", 17, registry);
            previous = document.evaluationContext(registry);
            previous.remember("sample", 17);
            index = document.HistoryIndex;
            document.undo();
            document.setProperty(label.Id, "FontSize", 21, registry);
            testCase.verifyEqual(document.HistoryIndex, index);
            testCase.verifyFalse(previous.matches(document, registry));
            current = document.evaluationContext(registry);
            document.LineEnding = "LF";
            testCase.verifyFalse(current.matches(document, registry));
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
