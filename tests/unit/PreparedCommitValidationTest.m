classdef (TestTags = {'fast', 'model', 'parser', 'generation'}) PreparedCommitValidationTest < matlab.unittest.TestCase
    % PreparedCommitValidationTest Verify complete pre-commit results against independent parsing and full validation.
    methods (Test)
        function implicitGridValuesSurviveDistinctPreparedChanges(testCase)
            % implicitGridValuesSurviveDistinctPreparedChanges Preserve absent source settings without repeating grid resolution.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(sourceFixture(), registry);
            second = document.getComponentByName("Second");
            testCase.verifyEmpty(second.getProperty("Layout.Row"));
            resolved = document.getEffectivePropertyStates(registry, second.Id);
            row = resolved(arrayfun(@(item) item.Definition.Path == "Layout.Row", resolved));
            testCase.verifyEqual(row.Resolution.EffectiveValue, 3);
            operations = {"First", "Tooltip", "first hint"; "Second", "FontSize", 19; "Second", "Text", "A longer button"};
            for index = 1:size(operations, 1)
                owner = document.getComponentByName(operations{index, 1});
                document.setProperty(owner.Id, operations{index, 2}, operations{index, 3}, registry);
                diagnostics = document.validatePropertyCommit(registry);
                document.getEffectivePropertyStates(registry, owner.Id);
                testCase.verifyEmpty(diagnostics);
                verifyIndependent(testCase, document, registry);
                testCase.verifyEmpty(second.getProperty("Layout.Row"));
            end
        end

        function partialParsingNeverProvidesAFullLoadProof(testCase)
            % partialParsingNeverProvidesAFullLoadProof Require established validation for components outside a limited parse.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(sourceFixture(), registry, "", "Second");
            owner = document.getComponentByName("Second");
            document.setProperty(owner.Id, "Tooltip", "limited", registry);
            document.validatePropertyCommit(registry);
            verifyIndependent(testCase, document, registry);
        end

        function layoutChangesAndExternalWritesRetainValidation(testCase)
            % layoutChangesAndExternalWritesRetainValidation Recompute affected configuration and reject stale baseline proofs.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(sourceFixture(), registry);
            grid = document.getComponentByName("Grid");
            document.setProperty(grid.Id, "RowHeight", {100, 120, 140}, registry);
            document.validatePropertyCommit(registry);
            verifyIndependent(testCase, document, registry);
            document.Metadata.OtherWriter = true;
            testCase.verifyEqual(document.validatePropertyCommit(registry), ...
                macd.validation.ModelValidator.validate(document, registry));
            verifyIndependent(testCase, document, registry);
        end

        function cachedFormattingMatchesReferenceAtEveryNeighbor(testCase)
            % cachedFormattingMatchesReferenceAtEveryNeighbor Preserve lexical boundaries, comments and multiline constructors.
            ending = string(sprintf("\r\n"));
            source = strjoin(["app.A = uilabel(app.UIFigure, ...", "    'Text', 'A'); % comment", ...
                "app.A.Tooltip = 'hint';", "app.B = uibutton(app.UIFigure);"], ending);
            analysis = macd.source.SourceAnalysis(source);
            statements = analysis.Statements; spans = [statements.Span];
            for boundary = 0:strlength(source)
                [before, after] = analysis.statementNeighbors(boundary);
                testCase.verifyEqual(before, find([spans.EndOffset] <= boundary, 1, "last"));
                testCase.verifyEqual(after, find([spans.StartOffset] > boundary, 1));
            end
            anchor = strfind(source, "app.B") - 1;
            edits = struct("Start", anchor + 1, "End", anchor, "Text", "app.C = uilabel(app.UIFigure);" + ending);
            expected = macd.source.SourceFormatting.separateComponents(source, edits);
            actual = macd.source.SourceFormatting.separateComponents(source, edits, analysis);
            testCase.verifyEqual(actual, expected);
            testCase.verifyError(@() macd.source.SourceFormatting.separateComponents(source + "x", edits, analysis), ...
                "macd:SourceFormatting:StaleAnalysis");
        end
    end
end

function verifyIndependent(testCase, document, registry)
% verifyIndependent Compare all effective states with fresh full parsing rather than reusing candidate caches.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
expected = macd.source.AppSourceParser.parseText(document.CurrentText, registry);
for owner = document.Components
    actual = document.getEffectivePropertyStates(registry, owner.Id);
    fresh = expected.getEffectivePropertyStates(registry, expected.getComponentByName(owner.Name).Id);
    testCase.verifyEqual(arrayfun(@(item) item.Definition.Path, actual), arrayfun(@(item) item.Definition.Path, fresh));
    for index = 1:numel(actual)
        for field = ["EffectiveValue", "IsKnown", "IsEditable", "ReadOnlyReason", "ExplicitKind"]
            testCase.verifyEqual(actual(index).Resolution.(field), fresh(index).Resolution.(field), owner.Name + "." + actual(index).Definition.Path);
        end
    end
end
end

function source = sourceFixture()
% sourceFixture Define a source-owned child whose implicit native placement follows an earlier explicit move.
arguments (Output)
    source (1, 1) string
end
source = strjoin(["classdef PreparedFixture < handle", "properties", "UIFigure matlab.ui.Figure", ...
    "Grid matlab.ui.container.GridLayout", "First matlab.ui.control.Button", "Second matlab.ui.control.Button", ...
    "end", "methods", "function app = PreparedFixture()", "app.UIFigure = uifigure();", ...
    "app.Grid = uigridlayout(app.UIFigure, [2 2]);", "app.First = uibutton(app.Grid);", ...
    "app.First.Layout.Row = 2;", "app.First.Layout.Column = 2;", "app.Second = uibutton(app.Grid);", ...
    "end", "end", "end"], string(sprintf("\r\n")));
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
