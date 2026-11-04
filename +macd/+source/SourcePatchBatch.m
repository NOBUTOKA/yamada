classdef SourcePatchBatch
    % SourcePatchBatch Prepare reversible edits and a current-source position transform.
    %   This private candidate retains source snapshots for exact stale checks.
    %   History should retain its forward/inverse edits, not this object.

    properties (SetAccess = private)
        % BeforeText - Exact source against which the batch was prepared.
        BeforeText string = ""
        % AfterText - Complete candidate, published only after model validation.
        AfterText string = ""
        % Edits - Nonoverlapping edits in inclusive before-state coordinates.
        Edits struct = struct("Start", {}, "End", {}, "Text", {}, "ExpectedText", {})
        % InverseEdits - Reverse edits in after-state coordinates.
        InverseEdits struct = struct("Start", {}, "End", {}, "Text", {}, "ExpectedText", {})
    end

    methods
        function obj = SourcePatchBatch(source, edits)
            % SourcePatchBatch Validate expected text and prepare atomic forward/inverse changes.
            arguments (Input)
                source (1, 1) string = ""
                edits struct = struct("Start", {}, "End", {}, "Text", {})
            end
            arguments (Output)
                obj (1, 1) macd.source.SourcePatchBatch
            end
            obj.BeforeText = source;
            count = strlength(source);
            normalized = obj.Edits;
            for edit = reshape(edits, 1, [])
                assert(all(isfield(edit, ["Start", "End", "Text"])), ...
                    "macd:SourcePatchBatch:InvalidEdit", "Edits need Start, End and Text.");
                validateattributes(edit.Start, "double", {"scalar", "integer", ">=", 1, "<=", count + 1});
                validateattributes(edit.End, "double", {"scalar", "integer", ">=", edit.Start - 1, "<=", count});
                assert(isstring(edit.Text) && isscalar(edit.Text) && ~ismissing(edit.Text), ...
                    "macd:SourcePatchBatch:InvalidText", "Replacement text must be one nonmissing string.");
                expected = "";
                if edit.End >= edit.Start, expected = extractBetween(source, edit.Start, edit.End); end
                if isfield(edit, "ExpectedText")
                    assert(isequal(edit.ExpectedText, expected), "macd:SourcePatchBatch:StaleEdit", ...
                        "The expected source fragment changed.");
                end
                item = struct("Start", edit.Start, "End", edit.End, "Text", edit.Text, "ExpectedText", expected);
                match = find([normalized.Start] == edit.Start & [normalized.End] < [normalized.Start], 1);
                if edit.End < edit.Start && ~isempty(match)
                    normalized(match).Text = normalized(match).Text + edit.Text;
                else
                    normalized(end + 1) = item; %#ok<AGROW>
                end
            end
            % Coalesce equal-boundary insertions in caller order before overlap checks.
            [~, order] = sort([normalized.Start], "ascend");
            normalized = normalized(order);
            for index = 2:numel(normalized)
                before = normalized(index - 1);
                current = normalized(index);
                assert(current.Start > before.End && current.Start ~= before.Start, ...
                    "macd:SourcePatchBatch:OverlappingEdits", "Combine overlapping edits before applying source.");
            end
            obj.Edits = normalized;
            result = source;
            for index = numel(normalized):-1:1
                edit = normalized(index);
                result = extractBefore(result, edit.Start) + edit.Text + extractAfter(result, edit.End);
            end
            obj.AfterText = result;
            % Inverse offsets belong to the completed candidate, not the old text.
            shift = 0;
            for edit = normalized
                first = edit.Start + shift;
                obj.InverseEdits(end + 1) = struct("Start", first, ...
                    "End", first + strlength(edit.Text) - 1, "Text", edit.ExpectedText, ...
                    "ExpectedText", edit.Text);
                shift = shift + strlength(edit.Text) - (edit.End - edit.Start + 1);
            end
            % Adjacent removal and insertion become one replacement at the inverse boundary.
            index = 1;
            while index < numel(obj.InverseEdits)
                left = obj.InverseEdits(index); right = obj.InverseEdits(index + 1);
                if left.Start == right.Start
                    left.End = max(left.End, right.End); left.Text = left.Text + right.Text;
                    left.ExpectedText = left.ExpectedText + right.ExpectedText;
                    obj.InverseEdits(index) = left; obj.InverseEdits(index + 1) = [];
                else
                    index = index + 1;
                end
            end
        end

        function source = apply(obj, source)
            % apply Reject stale source before returning the prepared candidate.
            arguments (Input)
                obj (1, 1) macd.source.SourcePatchBatch
                source (1, 1) string
            end
            arguments (Output)
                source (1, 1) string
            end
            assert(isequal(source, obj.BeforeText), "macd:SourcePatchBatch:StaleSource", ...
                "The source changed after preparing this batch.");
            source = obj.AfterText;
        end

        function batch = inverse(obj)
            % inverse Prepare the exact reverse without interpreting MATLAB syntax.
            arguments (Input)
                obj (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                batch (1, 1) macd.source.SourcePatchBatch
            end
            batch = macd.source.SourcePatchBatch(obj.AfterText, obj.InverseEdits);
        end

        function [offset, valid] = mapBoundary(obj, offset, affinity)
            % mapBoundary Transform a between-character position with insertion affinity.
            %   Zero precedes the first character. Interior replacement positions
            %   are invalid and must be rebound through local syntax analysis.
            arguments (Input)
                obj (1, 1) macd.source.SourcePatchBatch
                offset (1, 1) double {mustBeInteger, mustBeNonnegative}
                affinity (1, 1) string {mustBeMember(affinity, ["left", "right"])} = "left"
            end
            arguments (Output)
                offset (1, 1) double
                valid (1, 1) logical
            end
            assert(offset <= strlength(obj.BeforeText), "macd:SourcePatchBatch:InvalidBoundary", ...
                "The boundary is outside the original source.");
            shift = 0;
            valid = true;
            for edit = obj.Edits
                first = edit.Start - 1;
                last = edit.End;
                if offset < first, break, end
                if first == last
                    if offset > first || affinity == "right", shift = shift + strlength(edit.Text); end
                elseif offset >= last
                    shift = shift + strlength(edit.Text) - (last - first);
                elseif offset > first
                    valid = false;
                    offset = NaN;
                    return
                end
            end
            offset = offset + shift;
        end

        function [spans, valid] = mapSpanCells(obj, spans)
            % mapSpanCells Transform optional ranges together using one vector pass per edit.
            arguments (Input)
                obj (1, 1) macd.source.SourcePatchBatch
                spans cell
            end
            arguments (Output)
                spans cell
                valid logical
            end
            valid = true(size(spans));
            present = find(~cellfun(@isempty, spans));
            if isempty(present), return, end
            ranges = [spans{present}];
            assert(isa(ranges, "macd.model.SourceSpan") && numel(ranges) == numel(present));
            first = [ranges.StartOffset] - 1;
            last = [ranges.EndOffset];
            known = first >= 0;
            assert(all(last(known) <= strlength(obj.BeforeText)), ...
                "macd:SourcePatchBatch:InvalidBoundary", "The boundary is outside the original source.");
            starts = first;
            ends = last;
            surviving = true(size(first));
            % Original coordinates determine every shift, including shared insertion boundaries.
            for edit = obj.Edits
                left = edit.Start - 1;
                right = edit.End;
                delta = strlength(edit.Text) - (right - left);
                if left == right
                    starts = starts + delta * (known & first >= left);
                    ends = ends + delta * (known & last > left);
                else
                    surviving = surviving & ~(known & ((first > left & first < right) | (last > left & last < right)));
                    starts = starts + delta * (known & first >= right);
                    ends = ends + delta * (known & last >= right);
                end
            end
            surviving = surviving & (~known | ends > starts);
            ranges = ranges.withMappedOffsets(starts + 1, ends, known & surviving);
            for index = 1:numel(present)
                if surviving(index), spans{present(index)} = ranges(index);
                else, spans{present(index)} = macd.model.SourceSpan.empty; end
            end
            valid(present) = surviving;
        end

        function [span, valid] = mapSpan(obj, span)
            % mapSpan Shift a surviving range or invalidate removed/partially changed tokens.
            arguments (Input)
                obj (1, 1) macd.source.SourcePatchBatch
                span macd.model.SourceSpan
            end
            arguments (Output)
                span macd.model.SourceSpan
                valid (1, 1) logical
            end
            valid = true;
            if isempty(span), return, end
            assert(isscalar(span));
            if ~span.isKnown(), return, end
            [first, startValid] = obj.mapBoundary(span.StartOffset - 1, "right");
            [last, endValid] = obj.mapBoundary(span.EndOffset, "left");
            valid = startValid && endValid && last > first;
            if valid
                span = macd.model.SourceSpan(first + 1, last);
            else
                span = macd.model.SourceSpan.empty;
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
