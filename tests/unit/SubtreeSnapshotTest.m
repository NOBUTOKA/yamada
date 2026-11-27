classdef (TestTags = {'fast', 'model'}) SubtreeSnapshotTest < matlab.unittest.TestCase
    % SubtreeSnapshotTest Verify hierarchy integrity and independent snapshot data.
    %   Tests cover stable traversal, source expressions, and rejected live values.

    methods (Test)
        function capturesParentFirstInChildOrder(testCase)
            % capturesParentFirstInChildOrder Preserve tree order regardless of collection order.
            % Guarantee: snapshots list parents before children in sibling order.
            % Failure mode: records follow collection order, so Paste recreates children before their parents.
            [document, panel, nested, leaf] = SubtreeSnapshotTest.fixture();
            sibling = document.insertComponent(yamada.model.ComponentRegistry.createDefault(), ...
                "uilabel", panel.Id);
            snapshot = yamada.model.SubtreeSnapshot(document, panel.Id);
            testCase.verifyEqual(string({snapshot.Records.Id}), [panel.Id nested.Id leaf.Id sibling.Id]);
            testCase.verifyEqual(snapshot.RootId, panel.Id);
        end

        function remainsIndependentAfterOriginalEdits(testCase)
            % remainsIndependentAfterOriginalEdits Keep nested values and source expressions frozen.
            % Guarantee: a snapshot is a deep copy of names, nested metadata, and source expressions.
            % Failure mode: edits to the original after Copy change what Paste produces.
            [document, panel, ~, leaf] = SubtreeSnapshotTest.fixture();
            leaf.setProperty("Text", "Before");
            expression = leaf.setProperty("UserData", []);
            expression.setSourceExpression("app.SomeValue");
            leaf.Metadata = struct("Nested", {{struct("Value", "Before")}});
            snapshot = yamada.model.SubtreeSnapshot(document, panel.Id);
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

        % Guarantee: capture fails, without changing the document, on a missing root or an aliasing payload.
        % Failure mode: a missing component or nested handle produces a partial or shared snapshot.
        function rejectsMissingComponents(testCase)
            % rejectsMissingComponents Detect a root identity absent from the document.
            document = SubtreeSnapshotTest.fixture();
            testCase.verifyError(@() yamada.model.SubtreeSnapshot(document, "missing"), ...
                "yamada:SubtreeSnapshot:MissingComponent");
        end

        function rejectsHandlesInsideNestedPayloads(testCase)
            % rejectsHandlesInsideNestedPayloads Prevent clipboard aliasing through nested metadata.
            [document, panel, ~, leaf] = SubtreeSnapshotTest.fixture();
            leaf.Metadata = struct("Nested", {{struct("Live", panel)}});
            history = document.HistoryIndex;
            testCase.verifyError(@() yamada.model.SubtreeSnapshot(document, panel.Id), ...
                "yamada:SubtreeSnapshot:UnsupportedValue");
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyEqual(document.getComponent(leaf.Id), leaf);
        end
    end

    methods (Static, Access = private)
        % Guarantee: capturing a snapshot is read-only.
        % Failure mode: Copy marks the document dirty or adds a history step.
        function [document, panel, nested, leaf] = fixture()
            % fixture Create a three-level subtree using approved registry insertions.
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                panel (1, 1) yamada.model.ComponentRecord
                nested (1, 1) yamada.model.ComponentRecord
                leaf (1, 1) yamada.model.ComponentRecord
            end

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("SnapshotApp", registry);
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
