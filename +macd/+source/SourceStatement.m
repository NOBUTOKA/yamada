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

    methods
        function obj = SourceStatement(text, span)
            % SourceStatement Create an immutable statement and source range.
            arguments (Input)
                text string = ""
                span macd.model.SourceSpan = macd.model.SourceSpan.empty
            end
            arguments (Output)
                obj (1, 1) macd.source.SourceStatement
            end

            % Store lexical output without making semantic assumptions.
            obj.Text = text;
            obj.Span = span;
        end
    end
end

%{
MatlabAppClassDesigner - Lexically complete MATLAB source statement record.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
