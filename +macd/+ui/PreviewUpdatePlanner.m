classdef PreviewUpdatePlanner
    % PreviewUpdatePlanner Order local native updates from resolved catalog dependencies.
    %   This planner reads only resolved values and editor-owned native controls.
    %   It never constructs a candidate document or executes application code.
    methods (Static)
        function indices = plan(states, requested, target)
            % plan Select changed values and required dependent writes in final-state order.
            arguments (Input)
                states (1, :) struct
                requested (1, :) string
                target
            end
            arguments (Output)
                indices (1, :) double
            end
            definitions = [states.Definition];
            paths = string({definitions.Path});
            count = numel(states);
            edges = false(count);
            effects = false(count);
            direct = ismember(paths, requested);
            for index = 1:count
                policy = definitions(index).Application;
                edges(ismember(paths, policy.ApplyAfter), index) = true;
                effects(index, ismember(paths, policy.AffectedPaths)) = true;
            end
            % Final implicit values follow the write that resolved their state.
            ids = string(arrayfun(@(state) state.Resolution.EffectSettingId, states));
            for index = find(direct)
                if strlength(ids(index)) == 0, continue, end
                affected = ids == ids(index) & ~direct & arrayfun(@(state) state.Resolution.IsKnown, states);
                % Final implicit values supersede constructor-order prerequisites.
                edges(affected, index) = false;
                edges(index, affected) = true;
            end
            edges(1:count + 1:end) = false;
            relations = edges | effects;
            related = direct;
            while true
                expanded = related | any(relations(related, :), 1) | any(relations(:, related), 2)';
                if isequal(expanded, related), break, end
                related = expanded;
            end
            % Compare public native values only within this dependency closure.
            needed = direct;
            for index = find(related & ~direct)
                resolution = states(index).Resolution;
                if ~resolution.IsKnown || ~definitions(index).IsEditable || ...
                        any(definitions(index).PreviewPolicy == ["skip", "notRendered"])
                    continue
                end
                [value, known] = macd.ui.PreviewUpdatePlanner.nativeValue(target, paths(index));
                needed(index) = ~known || ~macd.ui.PreviewUpdatePlanner.sameValue(value, resolution.EffectiveValue);
            end
            while true
                expanded = needed | any(relations(needed, :), 1);
                if isequal(expanded, needed), break, end
                needed = expanded;
            end
            writable = arrayfun(@(state) state.Resolution.IsKnown && ...
                state.Definition.IsEditable && ~any(state.Definition.PreviewPolicy == ["skip", "notRendered"]), states);
            indices = zeros(1, 0);
            % Existing catalog edges plus implicit-effect edges preserve setter order.
            while any(needed)
                ready = find(needed & ~any(edges(needed, :), 1), 1);
                if isempty(ready)
                    error("macd:PreviewUpdatePlanner:CyclicEffects", "Native update effects require reconstruction.");
                end
                if writable(ready), indices(end + 1) = ready; end %#ok<AGROW>
                needed(ready) = false;
            end
        end
    end
    methods (Static, Access = private)
        function [value, known] = nativeValue(target, path)
            % nativeValue Read one public native property without evaluating expressions.
            arguments (Input)
                target
                path (1, 1) string
            end
            arguments (Output)
                value
                known (1, 1) logical
            end
            value = []; known = false;
            parts = split(path, ".");
            try
                value = target.(parts(1));
                if numel(parts) == 2, value = value.(parts(2)); end
                known = numel(parts) <= 2;
            catch
                % Unavailable getters require an explicit final write or reconstruction.
            end
        end

        function result = sameValue(left, right)
            % sameValue Normalize native text representations at the graphics API boundary.
            arguments (Input)
                left
                right
            end
            arguments (Output)
                result (1, 1) logical
            end
            if ischar(left) || isstring(left) || isa(left, "matlab.lang.OnOffSwitchState")
                if ischar(right) || isstring(right), left = string(left); right = string(right); end
            end
            result = isequaln(left, right);
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
