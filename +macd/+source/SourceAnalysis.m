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
        % Facts - Load-time statement classification and insertion trivia, projected by known edits.
        Facts struct = struct()
    end

    properties (Access = private)
        Source string = ""
        TraceOffsets double = []
        Trace struct = struct()
        Execution struct = struct()
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
            obj.compileStatementFacts();
        end

        function result = executionIndex(obj)
            % executionIndex Read the exact-source execution event index without interpreting statements.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
            end
            arguments (Output)
                result (1, 1) struct
            end
            result = obj.Execution;
        end

        function rememberExecution(obj, result)
            % rememberExecution Cache value-only execution events for this immutable source revision.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                result (1, 1) struct
            end
            obj.Execution = result;
        end

        function [analysis, execution] = withLiteralPatches(obj, batch, additions, anchors, removed, constructorDelta, execution, addedOwner)
            % withLiteralPatches Apply editor-owned literal patches without rescanning or rediscovering source ownership.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                batch (1, 1) macd.source.SourcePatchBatch
                additions macd.source.SourceStatement
                anchors double
                removed double
                constructorDelta double
                execution (1, 1) struct
                addedOwner (1, 1) string
            end
            arguments (Output)
                analysis (1, 1) macd.source.SourceAnalysis
                execution (1, 1) struct
            end
            batch.apply(obj.Source);
            [ranges, valid] = batch.mapSpanCells(arrayfun(@(item) {item.Span}, obj.Statements));
            keep = true(size(obj.Statements)); keep(removed) = false;
            assert(all(valid(keep)), "macd:SourceLiteralTransaction:WiderProof", "An owned edit removed another statement.");
            original = find(keep);
            statements = obj.Statements(keep).withSpans(ranges(keep));
            edits = batch.Edits;
            shifts = [0 cumsum(strlength(string({edits.Text})) - ([edits.End] - [edits.Start] + 1))];
            % Locate touched intervals numerically before accessing any statement payload.
            changed = false(size(obj.Statements));
            for edit = edits
                if edit.End >= edit.Start
                    changed = changed | (obj.StatementStarts <= edit.End & obj.StatementEnds >= edit.Start);
                else
                    changed = changed | (obj.StatementStarts < edit.Start & obj.StatementEnds >= edit.Start);
                end
            end
            for position = find(changed(original))
                old = obj.Statements(original(position));
                touched = find(([edits.End] >= [edits.Start] & [edits.Start] <= old.Span.EndOffset & [edits.End] >= old.Span.StartOffset) | ...
                    ([edits.End] < [edits.Start] & [edits.Start] > old.Span.StartOffset & [edits.Start] <= old.Span.EndOffset));
                touched = touched([edits(touched).Start] > old.Span.StartOffset | [edits(touched).End] >= [edits(touched).Start]);
                if isempty(touched), continue, end
                text = char(old.Text); offsets = old.CodeOffsets; mapped = offsets;
                for edit = edits
                    mapped = mapped + (strlength(edit.Text) - (edit.End - edit.Start + 1)) * (offsets > edit.End);
                end
                for which = fliplr(touched)
                    edit = edits(which);
                    assert(edit.Start >= old.Span.StartOffset && edit.End < old.Span.EndOffset, ...
                        "macd:SourceLiteralTransaction:WiderProof", "Literal ownership must exclude structural delimiters.");
                    first = find(offsets >= edit.Start, 1);
                    if isempty(first), first = numel(offsets) + 1; end
                    last = find(offsets <= edit.End, 1, "last");
                    if isempty(last) || last < first, last = first - 1; end
                    inserted = char(edit.Text);
                    text = [text(1:first - 1) inserted text(last + 1:end)];
                    points = edit.Start + shifts(which) + (0:numel(inserted) - 1);
                    mapped = [mapped(1:first - 1) points mapped(last + 1:end)];
                    offsets = [offsets(1:first - 1) repmat(edit.Start, 1, numel(inserted)) offsets(last + 1:end)];
                end
                statements(position) = macd.source.SourceStatement(string(text), ranges{original(position)}, mapped);
            end
            tags = [original -(1:numel(additions))];
            parents = [original anchors];
            statements = [statements additions];
            spans = [statements.Span]; [~, order] = sort([spans.StartOffset]);
            statements = statements(order); tags = tags(order); parents = parents(order);
            mapping = zeros(1, numel(obj.Statements)); mapping(tags(tags > 0)) = find(tags > 0);
            addedPositions = zeros(1, numel(additions));
            addedPositions(-tags(tags < 0)) = find(tags < 0);
            % Method membership and straight-line certainty are unchanged by literal writes.
            layout = obj.Layout;
            for field = ["Owner", "Direct", "StraightLine"], layout.(field) = layout.(field)(parents); end
            if ~isempty(layout.Methods)
                [methodSpans, valid] = batch.mapSpanCells(arrayfun(@(item) {item.Span}, layout.Methods));
                assert(all(valid));
                for index = 1:numel(layout.Methods), layout.Methods(index).Span = methodSpans{index}; end
            end
            [layout.MethodAnchor, valid] = batch.mapBoundary(layout.MethodAnchor, "right"); assert(valid);
            trace = execution.Trace;
            beforeOrder = trace.Order;
            counts = execution.Counts;
            counts = counts + constructorDelta;
            insertionVisits = zeros(size(anchors));
            for index = 1:numel(anchors)
                anchor = find(beforeOrder == anchors(index));
                assert(isscalar(anchor), "macd:SourceLiteralTransaction:WiderProof", "Insertion needs one execution visit.");
                insertionVisits(index) = trace.Returns(anchor);
            end
            surviving = find(mapping(beforeOrder) > 0);
            visitKeys = [surviving insertionVisits];
            added = [false(size(surviving)) true(size(insertionVisits))];
            [~, order] = sortrows([visitKeys(:) added(:) (1:numel(visitKeys))'], [1 2 3]);
            physical = [mapping(beforeOrder(surviving)) addedPositions];
            currentOrder = physical(order);
            certain = [trace.Certain(surviving) trace.Certain(insertionVisits)]; certain = certain(order);
            currentCounts = [counts(surviving) ones(size(insertionVisits))]; currentCounts = currentCounts(order);
            creation = [execution.Creation(surviving) > 0 false(size(insertionVisits))]; creation = creation(order);
            assignment = [execution.Assignment(surviving) > 0 true(size(insertionVisits))]; assignment = assignment(order);
            oldVisit = zeros(size(beforeOrder));
            oldPositions = find(~added(order)); oldVisit(surviving) = oldPositions;
            newPositions = zeros(size(insertionVisits));
            newPositions(order(added(order)) - numel(surviving)) = find(added(order));
            previousRetained = cummax(oldVisit);
            returns = 1:numel(currentOrder);
            returns(oldPositions) = previousRetained(trace.Returns(surviving));
            % An inserted caller statement follows the callee return; it is not part of that callee.
            for visit = surviving(trace.Returns(surviving) > surviving)
                target = trace.Returns(visit);
                owner = obj.Layout.Owner(beforeOrder(target));
                extend = find(insertionVisits == target & obj.Layout.Owner(anchors) == owner);
                if ~isempty(extend), returns(oldVisit(visit)) = max([returns(oldVisit(visit)) newPositions(extend)]); end
            end
            diagnostics = macd.model.SourceLocationUpdate.relocateDiagnostics(trace.Diagnostics, batch);
            trace = struct("Order", currentOrder, "Certain", certain, "Returns", returns, "Diagnostics", diagnostics);
            last = cumsum(currentCounts);
            previousExecution = execution;
            execution.Trace = trace; execution.Counts = currentCounts;
            execution.Creation = zeros(size(last)); execution.Assignment = zeros(size(last));
            execution.Creation(creation) = last(creation) - currentCounts(creation) + 1;
            execution.Assignment(assignment) = last(assignment);
            sequenceMap = zeros(1, sum(previousExecution.Counts));
            for visit = surviving
                first = max(previousExecution.Creation(visit), previousExecution.Assignment(visit));
                if first == 0, continue, end
                current = max(execution.Creation(oldVisit(visit)), execution.Assignment(oldVisit(visit)));
                if previousExecution.Creation(visit) > 0
                    length = previousExecution.Counts(visit);
                    sequenceMap(first:first + length - 1) = current + (0:length - 1);
                else
                    sequenceMap(first) = current;
                end
            end
            execution.SequenceMap = sequenceMap;
            execution.Owners = mapping(execution.Owners);
            [uniqueStatements, ~, groups] = unique(currentOrder);
            occurrences = accumarray(groups(:), 1);
            uniqueStatements = uniqueStatements(occurrences == 1);
            [~, visits] = ismember(uniqueStatements, currentOrder);
            ranges = [statements(uniqueStatements).Span];
            execution.RangeStarts = [ranges.StartOffset]; execution.RangeEnds = [ranges.EndOffset]; execution.Visits = visits;
            analysis = macd.source.SourceAnalysis();
            analysis.Source = batch.AfterText; analysis.Statements = statements; analysis.Layout = layout;
            facts = obj.Facts;
            for field = ["Structural", "SafeLocal", "ComponentName", "Indent"]
                facts.(field) = facts.(field)(parents);
            end
            [anchorSpans, valid] = batch.mapSpanCells(arrayfun(@(offset) {macd.model.SourceSpan(offset, offset)}, obj.Facts.AnchorOffset));
            assert(all(valid(keep)));
            offsets = NaN(size(obj.Facts.AnchorOffset));
            for index = find(valid), offsets(index) = anchorSpans{index}.StartOffset; end
            facts.AnchorOffset = offsets(parents);
            for position = addedPositions
                facts.Structural(position) = false; facts.SafeLocal(position) = false;
                facts.ComponentName(position) = addedOwner;
                facts.AnchorOffset(position) = statements(position).Span.EndOffset;
            end
            analysis.Facts = facts;
            analysis.indexStatements(); analysis.Trace = trace; analysis.HasTrace = true;
            [offsets, valid] = batch.mapSpanCells(arrayfun(@(offset) {macd.model.SourceSpan(offset, offset)}, obj.TraceOffsets));
            assert(all(valid)); analysis.TraceOffsets = cellfun(@(item) item.StartOffset, offsets);
            analysis.Execution = execution;
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
            % Transform the maintained ranges once, then check only the lexical guard window.
            [mapped, mappedValid] = batch.mapSpanCells(arrayfun(@(item) {item.Span}, obj.Statements));
            local = true;
            for index = find(removed)
                old = obj.Statements(index);
                changed = false;
                for edit = batch.Edits
                    changed = changed || (edit.End >= edit.Start && ...
                        old.Span.StartOffset <= edit.End && old.Span.EndOffset >= edit.Start) || ...
                        (edit.End < edit.Start && edit.Start > old.Span.StartOffset && edit.Start <= old.Span.EndOffset);
                end
                if changed, continue, end
                matches = [];
                if mappedValid(index) && ~isempty(statements)
                    spans = [statements.Span];
                    span = mapped{index};
                    matches = find([spans.StartOffset] == span.StartOffset & [spans.EndOffset] == span.EndOffset);
                end
                if numel(matches) ~= 1 || statements(matches).Text ~= old.Text
                    local = false;
                    break
                end
            end
            retained = ~removed;
            assert(all(mappedValid(retained)));
            statements = [statements obj.Statements(retained).withSpans(mapped(retained))];
            statistics.ReusedStatements = nnz(retained);
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
            analysis.compileStatementFacts();
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

        function [before, after] = statementNeighbors(obj, boundary)
            % statementNeighbors Find adjacent complete statements by binary search in immutable position indexes.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                boundary (1, 1) double {mustBeInteger, mustBeNonnegative}
            end
            arguments (Output)
                before double
                after double
            end
            % Both index arrays are monotonic because lexical statements do not overlap.
            left = 1; right = numel(obj.StatementEnds); previous = 0;
            while left <= right
                middle = floor((left + right) / 2);
                if obj.StatementEnds(middle) <= boundary
                    previous = middle; left = middle + 1;
                else
                    right = middle - 1;
                end
            end
            left = 1; right = numel(obj.StatementStarts); following = right + 1;
            while left <= right
                middle = floor((left + right) / 2);
                if obj.StatementStarts(middle) > boundary
                    following = middle; right = middle - 1;
                else
                    left = middle + 1;
                end
            end
            before = previous; after = following;
            if previous == 0, before = zeros(1, 0); end
            if following > numel(obj.StatementStarts), after = zeros(1, 0); end
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
            creationOffsets = sort(creationOffsets);
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

    methods (Access = ?macd.model.SourceSettingRebinder)
        function projected = inheritInitialization(obj, previous, batch, offsets, name)
            % inheritInitialization Reuse the exact prior trace only after proving component-local inert syntax changes.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                previous (1, 1) macd.source.SourceAnalysis
                batch (1, 1) macd.source.SourcePatchBatch
                offsets double
                name (1, 1) string
            end
            arguments (Output)
                projected (1, 1) logical
            end
            offsets = sort(offsets);
            projected = false;
            if obj.HasTrace || ~previous.HasTrace || ~previous.matches(batch.BeforeText) || ~obj.matches(batch.AfterText), return, end
            [mapped, valid] = batch.mapSpanCells(arrayfun(@(offset) {macd.model.SourceSpan(offset, offset)}, previous.TraceOffsets));
            if ~all(valid), return, end
            starts = cellfun(@(span) span.StartOffset, mapped);
            if ~isequal(starts, offsets), return, end
            [trace, projected] = macd.source.SourceInitializationProjection.project(previous, obj, batch, previous.Trace, name);
            if ~projected, return, end
            obj.Trace = trace;
            obj.TraceOffsets = offsets;
            obj.HasTrace = true;
        end
    end

    methods (Access = private)
        function compileStatementFacts(obj)
            % compileStatementFacts Classify opaque boundaries and record insertion trivia once while reading source.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
            end
            count = numel(obj.Statements);
            facts = struct("Structural", false(1, count), "SafeLocal", false(1, count), ...
                "ComponentName", strings(1, count), "AnchorOffset", zeros(1, count), "Indent", strings(1, count));
            source = char(obj.Source); lines = [0 find(source == newline) numel(source) + 1];
            for index = 1:count
                statement = obj.Statements(index); code = strtrim(statement.Text);
                facts.Structural(index) = ~isempty(regexp(code, '^(end|arguments|function|return)(?!\w)', 'once'));
                name = regexp(code, '^app\.(\w+)(?:\.\w+)*\s*=(?!=)', 'tokens', 'once');
                if ~isempty(name), facts.ComponentName(index) = string(name{1}); end
                local = regexp(code, '^[A-Za-z]\w*\s*=\s*(.*)$', 'tokens', 'once');
                if ~isempty(local), [~, facts.SafeLocal(index)] = macd.source.MatlabLiteralParser.parse(string(local{1})); end
                ending = statement.Span.EndOffset;
                following = lines(find(lines > ending, 1));
                last = following - 1;
                if last > ending && source(last) == char(13), last = last - 1; end
                suffix = string(source(ending + 1:last));
                if ~isempty(regexp(suffix, '^\s*(%[^\r\n]*)?$', 'once')), ending = last; end
                facts.AnchorOffset(index) = ending;
                beginning = lines(find(lines < statement.Span.StartOffset, 1, 'last'));
                prefix = string(source(beginning + 1:statement.Span.StartOffset - 1));
                indent = regexp(char(prefix), '^[ \t]*', 'match', 'once');
                if ~isempty(indent), facts.Indent(index) = string(indent); end
            end
            obj.Facts = facts;
        end

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
            obj.compileStatementFacts();
            obj.TraceOffsets = sort(offsets);
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
