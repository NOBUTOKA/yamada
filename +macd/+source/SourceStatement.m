classdef SourceStatement
    % SourceStatement Represent one lexically complete MATLAB source statement.
    %   This immutable value class retains comment-free statement text and its
    %   original source range. It does not interpret MATLAB syntax or evaluate
    %   source code.
    %
    %   Example:
    %       statement = macd.source.SourceStatement( ...
    %           "app.Label.Text = 'Ready'", macd.model.SourceSpan(1, 25));

    properties (SetAccess = private)
        % Text - Comment-free source text for the complete statement.
        Text string = ""
        % Span - Inclusive offset range of the original statement.
        Span macd.model.SourceSpan = macd.model.SourceSpan.empty
    end

    properties (Dependent, SetAccess = private)
        % CodeOffsets - Current absolute offsets projected from the statement-local code positions.
        CodeOffsets double
    end

    properties (Access = private)
        RelativeCodeOffsets double = zeros(1, 0)
    end

    methods
        function obj = SourceStatement(text, span, codeOffsets)
            % SourceStatement Create an immutable statement and source range.
            arguments (Input)
                text string = ""
                span macd.model.SourceSpan = macd.model.SourceSpan.empty
                codeOffsets (1, :) double = zeros(1, 0)
            end
            arguments (Output)
                obj (1, 1) macd.source.SourceStatement
            end

            % Store lexical output without making semantic assumptions.
            obj.Text = text;
            obj.Span = span;
            if ~isempty(codeOffsets) && numel(codeOffsets) ~= strlength(text)
                error("macd:SourceStatement:InvalidOffsets", ...
                    "Code offsets must identify every code unit of the statement text.");
            end
            base = 0;
            if ~isempty(span), base = span.StartOffset; end
            obj.RelativeCodeOffsets = codeOffsets - base;
        end

        function offsets = get.CodeOffsets(obj)
            % get.CodeOffsets Project current absolute positions without mutating stored local offsets.
            arguments (Input)
                obj (1, 1) macd.source.SourceStatement
            end
            arguments (Output)
                offsets (1, :) double
            end
            base = 0;
            if ~isempty(obj.Span), base = obj.Span.StartOffset; end
            offsets = obj.RelativeCodeOffsets + base;
        end

        function obj = withSpan(obj, span)
            % withSpan Relocate unchanged syntax while retaining shared statement-local positions.
            arguments (Input)
                obj (1, 1) macd.source.SourceStatement
                span (1, 1) macd.model.SourceSpan
            end
            arguments (Output)
                obj (1, 1) macd.source.SourceStatement
            end
            assert(~isempty(obj.Span) && obj.Span.isKnown() && span.isKnown() && ...
                span.EndOffset - span.StartOffset == obj.Span.EndOffset - obj.Span.StartOffset, ...
                "macd:SourceStatement:ChangedSyntax", "Changed statement syntax requires local rescanning.");
            obj.Span = span;
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
