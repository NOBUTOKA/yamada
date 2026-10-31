classdef SourceAnalysis < handle
    % SourceAnalysis Share read-only lexical input and bounded source proofs.
    %   This derived cache retains source values only, without document, record,
    %   registry, or native UI references. Trace results are keyed by exact factory
    %   offsets and returned by value. Input application code is never executed.
    %
    %   Example:
    %       analysis = document.sourceAnalysis();
    %       statements = analysis.Statements;
    properties (SetAccess = private)
        % Statements - Immutable lexical statements with original source offsets.
        Statements macd.source.SourceStatement = macd.source.SourceStatement.empty
        % Layout - Value-only method and scope layout for the exact input source.
        Layout struct = struct()
    end

    properties (Access = private)
        Source string = ""
        TraceOffsets double = []
        Trace struct = struct()
        HasTrace logical = false
        CallbackDirectOffsets double = []
        HasCallbackIndex logical = false
        CallbackCreationOffsets double = []
        CallbackInsertion logical = false
        HasCallbackInsertion logical = false
        CallbackCandidates containers.Map
        StatementStarts double = []
        StatementEnds double = []
    end

    methods
        function obj = SourceAnalysis(source)
            % SourceAnalysis Compile one exact source without evaluating its contents.
            arguments (Input)
                source string = ""
            end
            arguments (Output)
                obj (1, 1) macd.source.SourceAnalysis
            end
            obj.Source = source;
            obj.CallbackCandidates = containers.Map("KeyType", "char", "ValueType", "any");
            obj.Statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            obj.indexStatements();
            obj.Layout = macd.source.CallbackSourceAnalyzer.sourceLayout(obj.Statements);
        end

        function [analysis, local, statistics] = withPatches(obj, batch)
            % withPatches Rescan complete changed windows and relocate unaffected lexical statements.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                analysis (1, 1) macd.source.SourceAnalysis
                local (1, 1) logical
                statistics (1, 1) struct
            end
            batch.apply(obj.Source);
            statistics = struct("ScannedCharacters", 0, "ReusedStatements", 0, "FullScan", false);
            if isempty(batch.Edits)
                analysis = obj;
                local = true;
                statistics.ReusedStatements = numel(obj.Statements);
                return
            end
            if isempty(obj.Statements)
                analysis = macd.source.SourceAnalysis(batch.AfterText);
                local = false;
                statistics.FullScan = true;
                statistics.ScannedCharacters = strlength(batch.AfterText);
                return
            end
            % Keep one complete neighboring statement on both sides as lexical guards.
            windows = zeros(0, 2);
            for edit = batch.Edits
                touched = find(obj.StatementStarts <= edit.End + 1 & obj.StatementEnds >= edit.Start - 1);
                if isempty(touched)
                    touched = [find(obj.StatementEnds < edit.Start, 1, "last"), ...
                        find(obj.StatementStarts > edit.End, 1)];
                end
                first = max(1, min(touched) - 1);
                last = min(numel(obj.Statements), max(touched) + 1);
                windows(end + 1, :) = [min(obj.StatementStarts(first), edit.Start), ...
                    max(obj.StatementEnds(last), edit.End)]; %#ok<AGROW>
            end
            windows = sortrows(windows, 1);
            merged = windows(1, :);
            for index = 2:size(windows, 1)
                if windows(index, 1) <= merged(end, 2) + 1
                    merged(end, 2) = max(merged(end, 2), windows(index, 2));
                else
                    merged(end + 1, :) = windows(index, :); %#ok<AGROW>
                end
            end
            statements = macd.source.SourceStatement.empty;
            removed = false(size(obj.Statements));
            for index = 1:size(merged, 1)
                first = merged(index, 1);
                last = merged(index, 2);
                removed = removed | (obj.StatementStarts <= last & obj.StatementEnds >= first);
                [startBoundary, startValid] = batch.mapBoundary(first - 1, "left");
                [endBoundary, endValid] = batch.mapBoundary(last, "right");
                assert(startValid && endValid);
                if startBoundary == endBoundary, continue, end
                fragment = extractBetween(batch.AfterText, startBoundary + 1, endBoundary);
                scanned = macd.source.MatlabLexicalScanner.splitStatements(fragment);
                statistics.ScannedCharacters = statistics.ScannedCharacters + strlength(fragment);
                for statement = scanned
                    span = statement.Span;
                    statements(end + 1) = statement.withSpan(macd.model.SourceSpan( ...
                        span.StartOffset + startBoundary, span.EndOffset + startBoundary)); %#ok<AGROW>
                end
            end
            % Guard unchanged boundary syntax before relying on independent window scans.
            local = true;
            for index = 1:numel(obj.Statements)
                old = obj.Statements(index);
                if removed(index)
                    changed = false;
                    for edit = batch.Edits
                        changed = changed || (edit.End >= edit.Start && ...
                            old.Span.StartOffset <= edit.End && old.Span.EndOffset >= edit.Start) || ...
                            (edit.End < edit.Start && edit.Start > old.Span.StartOffset && edit.Start <= old.Span.EndOffset);
                    end
                    if changed, continue, end
                    [span, valid] = batch.mapSpan(old.Span);
                    matches = [];
                    if valid && ~isempty(statements)
                        spans = [statements.Span];
                        matches = find([spans.StartOffset] == span.StartOffset & [spans.EndOffset] == span.EndOffset);
                    end
                    if numel(matches) ~= 1 || statements(matches).Text ~= old.Text
                        local = false;
                        break
                    end
                else
                    [span, valid] = batch.mapSpan(old.Span);
                    assert(valid);
                    statements(end + 1) = old.withSpan(span); %#ok<AGROW>
                    statistics.ReusedStatements = statistics.ReusedStatements + 1;
                end
            end
            if ~local
                analysis = macd.source.SourceAnalysis(batch.AfterText);
                statistics.FullScan = true;
                statistics.ScannedCharacters = statistics.ScannedCharacters + strlength(batch.AfterText);
                statistics.ReusedStatements = 0;
                return
            end
            if ~isempty(statements)
                spans = [statements.Span];
                [~, order] = sort([spans.StartOffset]);
                statements = statements(order);
            end
            analysis = macd.source.SourceAnalysis();
            analysis.Source = batch.AfterText;
            analysis.Statements = statements;
            analysis.indexStatements();
            analysis.Layout = macd.source.CallbackSourceAnalyzer.sourceLayout(statements);
            % Source-bound trace/callback caches are rebuilt lazily from this exact lexical revision.
        end

        function result = matches(obj, source)
            % matches Require exact text equality before sharing derived source analysis.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                source string
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = isequaln(obj.Source, source);
        end

        function indices = statementIndices(obj, span, matchEnd)
            % statementIndices Find exact source ranges without repeated statement-object traversal.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                span (1, 1) macd.model.SourceSpan
                matchEnd (1, 1) logical = true
            end
            arguments (Output)
                indices (1, :) double
            end
            matching = obj.StatementStarts == span.StartOffset;
            if matchEnd, matching = matching & obj.StatementEnds == span.EndOffset; end
            indices = find(matching);
        end

        function result = canInsertGenerated(obj, creationOffsets)
            % canInsertGenerated Share direct-anchor eligibility for an exact parsed creation set.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                creationOffsets double
            end
            arguments (Output)
                result (1, 1) logical
            end
            if obj.HasCallbackInsertion && isequaln(obj.CallbackCreationOffsets, creationOffsets)
                result = obj.CallbackInsertion;
                return
            end
            result = obj.Layout.Valid && obj.Layout.MethodAnchor > 0 && ~isempty(creationOffsets);
            if result
                % Build a value-only index once; ambiguous statement offsets are excluded.
                if ~obj.HasCallbackIndex
                    spans = [obj.Statements.Span];
                    [offsets, first, groups] = unique([spans.StartOffset]);
                    counts = accumarray(groups(:), 1);
                    direct = reshape(obj.Layout.Direct(first), 1, []);
                    obj.CallbackDirectOffsets = offsets(counts(:)' == 1 & direct);
                    obj.HasCallbackIndex = true;
                end
                result = all(ismember(creationOffsets, obj.CallbackDirectOffsets), "all");
            end
            % Retain only one scalar answer and its numeric key, never document handles.
            obj.CallbackCreationOffsets = creationOffsets;
            obj.CallbackInsertion = result;
            obj.HasCallbackInsertion = true;
        end

        function trace = initialization(obj, creationOffsets)
            % initialization Return a value-only trace for the exact factory-offset input.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                creationOffsets double = []
            end
            arguments (Output)
                trace (1, 1) struct
            end
            if obj.HasTrace && isequaln(obj.TraceOffsets, creationOffsets)
                trace = obj.Trace;
                return
            end
            % Replace the single retained trace only after analysis succeeds.
            [order, diagnostics, certain, returns] = macd.source.InitializationSourceAnalyzer.analyze( ...
                obj.Statements, obj.Layout, creationOffsets);
            trace = struct("Order", order, "Diagnostics", diagnostics, ...
                "Certain", certain, "Returns", returns);
            obj.Trace = trace;
            obj.TraceOffsets = creationOffsets;
            obj.HasTrace = true;
        end
    end

    methods (Access = private)
        function indexStatements(obj)
            % indexStatements Retain immutable numeric offsets for the exact lexical statement snapshot.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
            end
            if isempty(obj.Statements)
                obj.StatementStarts = zeros(1, 0);
                obj.StatementEnds = zeros(1, 0);
                return
            end
            spans = [obj.Statements.Span];
            obj.StatementStarts = [spans.StartOffset];
            obj.StatementEnds = [spans.EndOffset];
        end
    end

    methods (Access = ?macd.source.CallbackSourceAnalyzer)
        function indices = callbackCandidates(obj, name)
            % callbackCandidates Share source-only candidate indices for one literal callback identifier.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                name (1, 1) string
            end
            arguments (Output)
                indices (1, :) double
            end
            key = char(name);
            if ~isKey(obj.CallbackCandidates, key)
                obj.CallbackCandidates(key) = macd.source.CallbackSourceAnalyzer.sourceCallbackCandidates(obj.Statements, name);
            end
            indices = obj.CallbackCandidates(key);
        end
    end

    methods (Static, Access = ?macd.source.AppSourceParser)
        function obj = fromParsed(source, statements, layout, offsets, trace)
            % fromParsed Retain the parser's completed analysis without compiling it again.
            arguments (Input)
                source string
                statements macd.source.SourceStatement
                layout (1, 1) struct
                offsets double
                trace (1, 1) struct
            end
            arguments (Output)
                obj (1, 1) macd.source.SourceAnalysis
            end
            obj = macd.source.SourceAnalysis();
            obj.Source = source;
            obj.Statements = statements;
            obj.indexStatements();
            obj.Layout = layout;
            obj.TraceOffsets = offsets;
            obj.Trace = trace;
            obj.HasTrace = true;
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
