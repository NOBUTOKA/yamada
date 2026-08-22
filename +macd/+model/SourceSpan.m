classdef SourceSpan
    % SourceSpan Describe an optional range in MATLAB source text.
    %   This value class is responsible only for retaining validated offsets and
    %   reporting whether they identify a known range. It does not read or edit
    %   source text.

    properties (SetAccess = private)
        % StartOffset - One-based start offset, or zero for an unknown span.
        StartOffset double = 0
        % EndOffset - Inclusive end offset, or zero for an unknown span.
        EndOffset double = 0
    end

    methods
        function obj = SourceSpan(startOffset, endOffset)
            % SourceSpan Create a source location range description.
            % Start and end offsets are zero when the location is unknown.
            arguments (Input)
                startOffset = 0
                endOffset = 0
            end
            arguments (Output)
                obj (1, 1) macd.model.SourceSpan
            end

            % Preserve the default unknown span for the no-input constructor.
            if nargin == 0
                return
            end

            % Reject invalid ranges before storing normalized double values.
            validateattributes(startOffset, "numeric", ...
                ["scalar", "integer", "nonnegative"]);
            validateattributes(endOffset, "numeric", ...
                {"scalar", "integer", ">=", startOffset});
            obj.StartOffset = double(startOffset);
            obj.EndOffset = double(endOffset);
        end

        function result = isKnown(obj)
            % isKnown Return true when the span contains a usable source range.
            arguments (Input)
                obj (1, 1) macd.model.SourceSpan
            end
            arguments (Output)
                result (1, 1) logical
            end

            % An unknown span uses zero offsets by convention.
            result = obj.StartOffset > 0 && obj.EndOffset >= obj.StartOffset;
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
