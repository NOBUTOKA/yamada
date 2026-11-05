classdef PositionGeometry
    % PositionGeometry Share finite Position constraints across model and editor inputs.
    %   Reviewed policies select fixed ratios, slider thickness, or independent
    %   linear gauge dimensions. Decoration and parent layout are not calculated.

    methods (Static)
        function result = applies(policy)
            % applies Identify reviewed native size constraints.
            arguments (Input)
                policy (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = any(policy == ["squarePosition", "squarePositionAlias", ...
                "sliderPosition", "switchPosition", "semicircularPosition", "linearPosition"]);
        end

        function spec = constraint(policy, orientation, known)
            % constraint Describe the current aspect ratio or fixed dimension.
            arguments (Input)
                policy (1, 1) string
                orientation (1, 1) string = ""
                known (1, 1) logical = false
            end
            arguments (Output)
                spec (1, 1) struct
            end
            spec = struct("Ratio", NaN, "FixedIndex", 0, "FixedValue", 3, "Known", true);
            if any(policy == ["squarePosition", "squarePositionAlias"])
                spec.Ratio = 1;
            elseif any(policy == ["sliderPosition", "switchPosition"])
                spec.Known = known && any(orientation == ["horizontal", "vertical"]);
                if ~spec.Known, return, end
                if policy == "sliderPosition"
                    spec.FixedIndex = 4;
                    if orientation == "vertical", spec.FixedIndex = 3; end
                else
                    spec.Ratio = 45 / 20;
                    if orientation == "vertical", spec.Ratio = 20 / 45; end
                end
            elseif policy == "semicircularPosition"
                spec.Known = known && any(orientation == ["north", "south", "east", "west"]);
                if ~spec.Known, return, end
                spec.Ratio = 120 / 65;
                if any(orientation == ["east", "west"]), spec.Ratio = 65 / 120; end
            end
        end

        function result = valid(value)
            % valid Check a finite native rectangle with nonnegative dimensions.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = isnumeric(value) && isreal(value) && isvector(value) && ...
                numel(value) == 4 && all(isfinite(value), "all") && all(value(3:4) >= 0);
        end

        function value = normalize(value, spec)
            % normalize Apply the reviewed native bounding-box or thickness rule.
            arguments (Input)
                value (1, 4) double {mustBeFinite}
                spec (1, 1) struct
            end
            arguments (Output)
                value (1, 4) double
            end
            if ~spec.Known, return, end
            if spec.FixedIndex > 0, value(spec.FixedIndex) = spec.FixedValue; end
            if isnan(spec.Ratio), return, end
            if value(4) == 0 || value(3) / value(4) > spec.Ratio
                value(3) = value(4) * spec.Ratio;
            elseif value(3) / value(4) < spec.Ratio
                value(4) = value(3) / spec.Ratio;
            end
        end

        function value = edit(value, index, number, spec)
            % edit Change one field and update its linked partner before one commit.
            arguments (Input)
                value (1, 4) double {mustBeFinite}
                index (1, 1) double {mustBeInteger, mustBeInRange(index, 1, 4)}
                number (1, 1) double {mustBeFinite}
                spec (1, 1) struct
            end
            arguments (Output)
                value (1, 4) double
            end
            if index == spec.FixedIndex || ~spec.Known, return, end
            value(index) = number;
            if ~isnan(spec.Ratio)
                if index == 3, value(4) = number / spec.Ratio; end
                if index == 4, value(3) = number * spec.Ratio; end
            end
            value = yamada.model.PositionGeometry.normalize(value, spec);
        end

        function value = resize(value, before, kind, spec)
            % resize Preserve the opposite edges while applying shared size constraints.
            arguments (Input)
                value (1, 4) double {mustBeFinite}
                before (1, 4) double {mustBeFinite}
                kind (1, 1) string
                spec (1, 1) struct
            end
            arguments (Output)
                value (1, 4) double
            end
            if ~spec.Known, value = before; return, end
            if ~isnan(spec.Ratio)
                horizontal = contains(kind, "e") || contains(kind, "w");
                vertical = contains(kind, "n") || contains(kind, "s");
                index = 3;
                if (vertical && ~horizontal) || (vertical && ...
                        abs(value(4) - before(4)) * spec.Ratio > abs(value(3) - before(3)))
                    index = 4;
                end
                value = yamada.model.PositionGeometry.edit(value, index, value(index), spec);
                if contains(kind, "w"), value(1) = before(1) + before(3) - value(3); end
                if contains(kind, "s"), value(2) = before(2) + before(4) - value(4); end
            elseif spec.FixedIndex > 0
                value(spec.FixedIndex) = spec.FixedValue;
                value(spec.FixedIndex - 2) = before(spec.FixedIndex - 2);
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
