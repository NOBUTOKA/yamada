classdef (TestTags = {'fast', 'model', 'generation'}) PropertyEligibilityCarryTest < matlab.unittest.TestCase
    % PropertyEligibilityCarryTest Verify literal edits reuse only unchanged operation conditions.
    %   Catalog effects guard reuse; property names are not an optimization allowlist.
    properties (TestParameter)
        % Scenario - Representative literal families and layout placements.
        Scenario struct = struct("absoluteText", struct("Depth", 0, "Setting", "Tooltip"), ...
            "absoluteNumber", struct("Depth", 0, "Setting", "FontSize"), ...
            "absoluteColor", struct("Depth", 0, "Setting", "FontColor"), ...
            "nestedText", struct("Depth", 4, "Setting", "Text"), ...
            "nestedNumber", struct("Depth", 4, "Setting", "FontSize"))
    end
    methods (Test)
        function newLiteralSettingsKeepCachedConditions(testCase, Scenario)
            % newLiteralSettingsKeepCachedConditions Avoid source inspection for safe additions.
            % Guarantee: safe literal additions reuse cached command conditions.
            % Failure mode: every literal edit reinspects source to answer Copy and Delete availability, slowing editing.
            [document, registry, source] = fixture(Scenario.Depth);
            Setting = Scenario.Setting;
            document.validatePropertyCommit(registry);
            [copy, deletion] = conditions(document, source.Id, registry);
            testCase.assertEmpty(source.getProperty(string(Setting)));
            value = "Updated setting";
            if Setting == "FontSize", value = 17; end
            if Setting == "FontColor", value = [0.1 0.2 0.3]; end
            document.setProperty(source.Id, string(Setting), value, registry);
            document.validatePropertyCommit(registry);
            [actualCopy, actualDelete] = conditions(document, source.Id, registry);
            testCase.verifyEqual(actualCopy, copy);
            testCase.verifyEqual(actualDelete, deletion);
            independent = document.structuralCandidate(registry);
            [expectedCopy, expectedDelete] = conditions(independent, source.Id, registry);
            testCase.verifyEqual(actualCopy, expectedCopy);
            testCase.verifyEqual(actualDelete, expectedDelete);
        end

    end
end

function [copy, deletion] = conditions(document, id, registry)
% conditions Read independent immutable command and destination answers for one component.
arguments (Input)
    document (1, 1) yamada.model.DocumentModel
    id (1, 1) string
    registry (1, 1) yamada.model.ComponentRegistry
end
arguments (Output)
    copy (1, 1) struct
    deletion (1, 1) struct
end
copy = yamada.model.DocumentEditAvailability.copying(document, id, registry);
deletion = yamada.model.DocumentEditAvailability.deletion(document, id, registry);
end

function [document, registry, source] = fixture(depth)
% fixture Parse an absolute or nested-grid label and a separate destination hierarchy.
arguments (Input)
    depth (1, 1) double {mustBeInteger, mustBeNonnegative}
end
arguments (Output)
    document (1, 1) yamada.model.DocumentModel
    registry (1, 1) yamada.model.ComponentRegistry
    source (1, 1) yamada.model.ComponentRecord
end
registry = yamada.model.ComponentRegistry.createDefault();
document = yamada.model.NewAppFactory.createEmpty("EligibilityCarryFixture", registry);
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
text = yamada.source.NewAppGenerator(registry).generate(document);
document = yamada.source.AppSourceParser.parseText(text, registry);
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
