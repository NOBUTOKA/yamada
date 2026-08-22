classdef UnknownSourceRegion
    % UnknownSourceRegion Retain a source statement the editor cannot interpret.
    %   This immutable value class records the original statement, its source
    %   location, and a machine-readable reason. It does not attempt to repair or
    %   evaluate the unknown code.
    %
    %   Example:
    %       region = macd.model.UnknownSourceRegion( ...
    %           "app.Label.Text = loadText()", span, "nonliteral-property");

    properties (SetAccess = private)
        % Text - Original statement text that remains outside supported parsing.
        Text string = ""
        % Span - Inclusive range of the original statement text.
        Span macd.model.SourceSpan = macd.model.SourceSpan.empty
        % Reason - Stable identifier explaining why the region is unknown.
        Reason string = ""
    end

    methods
        function obj = UnknownSourceRegion(text, span, reason)
            % UnknownSourceRegion Create an immutable unsupported-source record.
            arguments (Input)
                text string = ""
                span macd.model.SourceSpan = macd.model.SourceSpan.empty
                reason string = ""
            end
            arguments (Output)
                obj (1, 1) macd.model.UnknownSourceRegion
            end

            % Preserve the exact unsupported text and the reason for retaining it.
            obj.Text = text;
            obj.Span = span;
            obj.Reason = reason;
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
