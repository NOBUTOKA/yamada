classdef PositionAliasPolicy
    % PositionAliasPolicy Resolve the reviewed position aliases of simple UI controls.
    %   Only catalog-selected families use these rules. Container and axes
    %   geometry is outside this policy. Explicit source records remain intact.

    methods (Static)
        function [entries, reason] = forPreview(entries, component, document, registry)
            % forPreview Project known shared geometry once instead of replaying skipped aliases.
            arguments (Input)
                entries macd.model.PropertyEntry
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                entries macd.model.PropertyEntry
                reason (1, 1) string
            end
            reason = "";
            parent = document.getComponent(component.ParentId);
            parentFactory = "";
            if ~isempty(parent), parentFactory = parent.Factory; end
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
            aliases = definitions(arrayfun(@macd.model.PositionAliasPolicy.applies, definitions));
            if isempty(aliases), return, end
            entries = entries(~ismember(string({entries.Path}), string({aliases.Path})));
            if ~any(string({aliases.Path}) == "Position"), return, end
            states = macd.model.PropertyStateResolver.resolve(component, definitions, document, registry);
            position = states(string({states.Path}) == "Position");
            if strlength(position.EffectSettingId) == 0, return, end
            if position.IsKnown
                entries(end + 1) = macd.model.PropertyEntry("Position", position.EffectiveValue, "generated");
            else
                reason = position.Reason;
            end
        end

        function result = applies(definition)
            % applies Identify a property in a reviewed position alias family.
            arguments (Input)
                definition (1, 1) macd.model.PropertyDefinition
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = any(definition.Application.EffectPolicy == ["positionAlias", "squarePositionAlias"]);
        end

        function [states, message] = apply(states, definitions, path, id)
            % apply Propagate one public alias setter to its shared getters without editing inputs.
            arguments (Input)
                states macd.model.PropertyState
                definitions macd.model.PropertyDefinition
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            paths = string({states.Path});
            index = find(paths == path, 1);
            targets = reshape(find(arrayfun(@macd.model.PositionAliasPolicy.applies, definitions)), 1, []);
            message = "";
            value = [];
            known = states(index).IsKnown;
            reason = "An uncertain position alias may change every shared getter.";
            code = "position-alias";

            % A grid owns geometry even if a source alias contains literal numbers.
            if ~any(paths == "Position")
                known = false;
                reason = "The parent layout manages position; an explicit alias does not determine its geometry.";
                code = "layout-managed";
            elseif known
                value = states(index).EffectiveValue;
                if ~isnumeric(value) || ~isreal(value) || numel(value) ~= 4 || ...
                        any(~isfinite(value), "all") || any(value(3:4) < 0)
                    known = false;
                    message = "Position requires four finite real numbers and nonnegative width and height.";
                    reason = message;
                    code = "constraint";
                else
                    value = reshape(double(value), 1, 4);
                    if definitions(index).Application.EffectPolicy == "squarePositionAlias"
                        value = macd.model.PositionGeometry.normalize(value, ...
                            macd.model.PositionGeometry.constraint("squarePositionAlias"));
                    end
                    reason = "";
                end
            end
            for target = targets
                states(target) = states(target).withEffective(value, known, id, reason, code);
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
