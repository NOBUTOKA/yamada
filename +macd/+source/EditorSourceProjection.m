classdef EditorSourceProjection
    % EditorSourceProjection Project editor-owned syntax changes through existing method and call indexes.
    %   Only inserted method fragments and new factory/assignment tokens are
    %   interpreted. Existing call expansions and unaffected scopes stay intact.
    methods (Static)
        function mapping = statementMap(before, after, batch)
            % statementMap Join surviving statement ranges without comparing or parsing their bodies.
            arguments (Input)
                before (1, 1) macd.source.SourceAnalysis
                after (1, 1) macd.source.SourceAnalysis
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                mapping (1, :) double
            end
            [spans, valid] = batch.mapSpanCells(arrayfun(@(item) {item.Span}, before.Statements));
            ranges = [after.Statements.Span];
            mapping = zeros(1, numel(spans));
            for index = find(valid)
                span = spans{index};
                match = find([ranges.StartOffset] == span.StartOffset & [ranges.EndOffset] == span.EndOffset);
                if isscalar(match), mapping(index) = match; end
            end
            % A neighboring insertion may change only the CR/trivia owned by a statement end.
            for index = find(mapping == 0)
                offsets = before.Statements(index).CodeOffsets;
                if isempty(offsets), continue, end
                [span, survives] = batch.mapSpan(macd.model.SourceSpan(offsets(1), offsets(end)));
                if ~survives, continue, end
                for candidate = find([ranges.StartOffset] == span.StartOffset)
                    current = after.Statements(candidate).CodeOffsets;
                    if ~isempty(current) && current(end) == span.EndOffset, mapping(index) = candidate; break, end
                end
            end
        end

        function names = changedMembers(analysis, positions)
            % changedMembers Read only changed class property declarations outside method bodies.
            arguments (Input)
                analysis (1, 1) macd.source.SourceAnalysis
                positions (1, :) double
            end
            arguments (Output)
                names (1, :) string
            end
            names = strings(1, 0);
            for index = positions
                if analysis.Layout.Owner(index) ~= "", continue, end
                token = regexp(analysis.Statements(index).Text, '^(\w+)(?:\s+[A-Za-z]\w*(?:\.\w+)*|$)', 'tokens', 'once');
                if ~isempty(token) && isvarname(token{1}) && ~iskeyword(token{1})
                    names(end + 1) = string(token{1}); %#ok<AGROW>
                end
            end
        end

        function layout = layout(before, after, batch)
            % layout Retain established scopes and compile only complete inserted callback methods.
            arguments (Input)
                before (1, 1) macd.source.SourceAnalysis
                after (1, 1) macd.source.SourceAnalysis
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                layout (1, 1) struct
            end
            layout = before.Layout; oldMethods = layout.Methods;
            mapping = macd.source.EditorSourceProjection.statementMap(before, after, batch);
            oldRanges = [before.Statements.Span]; methods = oldMethods([]);
            for method = oldMethods
                first = find([oldRanges.StartOffset] == method.Span.StartOffset);
                last = find([oldRanges.EndOffset] == method.Span.EndOffset);
                if ~isscalar(first) || ~isscalar(last) || mapping(first) == 0 || mapping(last) == 0, continue, end
                method.Span = macd.model.SourceSpan(after.Statements(mapping(first)).Span.StartOffset, ...
                    after.Statements(mapping(last)).Span.EndOffset);
                methods(end + 1) = method; %#ok<AGROW>
            end
            methodStatements = macd.source.SourceStatement.empty;
            methodOwner = strings(1, 0); methodDirect = false(1, 0); methodStraight = false(1, 0);
            shift = 0;
            for edit = batch.Edits
                if ~isempty(regexp(edit.Text, '(?m)^\s*function\s', 'once'))
                    prefix = "classdef " + layout.ClassName + " < handle" + newline + "methods" + newline;
                    fragment = macd.source.SourceAnalysis(prefix + edit.Text + newline + "end" + newline + "end");
                    compiled = fragment.Layout;
                    assert(compiled.Valid, "macd:EditorSourceProjection:InvalidMethod", "Inserted methods must be complete editor-owned syntax.");
                    offset = edit.Start + shift - strlength(prefix) - 1;
                    for index = 1:numel(fragment.Statements)
                        statement = fragment.Statements(index); span = statement.Span;
                        if span.StartOffset <= strlength(prefix) || span.EndOffset > strlength(prefix + edit.Text), continue, end
                        methodStatements(end + 1) = statement.withSpan(macd.model.SourceSpan(span.StartOffset + offset, span.EndOffset + offset)); %#ok<AGROW>
                        methodOwner(end + 1) = compiled.Owner(index); methodDirect(end + 1) = compiled.Direct(index); %#ok<AGROW>
                        methodStraight(end + 1) = compiled.StraightLine(index); %#ok<AGROW>
                    end
                    for method = compiled.Methods
                        offset = edit.Start + shift - strlength(prefix) - 1;
                        method.Span = macd.model.SourceSpan(method.Span.StartOffset + offset, method.Span.EndOffset + offset);
                        methods(end + 1) = method; %#ok<AGROW>
                    end
                end
                shift = shift + strlength(edit.Text) - (edit.End - edit.Start + 1);
            end
            if ~isempty(methods)
                spans = [methods.Span]; [~, order] = sort([spans.StartOffset]); methods = methods(order);
            end
            layout.Methods = methods; layout.InstanceNames = string({methods.Name});
            [layout.MethodAnchor, valid] = batch.mapBoundary(layout.MethodAnchor, "right"); assert(valid);
            count = numel(after.Statements); layout.Owner = strings(1, count);
            layout.Direct = false(1, count); layout.StraightLine = false(1, count);
            mapping = macd.source.EditorSourceProjection.statementMap(before, after, batch);
            for index = find(mapping > 0)
                for field = ["Owner", "Direct", "StraightLine"], layout.(field)(mapping(index)) = before.Layout.(field)(index); end
            end
            for index = setdiff(1:count, mapping(mapping > 0))
                statement = after.Statements(index); position = statement.Span.StartOffset;
                if ~isempty(methodStatements)
                    spans = [methodStatements.Span]; found = find([spans.StartOffset] == position);
                    if isscalar(found)
                        layout.Owner(index) = methodOwner(found); layout.Direct(index) = methodDirect(found);
                        layout.StraightLine(index) = methodStraight(found); continue
                    end
                end
                owners = find(arrayfun(@(item) item.Span.StartOffset < position && item.Span.EndOffset >= position, methods));
                if isempty(owners), continue, end
                assert(isscalar(owners)); owner = methods(owners).Name;
                layout.Owner(index) = owner; layout.StraightLine(index) = true;
                layout.Direct(index) = owner == "createComponents" && statement.Text ~= "end";
            end
        end

        function execution = execution(before, after, batch, components, registry)
            % execution Reuse established call expansions and count only changed owned source events.
            arguments (Input)
                before (1, 1) macd.source.SourceAnalysis
                after (1, 1) macd.source.SourceAnalysis
                batch (1, 1) macd.source.SourcePatchBatch
                components macd.model.ComponentRecord
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                execution (1, 1) struct
            end
            previous = before.executionIndex(); trace = previous.Trace;
            mapping = macd.source.EditorSourceProjection.statementMap(before, after, batch);
            assert(~isempty(trace.Order), "macd:EditorSourceProjection:MissingTrace", "Editor publication requires a loaded initialization trace.");
            projected = macd.source.EditorSourceProjection.frame(before, after, mapping, trace, 1, numel(trace.Order), true);
            diagnostics = macd.model.SourceLocationUpdate.relocateDiagnostics(trace.Diagnostics, batch);
            current = struct("Order", projected.Order, "Certain", projected.Certain, ...
                "Returns", projected.Returns, "Diagnostics", diagnostics);
            count = numel(current.Order); counts = zeros(1, count);
            creation = zeros(1, count); assignment = zeros(1, count); owners = zeros(1, numel(components));
            creationCounts = zeros(size(owners));
            added = setdiff(unique(current.Order), mapping(mapping > 0));
            for index = 1:numel(components)
                component = components(index); [span, valid] = batch.mapSpan(component.SourceSpans.Creation);
                statement = [];
                if valid && ~isempty(span), statement = after.statementIndices(span); end
                if ~isscalar(statement) && ~isempty(component.SourceSpans.Creation)
                    old = before.statementIndices(component.SourceSpans.Creation);
                    if isscalar(old) && mapping(old) > 0, statement = mapping(old); end
                end
                if ~isscalar(statement)
                    for position = added
                        if ~isempty(regexp(after.Statements(position).Text, '^app\.' + regexptranslate('escape', component.Name) + '\s*=', 'once'))
                            statement = position; break
                        end
                    end
                end
                if isempty(statement) && isempty(component.SourceSpans.Creation), continue, end
                assert(isscalar(statement), "macd:EditorSourceProjection:MissingFactory", "Every retained factory needs a current indexed occurrence.");
                owners(index) = statement;
                old = find(mapping == statement, 1);
                if ~isempty(old) && before.Statements(old).Text == after.Statements(statement).Text
                    creationCounts(index) = nnz(string({component.Settings.Method}) == "nameValue");
                else
                    definition = registry.get(component.Factory, component.CreationArguments);
                    [~, ~, settings, ~, supported] = macd.source.PropertySettingSyntax.factory(after.Statements(statement), definition, "editor");
                    assert(supported); creationCounts(index) = numel(settings);
                end
            end
            names = string({components.Name}); sequence = 0;
            for visit = 1:count
                statement = current.Order(visit); owner = find(owners == statement, 1);
                if ~isempty(owner)
                    counts(visit) = 1 + creationCounts(owner); creation(visit) = sequence + 1;
                elseif projected.OldRows(visit) > 0
                    old = projected.OldRows(visit);
                    if previous.Assignment(old) > 0, counts(visit) = 1; assignment(visit) = sequence + 1; end
                else
                    name = regexp(after.Statements(statement).Text, '^app\.(\w+)\.[A-Za-z]\w*(?:\.\w+)*\s*=', 'tokens', 'once');
                    if ~isempty(name) && any(names == string(name{1})), counts(visit) = 1; assignment(visit) = sequence + 1; end
                end
                sequence = sequence + counts(visit);
            end
            sequenceMap = zeros(1, sum(previous.Counts));
            for visit = find(projected.OldRows > 0)
                old = projected.OldRows(visit); first = max(previous.Creation(old), previous.Assignment(old));
                target = max(creation(visit), assignment(visit));
                if first == 0 || target == 0, continue, end
                length = min(previous.Counts(old), counts(visit));
                sequenceMap(first:first + length - 1) = target + (0:length - 1);
            end
            [uniqueStatements, ~, groups] = unique(current.Order); occurrences = accumarray(groups(:), 1);
            uniqueStatements = uniqueStatements(occurrences == 1); [~, visits] = ismember(uniqueStatements, current.Order);
            ranges = [after.Statements(uniqueStatements).Span];
            execution = struct("Trace", current, "Creation", creation, "Assignment", assignment, ...
                "Owners", owners, "Counts", counts, "SequenceMap", sequenceMap, ...
                "RangeStarts", [ranges.StartOffset], "RangeEnds", [ranges.EndOffset], "Visits", visits);
        end
    end
    methods (Static, Access = private)
        function result = frame(before, after, mapping, trace, first, last, certain)
            % frame Project one already-proven method invocation, retaining its existing nested calls.
            arguments (Input)
                before (1, 1) macd.source.SourceAnalysis
                after (1, 1) macd.source.SourceAnalysis
                mapping (1, :) double
                trace (1, 1) struct
                first (1, 1) double
                last (1, 1) double
                certain (1, 1) logical
            end
            arguments (Output)
                result (1, 1) struct
            end
            rows = []; cursor = first;
            while cursor <= last, rows(end + 1) = cursor; cursor = trace.Returns(cursor) + 1; end %#ok<AGROW>
            owner = before.Layout.Owner(trace.Order(first));
            result = struct("Order", [], "Certain", false(1, 0), "Returns", [], "OldRows", []);
            for statement = find(after.Layout.Owner == owner)
                old = rows(mapping(trace.Order(rows)) == statement);
                if isempty(old)
                    if any(mapping == statement), continue, end
                    code = after.Statements(statement).Text;
                    assert(~isempty(regexp(code, '^app\.\w+(?:\.\w+)*\s*=', 'once')), ...
                        "macd:EditorSourceProjection:ChangedCall", "An editor patch must not introduce initialization calls or control flow.");
                    old = 0; known = certain && after.Layout.StraightLine(statement);
                else
                    assert(isscalar(old)); known = trace.Certain(old);
                end
                position = numel(result.Order) + 1;
                result.Order(end + 1) = statement; result.Certain(end + 1) = known;
                result.Returns(end + 1) = position; result.OldRows(end + 1) = old;
                if old > 0 && trace.Returns(old) > old
                    child = macd.source.EditorSourceProjection.frame(before, after, mapping, trace, old + 1, trace.Returns(old), known);
                    result.Order = [result.Order child.Order]; result.Certain = [result.Certain child.Certain];
                    result.Returns = [result.Returns child.Returns + position]; result.OldRows = [result.OldRows child.OldRows];
                    result.Returns(position) = numel(result.Order);
                end
            end
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
