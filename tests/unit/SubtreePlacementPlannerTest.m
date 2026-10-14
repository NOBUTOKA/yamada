classdef (TestTags = {'fast', 'model', 'gridOverlay'}) SubtreePlacementPlannerTest < matlab.unittest.TestCase
    % SubtreePlacementPlannerTest Verify destination and layout conversion planning.
    %   These tests exercise grid spans and failure atomicity without preview UI.

    methods (Test)
        function absolutePositionIsPreservedWithOptionalOffset(testCase)
            % absolutePositionIsPreservedWithOptionalOffset Keep parent-local geometry deterministic.
            [document, registry, left, right, leaf] = SubtreePlacementPlannerTest.fixture();
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            before = leaf.getProperty("Position").LiteralValue;
            plan = macd.model.SubtreePlacementPlanner.prepare(document, snapshot, right.Id, registry, leaf.Id, [], [10 20]);
            testCase.verifyEqual(plan.ParentId, right.Id);
            testCase.verifyEqual(plan.Changes.Value, before + [10 20 0 0]);
            testCase.verifyEqual(leaf.ParentId, left.Id);
            testCase.verifyEqual(leaf.getProperty("Position").LiteralValue, before);
        end

        function rejectsCyclesRootAndInvalidParent(testCase)
            % rejectsCyclesRootAndInvalidParent Check root and construction parent restrictions.
            [document, registry, left, ~, leaf] = SubtreePlacementPlannerTest.fixture();
            snapshot = macd.model.SubtreeSnapshot(document, left.Id);
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, leaf.Id, registry, ...
                string({snapshot.Records.Id})), "macd:SubtreePlacementPlanner:CyclicParent");
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, leaf.Id, registry), ...
                "macd:SubtreePlacementPlanner:InvalidParent");
            snapshot = macd.model.SubtreeSnapshot(document, document.RootComponentId);
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, left.Id, registry), ...
                "macd:SubtreePlacementPlanner:RootOperation");
        end

        function absoluteToGridFindsFreeCellAndRemovesPosition(testCase)
            % absoluteToGridFindsFreeCellAndRemovesPosition Choose a free cell without altering tracks.
            [document, registry, ~, right, leaf] = SubtreePlacementPlannerTest.fixture();
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            grid.setProperty("RowHeight", {"1x", "1x"});
            grid.setProperty("ColumnWidth", {"1x", "1x"});
            existing = document.insertComponent(registry, "uilabel", grid.Id);
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            plan = macd.model.SubtreePlacementPlanner.prepare(document, snapshot, grid.Id, registry, leaf.Id);
            testCase.verifyEqual(plan.Changes(1).Value, 1);
            testCase.verifyEqual(plan.Changes(2).Value, 2);
            testCase.verifyEqual(plan.Changes(3).Path, "Position");
            testCase.verifyTrue(plan.Changes(3).Remove);
            testCase.verifyEqual(existing.getProperty("Layout.Column").LiteralValue, 1);
        end

        function gridToGridPreservesSpanAndRejectsFullDestination(testCase)
            % gridToGridPreservesSpanAndRejectsFullDestination Preserve span extent and reject no-space moves.
            [document, registry, left, right] = SubtreePlacementPlannerTest.fixture();
            first = document.insertComponent(registry, "uigridlayout", left.Id);
            second = document.insertComponent(registry, "uigridlayout", right.Id);
            second.setProperty("RowHeight", {"1x", "1x"});
            second.setProperty("ColumnWidth", {"1x", "1x"});
            leaf = document.insertComponent(registry, "uilabel", first.Id);
            leaf.setProperty("Layout.Row", [1 2]);
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            plan = macd.model.SubtreePlacementPlanner.prepare(document, snapshot, second.Id, registry, leaf.Id);
            testCase.verifyEqual(plan.Changes(1).Value, [1 2]);
            occupied = document.insertComponent(registry, "uilabel", second.Id);
            occupied.setProperty("Layout.Row", [1 2]);
            occupied.setProperty("Layout.Column", [1 2]);
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, second.Id, registry, leaf.Id), ...
                "macd:SubtreePlacementPlanner:NoSpace");
        end

        function gridToAbsoluteRequiresVerifiedGeometry(testCase)
            % gridToAbsoluteRequiresVerifiedGeometry Require explicit geometry rather than guessing grid pixels.
            [document, registry, left, right] = SubtreePlacementPlannerTest.fixture();
            grid = document.insertComponent(registry, "uigridlayout", left.Id);
            leaf = document.insertComponent(registry, "uilabel", grid.Id);
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, right.Id, registry, leaf.Id), ...
                "macd:SubtreePlacementPlanner:MissingGeometry");
            plan = macd.model.SubtreePlacementPlanner.prepare(document, snapshot, right.Id, registry, leaf.Id, [5 6 80 22]);
            testCase.verifyEqual(plan.Changes(end).Value, [5 6 80 22]);
            testCase.verifyTrue(all([plan.Changes(1:2).Remove]));
        end

        function resolvesGridConstructionAndCatalogDefaults(testCase)
            % resolvesGridConstructionAndCatalogDefaults Resolve tracks without requiring preview controls.
            [document, registry, ~, right, leaf] = SubtreePlacementPlannerTest.fixture();
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            plan = macd.model.SubtreePlacementPlanner.prepare(document, snapshot, grid.Id, registry, leaf.Id);
            testCase.verifyEqual([plan.Changes(1:2).Value], [1 1]);
            grid.CreationArguments = {[1 3]};
            existing = document.insertComponent(registry, "uilabel", grid.Id);
            existing.setProperty("Layout.Column", [1 2]);
            plan = macd.model.SubtreePlacementPlanner.prepare(document, snapshot, grid.Id, registry, leaf.Id);
            testCase.verifyEqual([plan.Changes(1:2).Value], [1 3]);
        end

        function requestedCellNeverFallsBackFromOccupiedRectangle(testCase)
            % requestedCellNeverFallsBackFromOccupiedRectangle Honor explicit drop cells without choosing another free cell.
            [document, registry, ~, right, leaf] = SubtreePlacementPlannerTest.fixture();
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            document.insertComponent(registry, "uilabel", grid.Id);
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            plan = macd.model.SubtreePlacementPlanner.prepare(document, snapshot, grid.Id, registry, leaf.Id, [], [0 0], [2 2]);
            testCase.verifyEqual(plan.Changes(1).Value, 2);
            testCase.verifyEqual(plan.Changes(2).Value, 2);
            history = document.HistoryIndex;
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, grid.Id, registry, ...
                leaf.Id, [], [0 0], [1 1]), "macd:SubtreePlacementPlanner:NoSpace");
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, grid.Id, registry, ...
                leaf.Id, [], [0 0], [3 1]), "macd:SubtreePlacementPlanner:InvalidCell");
        end

        function expressionPlacementRejectsWithoutMutation(testCase)
            % expressionPlacementRejectsWithoutMutation Do not silently discard unevaluated placement.
            [document, registry, left, right, leaf] = SubtreePlacementPlannerTest.fixture();
            leaf.getProperty("Position").setSourceExpression("computePosition(app)");
            snapshot = macd.model.SubtreeSnapshot(document, leaf.Id);
            testCase.verifyError(@() macd.model.SubtreePlacementPlanner.prepare(document, snapshot, right.Id, registry, leaf.Id), ...
                "macd:SubtreePlacementPlanner:ImplicitPlacement");
            testCase.verifyEqual(leaf.ParentId, left.Id);
            testCase.verifyEqual(leaf.getProperty("Position").SourceExpression, "computePosition(app)");
        end
    end

    methods (Static, Access = private)
        function [document, registry, left, right, leaf] = fixture()
            % fixture Create two compatible absolute containers and one movable leaf.
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                left (1, 1) macd.model.ComponentRecord
                right (1, 1) macd.model.ComponentRecord
                leaf (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("PlacementApp", registry);
            left = document.insertComponent(registry, "uipanel", document.RootComponentId);
            right = document.insertComponent(registry, "uipanel", document.RootComponentId);
            leaf = document.insertComponent(registry, "uilabel", left.Id);
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
