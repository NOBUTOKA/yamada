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

        function tracks = describe(value)
            % describe Normalize a valid track list into display-independent typed tokens.
            arguments (Input)
                value
            end
            arguments (Output)
                tracks (1, :) struct
            end

            values = macd.model.GridTrackList.items(value);
            tracks = repmat(struct("kind", "", "value", 0, "label", ""), 1, numel(values));
            for index = 1:numel(values)
                item = values{index};
                tracks(index).label = string(item);
                if isnumeric(item)
                    tracks(index).kind = "fixed";
                    tracks(index).value = double(item);
                elseif lower(string(item)) == "fit"
                    tracks(index).kind = "fit";
                    tracks(index).value = 0;
                else
                    tracks(index).kind = "flexible";
                    tracks(index).value = str2double(extractBefore(lower(string(item)), "x"));
                end
            end
        end

        function result = replace(value, index, kind, amount)
            % replace Replace one token and return a canonical safe literal container.
            arguments (Input)
                value
                index (1, 1) double
                kind (1, 1) string
                amount (1, 1) double = 0
            end
            arguments (Output)
                result
            end

            descriptions = macd.model.GridTrackList.describe(value);
            if ~isfinite(index) || index ~= floor(index) || index < 1 || ...
                    index > numel(descriptions)
                error("macd:GridTrackList:InvalidIndex", ...
                    "Track index must identify an existing track.");
            end
            if ~any(kind == ["fit", "fixed", "flexible"])
                error("macd:GridTrackList:InvalidKind", ...
                    "Track kind must be fit, fixed, or flexible.");
            end
            if kind ~= "fit" && (~isfinite(amount) || amount < 0)
                error("macd:GridTrackList:InvalidAmount", ...
                    "Fixed sizes and flexible weights must be finite nonnegative numbers.");
            end

            values = cell(1, numel(descriptions));
            for itemIndex = 1:numel(descriptions)
                values{itemIndex} = macd.model.GridTrackList.literalFor( ...
                    descriptions(itemIndex).kind, descriptions(itemIndex).value);
            end
            values{index} = macd.model.GridTrackList.literalFor(kind, amount);
            if all(cellfun(@isnumeric, values))
                result = cell2mat(values);
            elseif all(cellfun(@(item) ischar(item) || ...
                    (isstring(item) && isscalar(item)), values))
                result = string(values);
            else
                result = values;
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

        function value = literalFor(kind, amount)
            % literalFor Encode one normalized token as a source-safe MATLAB literal value.
            arguments (Input)
                kind (1, 1) string
                amount (1, 1) double
            end
            arguments (Output)
                value
            end

            switch kind
                case "fixed"
                    value = amount;
                case "fit"
                    value = "fit";
                case "flexible"
                    value = string(num2str(amount, 15)) + "x";
                otherwise
                    error("macd:GridTrackList:InvalidKind", ...
                        "Track kind must be fit, fixed, or flexible.");
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
