classdef (TestTags = {'fast', 'model', 'generation'}) CommittedPropertySourcePlanTest < matlab.unittest.TestCase
    % CommittedPropertySourcePlanTest Verify shared committed source without stale or mutable results.
    %   Successful edits keep their parsed configuration for state and Preview
    %   consumers while direct writes and catalog changes invalidate that input.

    methods (Test)
        function committedEditsDoNotReparseForStateConsumers(testCase)
            % committedEditsDoNotReparseForStateConsumers Reuse complete source for single and batch edits.
            registry = macd.model.ComponentRegistry.createDefault();
            for inGrid = [false true]
                for batch = [false true]
                    [document, label] = CommittedPropertySourcePlanTest.fixture(registry, inGrid);
                    original = document.OriginalText;
                    if batch
                        document.setPropertyBatch(label.Id, ...
                            macd.model.PropertyTransaction.singleChange("FontSize", 23), registry);
                    else
                        document.setProperty(label.Id, "FontSize", 23, registry);
                    end

                    % Count source parsing, independently of elapsed time or PC load.
                    profile clear;
                    profile on;
                    cleanup = onCleanup(@() profile('off'));
                    plan = macd.source.PropertySourcePlan.plan(document, label, registry);
                    states = document.getEffectivePropertyStates(registry, label.Id);
                    profile off;
                    info = profile('info');
                    clear cleanup
                    functions = info.FunctionTable;
                    parsing = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
                    testCase.verifyEqual(sum([functions(parsing).NumCalls]), 0, ...
                        "Committed source must not be parsed again by read-only state consumers.");
                    testCase.verifyEqual(plan.Component.getProperty("FontSize").LiteralValue, 23);
                    state = states(arrayfun(@(item) item.Definition.Path == "FontSize", states)).Resolution;
                    testCase.verifyTrue(state.IsKnown);
                    testCase.verifyEqual(state.EffectiveValue, 23);
                    testCase.verifyEqual(document.OriginalText, original);
                    testCase.verifyEqual(document.HistoryIndex, 1);
                    document.undo();
                    testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), original);
                end
            end
        end

        function committedPlansRemainIndependentAndInvalidateOnWrites(testCase)
            % committedPlansRemainIndependentAndInvalidateOnWrites Never borrow stale values or caller mutations.
            registry = macd.model.ComponentRegistry.createDefault();
            [document, label] = CommittedPropertySourcePlanTest.fixture(registry, true);
            document.setPropertyBatch(label.Id, ...
                macd.model.PropertyTransaction.singleChange("FontSize", 23), registry);
            first = macd.source.PropertySourcePlan.plan(document, label, registry);
            first.Component.setProperty("FontSize", 99);
            second = macd.source.PropertySourcePlan.plan(document, label, registry);
            testCase.verifyEqual(second.Component.getProperty("FontSize").LiteralValue, 23);
            testCase.verifyEqual(label.getProperty("FontSize").LiteralValue, 23);

            % Direct record writes and registry replacement both invalidate the shared plan.
            label.setProperty("FontSize", 31);
            [~, found] = document.evaluationContext(registry).configuration("combined", label.Name);
            testCase.verifyFalse(found);
            updated = macd.source.PropertySourcePlan.plan(document, label, registry);
            testCase.verifyEqual(updated.Component.getProperty("FontSize").LiteralValue, 31);
            registry.register(registry.get("uilabel"));
            [~, found] = document.evaluationContext(registry).configuration("combined", label.Name);
            testCase.verifyFalse(found);
            updated = macd.source.PropertySourcePlan.plan(document, label, registry);
            testCase.verifyEqual(updated.Component.getProperty("FontSize").LiteralValue, 31);
            testCase.verifyEqual(document.HistoryIndex, 1);
        end
    end

    methods (Static, Access = private)
        function [document, label] = fixture(registry, inGrid)
            % fixture Create parsed controls with no explicit font setting in either parent layout.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry
                inGrid (1, 1) logical
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                label (1, 1) macd.model.ComponentRecord
            end
            document = macd.model.NewAppFactory.createEmpty("CommittedSourceFixture", registry);
            parentId = document.RootComponentId;
            if inGrid
                grid = document.insertComponent(registry, "uigridlayout", parentId);
                parentId = grid.Id;
            end
            label = document.insertComponent(registry, "uilabel", parentId);
            name = label.Name;
            source = macd.source.NewAppGenerator(registry).generate(document);
            document = macd.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName(name);
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
