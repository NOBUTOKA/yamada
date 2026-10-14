classdef (TestTags = {'fast', 'model'}) SubtreeSnapshotTest < matlab.unittest.TestCase
    % SubtreeSnapshotTest Verify hierarchy integrity and independent snapshot data.
    %   Tests cover stable traversal, source expressions, and rejected live values.

    methods (Test)
        function capturesParentFirstInChildOrder(testCase)
            % capturesParentFirstInChildOrder Preserve tree order regardless of collection order.
            [document, panel, nested, leaf] = SubtreeSnapshotTest.fixture();
            sibling = document.insertComponent(macd.model.ComponentRegistry.createDefault(), ...
                "uilabel", panel.Id);
            snapshot = macd.model.SubtreeSnapshot(document, panel.Id);
            testCase.verifyEqual(string({snapshot.Records.Id}), [panel.Id nested.Id leaf.Id sibling.Id]);
            testCase.verifyEqual(snapshot.RootId, panel.Id);
        end

        function remainsIndependentAfterOriginalEdits(testCase)
            % remainsIndependentAfterOriginalEdits Keep nested values and source expressions frozen.
            [document, panel, ~, leaf] = SubtreeSnapshotTest.fixture();
            leaf.setProperty("Text", "Before");
            expression = leaf.setProperty("UserData", []);
            expression.setSourceExpression("app.SomeValue");
            leaf.Metadata = struct("Nested", {{struct("Value", "Before")}});
            snapshot = macd.model.SubtreeSnapshot(document, panel.Id);
            leaf.setProperty("Text", "After");
            expression.setSourceExpression("app.OtherValue");
            leaf.Metadata.Nested{1}.Value = "After";
            leaf.Name = "Renamed";
            record = snapshot.Records(3);
            testCase.verifyNotEqual(record.Name, leaf.Name);
            testCase.verifyEqual(record.Metadata.Nested{1}.Value, "Before");
            testCase.verifyEqual(record.Properties(end).SourceExpression, "app.SomeValue");
            testCase.verifyEqual(record.Properties(end - 1).LiteralValue, "Before");
        end

        function rejectsMissingAndUnlinkedChildren(testCase)
            % rejectsMissingAndUnlinkedChildren Detect incomplete parent-child relationships.
            [document, panel, nested] = SubtreeSnapshotTest.fixture();
            testCase.verifyError(@() macd.model.SubtreeSnapshot(document, "missing"), ...
                "macd:SubtreeSnapshot:MissingComponent");
            panel.removeChild(nested.Id);
            testCase.verifyError(@() macd.model.SubtreeSnapshot(document, panel.Id), ...
                "macd:SubtreeSnapshot:InvalidHierarchy");
        end

        function rejectsCyclesAndDuplicateIdentities(testCase)
            % rejectsCyclesAndDuplicateIdentities Reject traversal ambiguity before capture.
            [document, panel, ~, leaf] = SubtreeSnapshotTest.fixture();
            panel.ParentId = leaf.Id;
            leaf.addChild(panel.Id);
            testCase.verifyError(@() macd.model.SubtreeSnapshot(document, panel.Id), ...
                "macd:SubtreeSnapshot:InvalidHierarchy");
            [document, panel] = SubtreeSnapshotTest.fixture();
            document.Components(end + 1) = panel;
            testCase.verifyError(@() macd.model.SubtreeSnapshot(document, panel.Id), ...
                "macd:SubtreeSnapshot:InvalidHierarchy");
        end

        function rejectsHandlesInsideNestedPayloads(testCase)
            % rejectsHandlesInsideNestedPayloads Prevent clipboard aliasing through nested metadata.
            [document, panel, ~, leaf] = SubtreeSnapshotTest.fixture();
            leaf.Metadata = struct("Nested", {{struct("Live", panel)}});
            history = document.HistoryIndex;
            testCase.verifyError(@() macd.model.SubtreeSnapshot(document, panel.Id), ...
                "macd:SubtreeSnapshot:UnsupportedValue");
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyEqual(document.getComponent(leaf.Id), leaf);
        end

        function snapshotReadsDoNotDirtyDocument(testCase)
            % snapshotReadsDoNotDirtyDocument Leave saved state and history unchanged.
            [document, panel] = SubtreeSnapshotTest.fixture();
            document.markSaved();
            history = document.HistoryIndex;
            macd.model.SubtreeSnapshot(document, panel.Id);
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEqual(document.HistoryIndex, history);
        end
    end

    methods (Static, Access = private)
        function [document, panel, nested, leaf] = fixture()
            % fixture Create a three-level subtree using approved registry insertions.
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                panel (1, 1) macd.model.ComponentRecord
                nested (1, 1) macd.model.ComponentRecord
                leaf (1, 1) macd.model.ComponentRecord
            end

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("SnapshotApp", registry);
            panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
            nested = document.insertComponent(registry, "uipanel", panel.Id);
            leaf = document.insertComponent(registry, "uilabel", nested.Id);
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
