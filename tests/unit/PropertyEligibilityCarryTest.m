classdef (TestTags = {'fast', 'model', 'generation'}) PropertyEligibilityCarryTest < matlab.unittest.TestCase
    % PropertyEligibilityCarryTest Verify literal edits reuse only unchanged operation conditions.
    %   Catalog effects and measured geometry guard reuse; property names are not an optimization allowlist.
    properties (TestParameter)
        % Depth - Number of source-grid ancestors, or zero for absolute positioning.
        Depth = {0, 1, 4}
        % Setting - Distinct literal families used to exercise metadata-based eligibility reuse.
        Setting = {"Tooltip", "FontSize", "Text", "FontColor"}
    end
    methods (Test)
        function newLiteralSettingsKeepCachedConditions(testCase, Depth, Setting)
            % newLiteralSettingsKeepCachedConditions Avoid source inspection and placement preparation for safe additions.
            [document, registry, source] = fixture(Depth);
            document.validatePropertyCommit(registry);
            measured = [10 10 80 22];
            [copy, deletion, parents] = conditions(document, source.Id, registry, measured);
            testCase.assertEmpty(source.getProperty(string(Setting)));
            value = "Updated setting";
            if Setting == "FontSize", value = 17; end
            if Setting == "FontColor", value = [0.1 0.2 0.3]; end
            document.setProperty(source.Id, string(Setting), value, registry);
            document.validatePropertyCommit(registry);
            [actualCopy, actualDelete, actualParents] = conditions(document, source.Id, registry, measured);
            testCase.verifyEqual(actualCopy, copy);
            testCase.verifyEqual(actualDelete, deletion);
            testCase.verifyEqual(actualParents, parents);
            independent = document.structuralCandidate(registry);
            [expectedCopy, expectedDelete, expectedParents] = conditions(independent, source.Id, registry, measured);
            testCase.verifyEqual(actualCopy, expectedCopy);
            testCase.verifyEqual(actualDelete, expectedDelete);
            testCase.verifyEqual(orderParents(actualParents), orderParents(expectedParents));
        end

        function geometryStillGuardsReparentAnswers(testCase, Depth)
            % geometryStillGuardsReparentAnswers Recompute placement if the current measured source rectangle changes.
            [document, registry, source] = fixture(Depth);
            conditions(document, source.Id, registry, [10 10 80 22]);
            document.setProperty(source.Id, "Tooltip", "New hint", registry);
            measured = [12 15 100 28];
            actual = macd.model.DocumentEditAvailability.reparenting(document, source.Id, registry, measured);
            independent = document.structuralCandidate(registry);
            expected = macd.model.DocumentEditAvailability.reparenting(independent, source.Id, registry, measured);
            testCase.verifyEqual(orderParents(actual), orderParents(expected));
        end

        function placementInputsInvalidateConditions(testCase, Depth)
            % placementInputsInvalidateConditions Do not carry answers across stored placement changes.
            [document, registry, source] = fixture(Depth);
            document.validatePropertyCommit(registry);
            measured = [10 10 80 22];
            conditions(document, source.Id, registry, measured);
            if Depth == 0
                document.setProperty(source.Id, "Position", [12 15 100 28], registry);
            else
                document.setProperty(source.Id, "Layout.Column", 2, registry);
            end
            [copy, deletion, parents] = conditions(document, source.Id, registry, measured);
            independent = document.structuralCandidate(registry);
            [expectedCopy, expectedDelete, expectedParents] = conditions(independent, source.Id, registry, measured);
            testCase.verifyEqual(copy, expectedCopy);
            testCase.verifyEqual(deletion, expectedDelete);
            testCase.verifyEqual(orderParents(parents), orderParents(expectedParents));
        end

        function subsequentExternalWritesInvalidateTransferredAnswers(testCase, Depth)
            % subsequentExternalWritesInvalidateTransferredAnswers Reject stale caches after ownership or catalog changes.
            for kind = ["readonly", "metadata", "registry", "history"]
                [document, registry, source] = fixture(Depth);
                conditions(document, source.Id, registry, [10 10 80 22]);
                document.setProperty(source.Id, "Tooltip", "Transferred", registry);
                switch kind
                    case "readonly"
                        source.IsEditable = false;
                    case "metadata"
                        document.Metadata.OtherInput = true;
                    case "registry"
                        registry.register(registry.get("uilabel"));
                    case "history"
                        document.undo();
                end
                actual = macd.model.DocumentEditAvailability.copying(document, source.Id, registry);
                if kind == "readonly", testCase.verifyFalse(actual.Enabled); end
            end
        end

        function formerlyUnencodableValuesAreRechecked(testCase, Depth)
            % formerlyUnencodableValuesAreRechecked Do not carry a disabled Copy answer after repairing unsupported data.
            [document, registry, source] = fixture(Depth);
            source.setProperty("Text", categorical("Old unsupported text"));
            before = macd.model.DocumentEditAvailability.copying(document, source.Id, registry);
            testCase.assertFalse(before.Enabled);
            [~, found] = document.evaluationContext(registry).lookup("eligibility:copy:" + source.Id);
            testCase.assertTrue(found);
            document.setProperty(source.Id, "Text", "Recovered", registry);
            after = macd.model.DocumentEditAvailability.copying(document, source.Id, registry);
            testCase.verifyTrue(after.Enabled);
        end
    end
end

function states = orderParents(states)
% orderParents Align reference documents whose parent-first materialization changes record ordering.
arguments (Input)
    states struct
end
arguments (Output)
    states struct
end
[~, indices] = sort(string({states.Id}));
states = states(indices);
end

function [copy, deletion, parents] = conditions(document, id, registry, measured)
% conditions Read independent immutable command and destination answers for one component.
arguments (Input)
    document (1, 1) macd.model.DocumentModel
    id (1, 1) string
    registry (1, 1) macd.model.ComponentRegistry
    measured (1, 4) double
end
arguments (Output)
    copy (1, 1) struct
    deletion (1, 1) struct
    parents struct
end
copy = macd.model.DocumentEditAvailability.copying(document, id, registry);
deletion = macd.model.DocumentEditAvailability.deletion(document, id, registry);
parents = macd.model.DocumentEditAvailability.reparenting(document, id, registry, measured);
end

function [document, registry, source] = fixture(depth)
% fixture Parse an absolute or nested-grid label and a separate destination hierarchy.
arguments (Input)
    depth (1, 1) double {mustBeInteger, mustBeNonnegative}
end
arguments (Output)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
    source (1, 1) macd.model.ComponentRecord
end
registry = macd.model.ComponentRegistry.createDefault();
document = macd.model.NewAppFactory.createEmpty("EligibilityCarryFixture", registry);
left = document.insertComponent(registry, "uipanel", document.RootComponentId);
right = document.insertComponent(registry, "uipanel", document.RootComponentId);
destination = document.insertComponent(registry, "uigridlayout", right.Id);
destination.setProperty("RowHeight", {"1x", "1x"});
destination.setProperty("ColumnWidth", {"1x", "1x"});
parent = left.Id;
for index = 1:depth
    grid = document.insertComponent(registry, "uigridlayout", parent);
    grid.setProperty("RowHeight", {"1x", "1x"});
    grid.setProperty("ColumnWidth", {"1x", "1x"});
    parent = grid.Id;
end
source = document.insertComponent(registry, "uilabel", parent);
if depth > 0
    source.setProperty("Layout.Row", 1);
    source.setProperty("Layout.Column", 1);
else
    source.setProperty("Position", [10 10 80 22]);
end
name = source.Name;
text = macd.source.NewAppGenerator(registry).generate(document);
document = macd.source.AppSourceParser.parseText(text, registry);
source = document.getComponentByName(name);
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
