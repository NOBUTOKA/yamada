classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) LocalSourceProjectionTest < matlab.unittest.TestCase
    % LocalSourceProjectionTest Compare local execution and range projections with independent reference paths.
    methods (Test)
        function batchedRangesMatchScalarReference(testCase)
            % batchedRangesMatchScalarReference Cover insertion affinity, overlap, deletion, unknown and empty ranges.
            source = "abcdefghijklmnopqrstuvwx";
            edits = [edit(1, 0, "HEAD"), edit(5, 7, "REPLACEMENT"), edit(13, 15, ""), edit(25, 24, "TAIL")];
            batch = yamada.source.SourcePatchBatch(source, edits);
            spans = {yamada.model.SourceSpan.empty, yamada.model.SourceSpan()};
            for first = 1:strlength(source)
                for last = first:strlength(source)
                    spans{end + 1} = yamada.model.SourceSpan(first, last); %#ok<AGROW>
                end
            end
            [actual, flags] = batch.mapSpanCells(spans);
            for index = 1:numel(spans)
                [expected, valid] = batch.mapSpan(spans{index});
                testCase.verifyEqual(actual{index}, expected);
                testCase.verifyEqual(flags(index), valid);
            end
        end

        function helperTraceAndDiagnosticsSurviveLiteralChanges(testCase)
            % helperTraceAndDiagnosticsSurviveLiteralChanges Preserve calls, return boundaries and opaque diagnostics.
            source = traceSource();
            changed = replace(source, "app.A.Value = 1;", "app.A.Value = 123456;" + newline + "app.A.Tooltip = 'new';");
            verifyProjection(testCase, source, changed, "A", true);
            verifyProjection(testCase, changed, source, "A", true);
        end

        function unrelatedOrStructuralChangesRequireAnalysis(testCase)
            % unrelatedOrStructuralChangesRequireAnalysis Reject changes outside the proven target setting scope.
            source = traceSource();
            verifyProjection(testCase, source, replace(source, "app.B.Value = 2;", "app.B.Value = 200;"), "A", false);
            verifyProjection(testCase, source, replace(source, "observe(app.A);", "different(app.A);"), "A", false);
            verifyProjection(testCase, source, replace(source, "app.A.Value = 1;", "app.A.Value = other();"), "A", false);
        end

        function ambiguousHelperInsertionsRequireAnalysis(testCase)
            % ambiguousHelperInsertionsRequireAnalysis Do not invent one execution visit for a repeatedly called method.
            source = replace(traceSource(), "configure(app);", "configure(app);" + newline + "configure(app);");
            changed = replace(source, "app.A.Value = 1;", "app.A.Value = 1;" + newline + "app.A.Tooltip = 'new';");
            verifyProjection(testCase, source, changed, "A", false);
        end

        function rebinderUsesPriorTraceForOwnedLiteralReplacement(testCase)
            % rebinderUsesPriorTraceForOwnedLiteralReplacement Certify that the integrated path avoids global call analysis.
            registry = yamada.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            source = string(fileread(fullfile(root, "tests", "fixtures", "SmallPreviewFixtureApp.m")));
            document = yamada.source.AppSourceParser.parseText(source, registry);
            owner = document.getComponentByName("TopLeftLabel");
            span = owner.getSettings("Text").ValueSpan;
            batch = yamada.source.SourcePatchBatch(source, edit(span.StartOffset, span.EndOffset, "'Changed length'"));
            current = yamada.model.CurrentSourceState(source, document.sourceAnalysis()).withBatch(batch);
            [settings, ~, ~, execution] = yamada.model.SourceSettingRebinder.rebind(document, owner, current, batch, registry);
            testCase.verifyTrue(execution.ProjectedInitialization);
            testCase.verifyTrue(any(string({settings.Path}) == "Text"));
            % The trace must remain exact when read later with the same factory set.
            fresh = yamada.source.SourceAnalysis(batch.AfterText);
            offsets = zeros(1, 0);
            for item = document.Components
                [creation, valid] = batch.mapSpan(item.SourceSpans.Creation);
                testCase.assertTrue(valid);
                offsets(end + 1) = creation.StartOffset; %#ok<AGROW>
            end
            testCase.verifyEqual(execution.Trace, fresh.initialization(offsets));
        end

        function publishedRangesAndHistoryMatchIndependentParsing(testCase)
            % publishedRangesAndHistoryMatchIndependentParsing Check all owners after distinct insertions, replacements and history.
            registry = yamada.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            document = yamada.source.AppSourceParser.parseText(string(fileread(fullfile(root, ...
                "tests", "fixtures", "SmallPreviewFixtureApp.m"))), registry);
            operations = {"TopLeftLabel", "Text", "Longer replacement"; "CenterLabel", "Tooltip", "new"; ...
                "BottomRightButton", "FontSize", 21; "TopLeftLabel", "Tooltip", "another new setting"};
            for index = 1:size(operations, 1)
                owner = document.getComponentByName(operations{index, 1});
                document.setProperty(owner.Id, operations{index, 2}, operations{index, 3}, registry);
                verifyDocument(testCase, document, registry);
            end
            for index = 1:size(operations, 1)
                document.undo();
                verifyDocument(testCase, document, registry);
            end
            for index = 1:size(operations, 1)
                document.redo();
                verifyDocument(testCase, document, registry);
            end
        end
    end
end

function verifyDocument(testCase, document, registry)
% verifyDocument Compare source locations and evaluated settings against an independent full parse.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    document (1, 1) yamada.model.DocumentModel
    registry (1, 1) yamada.model.ComponentRegistry
end
parsed = yamada.source.AppSourceParser.parseText(document.CurrentText, registry);
for owner = document.Components
    other = parsed.getComponentByName(owner.Name);
    testCase.verifyEqual(owner.SourceSpans, other.SourceSpans);
    testCase.verifyEqual(numel(owner.Settings), numel(other.Settings));
    for index = 1:numel(owner.Settings)
        actual = owner.Settings(index);
        expected = other.Settings(index);
        for field = ["Path", "LiteralValue", "ValueKind", "SourceSpan", "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan", "Sequence", "IsCertain"]
            testCase.verifyEqual(actual.(field), expected.(field));
        end
    end
end
testCase.verifyEqual(document.evaluationContext(registry).inputs(), yamada.model.EvaluationContext(document, registry).inputs());
end

function verifyProjection(testCase, source, changed, name, supported)
% verifyProjection Compare the projected trace with independently compiled initialization execution.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    source (1, 1) string
    changed (1, 1) string
    name (1, 1) string
    supported (1, 1) logical
end
% Use minimal common prefix/suffix edits rather than replacing complete method structure.
a = char(source); b = char(changed); first = 1;
while first <= min(numel(a), numel(b)) && a(first) == b(first), first = first + 1; end
lastA = numel(a); lastB = numel(b);
while lastA >= first && lastB >= first && a(lastA) == b(lastB), lastA = lastA - 1; lastB = lastB - 1; end
batch = yamada.source.SourcePatchBatch(source, edit(first, lastA, string(b(first:lastB))));
before = yamada.source.SourceAnalysis(source);
after = before.withPatches(batch);
trace = before.initialization(factoryOffsets(before));
[actual, proven] = yamada.source.SourceInitializationProjection.project(before, after, batch, trace, name);
testCase.verifyEqual(proven, supported);
if proven
    expected = yamada.source.SourceAnalysis(changed);
    testCase.verifyEqual(actual, expected.initialization(factoryOffsets(expected)));
end
end

function offsets = factoryOffsets(analysis)
% factoryOffsets Identify the controlled fixture's registered factory statements.
arguments (Input)
    analysis (1, 1) yamada.source.SourceAnalysis
end
arguments (Output)
    offsets double
end
offsets = zeros(1, 0);
for statement = analysis.Statements
    if ~isempty(regexp(statement.Text, "^app\.\w+\s*=\s*(uifigure|uieditfield)\(", "once"))
        offsets(end + 1) = statement.Span.StartOffset; %#ok<AGROW>
    end
end
end

function source = traceSource()
% traceSource Exercise helper returns and an opaque boundary without executing application code.
arguments (Output)
    source (1, 1) string
end
source = strjoin(["classdef TraceApp < handle", "properties", "UIFigure", "A", "B", "end", "methods", ...
    "function app = TraceApp()", "app.UIFigure = uifigure();", "app.A = uieditfield(app.UIFigure, 'numeric');", ...
    "app.B = uieditfield(app.UIFigure, 'numeric');", "configure(app);", "app.B.Value = 2;", "end", ...
    "function configure(app)", "observe(app.A);", "app.A.Value = 1;", "end", "end", "end"], newline);
end

function value = edit(first, last, text)
% edit Build one exact inclusive source replacement or boundary insertion.
arguments (Input)
    first (1, 1) double
    last (1, 1) double
    text (1, 1) string
end
arguments (Output)
    value (1, 1) struct
end
value = struct("Start", first, "End", last, "Text", text);
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
