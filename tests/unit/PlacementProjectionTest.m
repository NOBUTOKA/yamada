classdef (TestTags = {'fast', 'model', 'gridOverlay'}) PlacementProjectionTest < matlab.unittest.TestCase
    % PlacementProjectionTest Verify shared grid-coordinate reads preserve placement safety and independence.
    %   No application or callback is executed; all fixtures are editor-owned model records.
    properties (TestParameter)
        % Depth - Number of nested destination grids used for occupancy checks.
        Depth = {1, 8}
    end
    methods (Test)
        function destinationsShareOneValidatedHierarchy(testCase, Depth)
            % destinationsShareOneValidatedHierarchy Bound subtree captures across all candidate parents.
            [document, registry, source, destinations] = fixture(Depth);
            snapshot = yamada.model.SubtreeSnapshot(document, source.Id);
            plans = struct([]);
            for index = 1:numel(destinations)
                prepared = yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, ...
                    destinations(index).Id, registry, source.Id);
                if isempty(plans), plans = prepared; else, plans(end + 1) = prepared; end %#ok<AGROW>
            end
            for index = 1:numel(plans)
                row = plans(index).Changes(string({plans(index).Changes.Path}) == "Layout.Row");
                column = plans(index).Changes(string({plans(index).Changes.Path}) == "Layout.Column");
                testCase.verifyEqual(row.Value, 1);
                testCase.verifyEqual(column.Value, 2);
            end
            expected = plans(1);
            plans(1).Changes(1).Value = 99;
            testCase.verifyNotEqual(plans(1), expected);
            again = yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, destinations(1).Id, registry, source.Id);
            testCase.verifyEqual(again, expected);
        end

        function coordinateAndCatalogChangesInvalidateSharedValues(testCase, Depth)
            % coordinateAndCatalogChangesInvalidateSharedValues Recompute coordinates after live writes and catalog updates.
            [document, registry, source, destinations] = fixture(Depth);
            snapshot = yamada.model.SubtreeSnapshot(document, source.Id);
            parent = destinations(1);
            child = document.getComponent(parent.Children(1));
            yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, parent.Id, registry, source.Id);
            child.setProperty("Layout.Column", 2);
            changed = yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, parent.Id, registry, source.Id);
            column = changed.Changes(string({changed.Changes.Path}) == "Layout.Column");
            testCase.verifyEqual(column.Value, 1);
            registry.register(registry.get("uilabel"));
            refreshed = yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, parent.Id, registry, source.Id);
            testCase.verifyEqual(refreshed, changed);
        end

        function unrelatedInvalidRecordsKeepLegacyPlacementResults(testCase, Depth)
            % unrelatedInvalidRecordsKeepLegacyPlacementResults Fall back locally instead of rejecting unrelated corruption.
            for kind = ["hierarchy", "live-data"]
                [document, registry, source, destinations, outsider] = fixture(Depth);
                snapshot = yamada.model.SubtreeSnapshot(document, source.Id);
                expected = yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, destinations(1).Id, registry, source.Id);
                if kind == "hierarchy"
                    outsider.addChild("missing-unrelated-child");
                else
                    outsider.Metadata.UnsafeValue = @() error("PlacementProjectionTest:Executed", "Must not run.");
                end
                actual = yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, destinations(1).Id, registry, source.Id);
                testCase.verifyEqual(actual, expected, kind);
            end
        end

        function invalidDestinationChildrenStillFail(testCase, Depth)
            % invalidDestinationChildrenStillFail Retain explicit-coordinate and subtree value restrictions.
            for kind = ["missing-coordinate", "live-data"]
                [document, registry, source, destinations] = fixture(Depth);
                snapshot = yamada.model.SubtreeSnapshot(document, source.Id);
                parent = destinations(1);
                yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, parent.Id, registry, source.Id);
                child = document.getComponent(parent.Children(1));
                if kind == "missing-coordinate"
                    child.removeProperty("Layout.Row");
                    expected = "yamada:SubtreePlacementPlanner:ImplicitPlacement";
                else
                    child.Metadata.UnsafeValue = @() error("PlacementProjectionTest:Executed", "Must not run.");
                    expected = "yamada:SubtreeSnapshot:UnsupportedValue";
                end
                testCase.verifyError(@() yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, ...
                    parent.Id, registry, source.Id), expected);
            end
        end
    end
end

function [document, registry, source, destinations, outsider] = fixture(depth)
% fixture Construct nested occupied grids and an absolute source outside their hierarchy.
arguments (Input)
    depth (1, 1) double {mustBeInteger, mustBePositive}
end
arguments (Output)
    document (1, 1) yamada.model.DocumentModel
    registry (1, 1) yamada.model.ComponentRegistry
    source (1, 1) yamada.model.ComponentRecord
    destinations (1, :) yamada.model.ComponentRecord
    outsider (1, 1) yamada.model.ComponentRecord
end
registry = yamada.model.ComponentRegistry.createDefault();
document = yamada.model.NewAppFactory.createEmpty("PlacementProjectionFixture", registry);
outsider = document.insertComponent(registry, "uipanel", document.RootComponentId);
source = document.insertComponent(registry, "uibutton", outsider.Id);
source.setProperty("Position", [10 10 80 22]);
parent = document.RootComponentId;
destinations = yamada.model.ComponentRecord.empty(1, 0);
for index = 1:depth
    grid = document.insertComponent(registry, "uigridlayout", parent);
    grid.setProperty("RowHeight", repmat({"1x"}, 1, 12));
    grid.setProperty("ColumnWidth", {"1x", "1x"});
    destinations(end + 1) = grid; %#ok<AGROW>
    parent = grid.Id;
end
for index = 1:4
    child = document.insertComponent(registry, "uilabel", parent);
    child.setProperty("Layout.Row", index);
    child.setProperty("Layout.Column", 1);
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
