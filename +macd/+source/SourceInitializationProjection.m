classdef SourceInitializationProjection
    % SourceInitializationProjection Preserve a proven call trace across component-local literal edits.
    %   Only changed target assignments are interpreted. Other statements retain their
    %   exact text and scope, and ambiguous insertion visits use the established analyzer.
    methods (Static)
        function [result, proven] = project(before, after, batch, trace, name)
            % project Relocate visits and splice inert assignments without retracing unrelated methods.
            arguments (Input)
                before (1, 1) macd.source.SourceAnalysis
                after (1, 1) macd.source.SourceAnalysis
                batch (1, 1) macd.source.SourcePatchBatch
                trace (1, 1) struct
                name (1, 1) string
            end
            arguments (Output)
                result (1, 1) struct
                proven (1, 1) logical
            end
            result = struct();
            proven = false;
            if ~before.Layout.Valid || ~after.Layout.Valid || isempty(before.Statements), return, end
            old = before.Statements;
            current = after.Statements;
            if isempty(current), return, end
            [spans, valid] = batch.mapSpanCells(arrayfun(@(item) {item.Span}, old));
            starts = zeros(1, numel(old));
            ends = starts;
            for index = find(valid)
                starts(index) = spans{index}.StartOffset;
                ends(index) = spans{index}.EndOffset;
            end
            ranges = [current.Span];
            [matched, mapping] = ismember([starts(:) ends(:)], [[ranges.StartOffset]' [ranges.EndOffset]'], "rows");
            matched = matched' & valid;
            mapping = mapping';
            mapping(~matched) = 0;
            kept = find(matched);
            if numel(unique(mapping(kept))) ~= numel(kept), return, end
            % A local edit must not change structural statements, scopes or branch certainty.
            for field = ["Owner", "StraightLine", "Direct"]
                if ~isequal(before.Layout.(field)(kept), after.Layout.(field)(mapping(kept))), return, end
            end
            added = setdiff(1:numel(current), mapping(kept));
            removed = find(~matched);
            changed = kept(string({old(kept).Text}) ~= string({current(mapping(kept)).Text}));
            for index = [removed changed]
                if ~macd.source.SourceInitializationProjection.literalAssignment(old(index), name), return, end
            end
            for index = [added mapping(changed)]
                if ~macd.source.SourceInitializationProjection.literalAssignment(current(index), name), return, end
            end
            % Place additions immediately before the next surviving visit in the same method.
            insertions = cell(1, numel(trace.Order));
            for index = added
                owner = after.Layout.Owner(index);
                if strlength(owner) == 0 || ~after.Layout.StraightLine(index), return, end
                following = kept(mapping(kept) > index & before.Layout.Owner(kept) == owner);
                if isempty(following), return, end
                anchor = following(1);
                visits = find(trace.Order == anchor);
                ownerVisits = trace.Order(before.Layout.Owner(trace.Order) == owner);
                if ~isscalar(visits) || any(diff(ownerVisits) <= 0), return, end
                insertions{visits}(end + 1) = index;
            end
            order = zeros(1, 0);
            certain = false(1, 0);
            oldToNew = zeros(size(trace.Order));
            for visit = 1:numel(trace.Order)
                inserted = insertions{visit};
                order = [order inserted]; %#ok<AGROW>
                certain = [certain repmat(trace.Certain(visit), 1, numel(inserted))]; %#ok<AGROW>
                index = mapping(trace.Order(visit));
                if index > 0
                    order(end + 1) = index; %#ok<AGROW>
                    certain(end + 1) = trace.Certain(visit); %#ok<AGROW>
                    oldToNew(visit) = numel(order);
                end
            end
            returns = 1:numel(order);
            for visit = find(oldToNew > 0)
                last = find(oldToNew(1:trace.Returns(visit)) > 0, 1, "last");
                if isempty(last), return, end
                returns(oldToNew(visit)) = oldToNew(last);
            end
            % Diagnostics remain independent values with current positions.
            diagnostics = trace.Diagnostics;
            for index = 1:numel(diagnostics)
                [span, valid] = batch.mapSpan(diagnostics(index).SourceSpan);
                if ~valid, return, end
                item = diagnostics(index);
                diagnostics(index) = macd.model.Diagnostic(item.Code, item.Severity, item.Message, item.ComponentId, span);
            end
            result = struct("Order", order, "Diagnostics", diagnostics, "Certain", certain, "Returns", returns);
            proven = true;
        end
    end

    methods (Static, Access = private)
        function result = literalAssignment(statement, name)
            % literalAssignment Admit only inert assignments to the explicitly edited component.
            arguments (Input)
                statement (1, 1) macd.source.SourceStatement
                name (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end
            pattern = "^app\." + regexptranslate("escape", name) + "\.[A-Za-z]\w*(?:\.[A-Za-z]\w*)*\s*=\s*(?<value>[\s\S]*)$";
            match = regexp(statement.Text, pattern, "names", "once");
            result = false;
            if isempty(match), return, end
            [~, result] = macd.source.MatlabLiteralParser.parse(string(match.value));
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
