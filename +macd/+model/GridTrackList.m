classdef GridTrackList
    % GridTrackList Validate literal GridLayout row and column track lists.
    %   This utility accepts the documented R2024a representations for the
    %   RowHeight and ColumnWidth properties without evaluating source text.
    %   It deliberately accepts only tokens that the public GridLayout setter
    %   accepts, so model validation and Safe Preview share one boundary.
    %
    %   Example:
    %       message = macd.model.GridTrackList.validate({'1x', 'fit', 120});

    methods (Static)
        function message = validate(value)
            % validate Check one documented GridLayout track-list literal.
            arguments (Input)
                value
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            [items, message] = macd.model.GridTrackList.parseItems(value);
            if strlength(message) > 0
                return
            end
            for index = 1:numel(items)
                message = macd.model.GridTrackList.validateItem(items{index});
                if strlength(message) > 0
                    return
                end
            end
        end

        function values = items(value)
            % items Convert a supported list container into row-cell track tokens.
            arguments (Input)
                value
            end
            arguments (Output)
                values cell
            end

            [values, message] = macd.model.GridTrackList.parseItems(value);
            if strlength(message) > 0
                error("macd:GridTrackList:InvalidValue", "%s", message);
            end
        end
    end

    methods (Static, Access = private)
        function [values, message] = parseItems(value)
            % parseItems Normalize documented containers while rejecting unsupported shapes.
            arguments (Input)
                value
            end
            arguments (Output)
                values cell
                message (1, 1) string
            end

            values = cell(1, 0);
            message = "";
            if isnumeric(value)
                if isempty(value) || ~isvector(value)
                    message = "Enter a numeric, string, or cell vector of track values.";
                    return
                end
                values = num2cell(reshape(value, 1, []));
            elseif isstring(value)
                if ~isvector(value) && ~isempty(value)
                    message = "Enter a numeric, string, or cell vector of track values.";
                    return
                end
                values = num2cell(reshape(value, 1, []));
            elseif iscell(value)
                if ~isvector(value) && ~isempty(value)
                    message = "Enter a numeric, string, or cell vector of track values.";
                    return
                end
                values = reshape(value, 1, []);
            else
                message = "Enter a numeric, string, or cell vector of track values.";
            end
        end

        function message = validateItem(value)
            % validateItem Check one fixed, fit-content, or weighted track token.
            arguments (Input)
                value
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            if isnumeric(value)
                if ~isscalar(value) || ~isreal(value) || ~isfinite(value) || value < 0
                    message = "Fixed track sizes must be finite nonnegative numbers.";
                end
                return
            end
            if (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))
                token = lower(string(value));
                if token == "fit"
                    return
                end
                match = regexp(char(token), "^(?:\d+(?:\.\d*)?|\.\d+)[x]$", "once");
                if ~isempty(match)
                    return
                end
            end
            message = "Track values must be nonnegative numbers, fit, or nonnegative x weights.";
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
