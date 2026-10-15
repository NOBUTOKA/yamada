classdef PropertyStateResolver
    % PropertyStateResolver Resolve audited setter effects without executing source.
    %   The resolver replays certain explicit writes, overlays replacement
    %   requests at their original occurrences, and applies pending settings in
    %   canonical order. Unsupported effects stay unknown. Constructor Value
    %   validation is grouped; mode and unit arguments retain their own order.

    methods (Static)
        function [states, diagnostics] = resolve(component, definitions, document, registry)
            % resolve Return independent explicit/requested/effective states and proven errors.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                definitions macd.model.PropertyDefinition
                document macd.model.DocumentModel = macd.model.DocumentModel.empty
                registry macd.model.ComponentRegistry = macd.model.ComponentRegistry.empty
            end
            arguments (Output)
                states macd.model.PropertyState
                diagnostics macd.model.Diagnostic
            end

            % Defaults are audited seeds, never new PropertyEntry objects.
            states = macd.model.PropertyState.empty;
            diagnostics = macd.model.Diagnostic.empty;
            for definition = reshape(definitions, 1, [])
                entry = component.getProperty(definition.Path);
                settings = component.getSettings(definition.Path);
                last = macd.model.PropertySetting.empty;
                if ~isempty(settings), last = settings(end); end
                states(end + 1) = macd.model.PropertyState(definition, entry, last); %#ok<AGROW>
            end

            % Source additions use the same actual placement as generation and Preview.
            if ~isempty(document) && ~isempty(registry) && ...
                    macd.source.PropertySourcePlan.needsPlan(document, component)
                try
                    plan = macd.source.PropertySourcePlan.plan(document, component, registry);
                    resolved = macd.model.PropertyStateResolver.resolve(plan.Component, definitions);
                    for index = 1:numel(states)
                        effective = resolved(index);
                        id = macd.model.PropertyStateResolver.originalEffectId(component, plan.Component, effective.EffectSettingId);
                        states(index) = states(index).withEffective(effective.EffectiveValue, effective.IsKnown, ...
                            id, effective.Reason, effective.ReasonCode);
                    end
                catch exception
                    diagnostics(end + 1) = macd.model.Diagnostic("unsafe-property-insertion", "error", ...
                        string(exception.message), component.Id, component.SourceSpans.Creation);
                    for index = 1:numel(states)
                        states(index) = states(index).withEffective([], false, "unresolved-placement", string(exception.message), "placement");
                    end
                end
                return
            end

            % Keep source execution order, treating each constructor as one group.
            settings = component.Settings(string({component.Settings.Method}) ~= "generated");
            [~, order] = sort([settings.Sequence]);
            settings = settings(order);
            cursor = 1;
            while cursor <= numel(settings)
                groupEnd = cursor;
                if settings(cursor).Method == "nameValue"
                    while groupEnd < numel(settings) && settings(groupEnd + 1).Method == "nameValue" && ...
                            settings(groupEnd + 1).StatementId == settings(cursor).StatementId
                        groupEnd = groupEnd + 1;
                    end
                end
                group = settings(cursor:groupEnd);
                if settings(cursor).Method == "nameValue" && defersConstructorValue(definitions)
                    % MATLAB validates domain-backed constructor Value against the group.
                    group = [group(string({group.Path}) ~= "Value"), group(string({group.Path}) == "Value")];
                end
                for setting = group
                    entry = component.getProperty(setting.Path);
                    if isempty(entry), continue, end
                    value = setting.LiteralValue;
                    known = setting.ValueKind == "literal" && setting.IsCertain;
                    if known && isfield(entry.Metadata, "SourceSettingId") && ...
                            string(entry.Metadata.SourceSettingId) == setting.Id && entry.ValueKind == "literal"
                        value = entry.LiteralValue;
                    end
                    [states, message] = macd.model.PropertyStateResolver.apply( ...
                        states, definitions, setting.Path, value, known, setting.Id);
                    if strlength(message) > 0
                        diagnostics(end + 1) = macd.model.Diagnostic("invalid-property-sequence", "error", ...
                            setting.Path + ": " + message, component.Id, setting.SourceSpan); %#ok<AGROW>
                    end
                end
                cursor = groupEnd + 1;
            end

            % New settings have no source span yet; legacy entries also use this path.
            entries = component.Properties;
            if ~isempty(settings), entries = entries([entries.Origin] == "generated"); end
            if ~isempty(entries), entries = macd.model.PropertyApplicationPlanner.order(entries, definitions); end
            for entry = entries
                id = "pending:" + component.Id + ":" + entry.Path;
                if isfield(entry.Metadata, "PendingSettingId"), id = string(entry.Metadata.PendingSettingId); end
                [states, message] = macd.model.PropertyStateResolver.apply(states, definitions, ...
                    entry.Path, entry.LiteralValue, entry.ValueKind == "literal" && entry.IsEditable, id);
                if strlength(message) > 0
                    diagnostics(end + 1) = macd.model.Diagnostic("invalid-property-sequence", "error", ...
                        entry.Path + ": " + message, component.Id); %#ok<AGROW>
                end
            end
        end

        function transaction = transaction(states)
            % transaction Copy only resolved effective values into a validator snapshot.
            arguments (Input)
                states macd.model.PropertyState
            end
            arguments (Output)
                transaction (1, 1) macd.model.PropertyTransaction
            end
            values = cell(1, numel(states));
            for index = 1:numel(states), values{index} = states(index).EffectiveValue; end
            transaction = macd.model.PropertyTransaction(string({states.Path}), values, [states.IsKnown]);
        end

        function result = matchesRequested(state, value)
            % matchesRequested Compare a resolved result with a literal edit request.
            arguments (Input)
                state (1, 1) macd.model.PropertyState
                value
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = state.IsKnown && macd.model.PropertyStateResolver.equivalent(state.EffectiveValue, value);
        end

        function result = valuesEquivalent(first, second)
            % valuesEquivalent Compare literal values using native scalar-text equivalence.
            arguments (Input)
                first
                second
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = macd.model.PropertyStateResolver.equivalent(first, second);
        end
    end

    methods (Static, Access = private)
        function id = originalEffectId(original, candidate, candidateId)
            % originalEffectId Map candidate-only offsets back to immutable original or pending identities.
            arguments (Input)
                original (1, 1) macd.model.ComponentRecord
                candidate (1, 1) macd.model.ComponentRecord
                candidateId (1, 1) string
            end
            arguments (Output)
                id (1, 1) string
            end
            id = "";
            effect = candidate.Settings(string({candidate.Settings.Id}) == candidateId);
            if isempty(effect), return, end
            path = effect(end).Path;
            before = original.getSettings(path);
            after = candidate.getSettings(path);
            ordinal = find(string({after.Id}) == candidateId, 1, 'last');
            if ~isempty(before) && ~isempty(ordinal)
                id = before(min(ordinal, numel(before))).Id;
            end
        end

        function [states, message] = apply(states, definitions, path, value, known, id)
            % apply Resolve one supported write and its allowlisted sibling effects.
            arguments (Input)
                states macd.model.PropertyState
                definitions macd.model.PropertyDefinition
                path (1, 1) string
                value
                known (1, 1) logical
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            paths = string({states.Path});
            index = find(paths == path, 1);
            if isempty(index), return, end
            previous = states;
            states(index) = states(index).withEffective(value, known, id, "The source value or its execution is uncertain.", "source");
            if known, states(index) = states(index).withEffective(value, true, id); end
            valueIndex = find(paths == "Value", 1);
            family = "none";
            if ~isempty(valueIndex), family = definitions(valueIndex).Application.EffectPolicy; end

            % Each family implements only reviewed semantics, never arbitrary setters.
            if family == "boundedValue" && any(path == ["Value", "Limits"])
                [states, message] = macd.model.PropertyStateResolver.bounded(states, definitions(valueIndex), path, id);
            elseif family == "numericValue" && any(path == ["Value", "Limits", ...
                    "LowerLimitInclusive", "UpperLimitInclusive", "RoundFractionalValues", "AllowEmpty"])
                [states, message] = macd.model.PropertyStateResolver.numeric(states, path, id);
            elseif family == "itemSelection" && any(path == ["Value", "Items", "ItemsData", "Editable", "Multiselect"])
                [states, message] = macd.model.PropertyStateResolver.items(states, previous, path, id);
            elseif family == "textValue" && any(path == ["Value", "CharacterLimits"])
                [states, message] = macd.model.PropertyStateResolver.text(states, path, id);
            end

            % Tick arrays force manual mode; automatic modes compute nonliteral arrays.
            if definitions(index).Application.EffectPolicy == "tickMode"
                target = find(paths == path + "Mode", 1);
                if ~isempty(target)
                    reason = "";
                    if ~known, reason = "An uncertain tick setter may change this mode."; end
                    states(target) = states(target).withEffective("manual", known, id, reason);
                end
            elseif endsWith(path, "Mode") && known && ...
                    ((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && string(value) == "auto"
                base = extractBefore(path, strlength(path) - 3);
                target = find(paths == base, 1);
                if ~isempty(target) && definitions(target).Application.EffectPolicy == "tickMode"
                    states(target) = states(target).withEffective([], false, id, "Automatic mode computes this value at runtime.", "automatic");
                end
            end

            % Unit conversion depends on native parent geometry and display metrics.
            if any(path == ["Units", "FontUnits"])
                targetPath = "Position";
                if path == "FontUnits", targetPath = "FontSize"; end
                target = find(paths == targetPath, 1);
                same = known && previous(index).IsKnown && ...
                    macd.model.PropertyStateResolver.equivalent(value, previous(index).EffectiveValue);
                if ~isempty(target) && ~same
                    states(target) = states(target).withEffective([], false, id, ...
                        path + " changed after " + targetPath + "; native unit conversion is not statically resolved.", "unit-conversion");
                end
            end
        end

        function [states, message] = bounded(states, definition, path, id)
            % bounded Validate scalar or range values and apply inclusive clamping.
            arguments (Input)
                states macd.model.PropertyState
                definition (1, 1) macd.model.PropertyDefinition
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [limits, limitsKnown] = stateValue(states, "Limits");
            [value, valueKnown] = stateValue(states, "Value");
            if ~limitsKnown
                states = setUnknown(states, "Value", id, "Limits is not known.", "constraint");
                return
            end
            if ~isnumeric(limits) || numel(limits) ~= 2 || any(~isfinite(limits)) || limits(1) >= limits(2)
                message = "Limits must contain two finite increasing bounds.";
            elseif valueKnown
                wrongSize = (definition.Editor == "number" && ~isscalar(value)) || ...
                    (isfield(definition.ValueSchema, "fixedLength") && numel(value) ~= definition.ValueSchema.fixedLength);
                if ~isnumeric(value) || isempty(value) || any(~isfinite(value)) || wrongSize
                    message = "Value must contain finite numbers.";
                elseif path == "Value" && any(value < limits(1) | value > limits(2))
                    message = "Value is outside Limits at this source occurrence.";
                elseif path == "Limits"
                    states = setEffective(states, "Value", min(max(value, limits(1)), limits(2)), id);
                end
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function [states, message] = numeric(states, path, id)
            % numeric Resolve numeric bounds, rounding, and conditional empty values.
            arguments (Input)
                states macd.model.PropertyState
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [limits, limitsKnown] = stateValue(states, "Limits");
            [value, valueKnown] = stateValue(states, "Value");
            [lower, lowerKnown] = stateSwitch(states, "LowerLimitInclusive");
            [upper, upperKnown] = stateSwitch(states, "UpperLimitInclusive");
            [rounding, roundingKnown] = stateSwitch(states, "RoundFractionalValues");
            [allowEmpty, emptyKnown] = stateSwitch(states, "AllowEmpty");
            if ~all([limitsKnown lowerKnown upperKnown roundingKnown emptyKnown])
                states = setUnknown(states, "Value", id, "A numeric value constraint is not known.", "constraint");
                return
            end
            if ~isnumeric(limits) || numel(limits) ~= 2 || any(isnan(limits)) || ...
                    limits(1) > limits(2) || (limits(1) == limits(2) && (~lower || ~upper))
                message = "The numeric constraints leave no allowed range.";
            elseif valueKnown
                if isempty(value)
                    if allowEmpty, return, end
                    if path == "Value"
                        message = "An empty Value requires AllowEmpty on.";
                    else
                        value = 0;
                    end
                elseif ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
                    message = "Value must be one finite number or an allowed empty array.";
                end
                if strlength(message) == 0
                    if rounding
                        minimum = ceil(limits(1));
                        maximum = floor(limits(2));
                        if ~lower && minimum == limits(1), minimum = minimum + 1; end
                        if ~upper && maximum == limits(2), maximum = maximum - 1; end
                        if minimum > maximum
                            message = "The configured limits contain no allowed integer.";
                        else
                            states = setEffective(states, "Value", min(max(round(value), minimum), maximum), id);
                        end
                    else
                        below = value < limits(1) || (~lower && value == limits(1));
                        above = value > limits(2) || (~upper && value == limits(2));
                        if path == "Value" && (below || above)
                            message = "Value is outside the allowed bounds at this source occurrence.";
                        elseif (below && ~lower) || (above && ~upper)
                            states = setUnknown(states, "Value", id, "Native adjustment to an exclusive bound is not yet resolved.", "adjustment");
                        else
                            states = setEffective(states, "Value", min(max(value, limits(1)), limits(2)), id);
                        end
                    end
                end
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function [states, message] = text(states, path, id)
            % text Enforce nonempty text length and model limit-induced clearing.
            arguments (Input)
                states macd.model.PropertyState
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [limits, limitsKnown] = stateValue(states, "CharacterLimits");
            [value, valueKnown] = stateValue(states, "Value");
            if ~limitsKnown
                states = setUnknown(states, "Value", id, "CharacterLimits is not known.", "constraint");
                return
            end
            if ~isnumeric(limits) || numel(limits) ~= 2 || ~isfinite(limits(1)) || limits(1) < 0 || ...
                    any(isnan(limits)) || limits(1) > limits(2) || any(limits ~= floor(limits))
                message = "CharacterLimits must contain increasing nonnegative integer bounds.";
            elseif valueKnown
                if ~((ischar(value) && (isrow(value) || isempty(value))) || (isstring(value) && isscalar(value)))
                    message = "Value must be scalar text.";
                else
                    count = strlength(string(value));
                    if count > 0 && (count < limits(1) || count > limits(2))
                        if path == "Value"
                            message = "The text length is outside CharacterLimits.";
                        else
                            states = setEffective(states, "Value", '', id);
                        end
                    end
                end
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function [states, message] = items(states, previous, path, id)
            % items Resolve reviewed item-domain selection and index-preserving data changes.
            arguments (Input)
                states macd.model.PropertyState
                previous macd.model.PropertyState
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [items, itemsKnown] = stateValue(states, "Items");
            [data, dataKnown] = stateValue(states, "ItemsData");
            [value, valueKnown] = stateValue(states, "Value");
            if ~itemsKnown || ~dataKnown
                states = setUnknown(states, "Value", id, "Items or ItemsData is not known.", "constraint");
                return
            end
            labels = selectionCells(items);
            candidates = labels;
            if ~isempty(data), candidates = selectionCells(data); end
            candidates = candidates(1:min(numel(labels), numel(candidates)));
            [multi, multiKnown] = stateSwitch(states, "Multiselect");
            if ~any(string({states.Path}) == "Multiselect"), multiKnown = true; end
            [editable, editableKnown] = stateSwitch(states, "Editable");
            if ~any(string({states.Path}) == "Editable"), editableKnown = true; end
            if ~multiKnown || ~editableKnown
                states = setUnknown(states, "Value", id, "The selection mode is not known.", "constraint");
                return
            end
            if ~valueKnown, return, end
            selected = selectionCells(value);
            if path == "ItemsData"
                [oldData, oldDataKnown] = stateValue(previous, "ItemsData");
                [oldValue, oldValueKnown] = stateValue(previous, "Value");
                if oldDataKnown && oldValueKnown && (isempty(oldData) ~= isempty(data))
                    oldCandidates = labels;
                    if ~isempty(oldData), oldCandidates = selectionCells(oldData); end
                    selected = cell(1, 0);
                    for item = selectionCells(oldValue)
                        match = find(cellfun(@(candidate) macd.model.PropertyStateResolver.equivalent(candidate, item{1}), oldCandidates), 1);
                        if ~isempty(match) && match <= numel(candidates), selected{end + 1} = candidates{match}; end %#ok<AGROW>
                    end
                end
            end
            represented = cellfun(@(item) any(cellfun(@(candidate) ...
                macd.model.PropertyStateResolver.equivalent(candidate, item), candidates)), selected);
            freeText = editable && ((ischar(value) && (isrow(value) || isempty(value))) || ...
                (isstring(value) && isscalar(value)));
            if path == "Value"
                if (~multi && numel(selected) ~= 1 && ~isempty(selected)) || ...
                        (~all(represented) && ~freeText) || (isempty(selected) && ~any(string({states.Path}) == "Multiselect"))
                    message = "Value is not represented by the current item domain or selection mode.";
                end
            else
                selected = selected(represented);
                if isempty(selected) && ~isempty(candidates), selected = candidates(1); end
                if ~multi && numel(selected) > 1, selected = selected(1); end
                if isempty(selected)
                    value = {};
                elseif multi
                    if ~isempty(data) && isnumeric(data), value = [selected{:}]; else, value = selected; end
                else
                    value = selected{1};
                end
                states = setEffective(states, "Value", value, id);
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function result = equivalent(first, second)
            % equivalent Compare native scalar text independently of char/string spelling.
            arguments (Input)
                first
                second
            end
            arguments (Output)
                result (1, 1) logical
            end
            text = @(value) (ischar(value) && (isrow(value) || isempty(value))) || ...
                (isstring(value) && isscalar(value));
            result = isequaln(first, second);
            if text(first) && text(second), result = isequaln(string(first), string(second)); end
        end
    end
end

function result = defersConstructorValue(definitions)
% defersConstructorValue Identify constructor values with group-validated domains.
arguments (Input)
    definitions macd.model.PropertyDefinition
end
arguments (Output)
    result (1, 1) logical
end
index = find(string({definitions.Path}) == "Value", 1);
result = ~isempty(index) && (any(definitions(index).Application.EffectPolicy == ...
    ["boundedValue", "numericValue", "itemSelection", "textValue"]) || definitions(index).Editor == "dateTime");
end

function [value, known] = stateValue(states, path)
% stateValue Read an independently resolved value without falling back to a source literal.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
end
arguments (Output)
    value
    known (1, 1) logical
end
index = find(string({states.Path}) == path, 1);
known = ~isempty(index) && states(index).IsKnown;
value = [];
if known, value = states(index).EffectiveValue; end
end

function [value, known] = stateSwitch(states, path)
% stateSwitch Read a known scalar documented on/off state.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
end
arguments (Output)
    value (1, 1) logical
    known (1, 1) logical
end
[raw, known] = stateValue(states, path);
value = false;
if known
    if (islogical(raw) || isnumeric(raw)) && isscalar(raw)
        value = logical(raw);
    elseif (ischar(raw) && isrow(raw)) || (isstring(raw) && isscalar(raw))
        value = string(raw) == "on";
        known = any(string(raw) == ["on", "off"]);
    else
        known = false;
    end
end
end

function states = setEffective(states, path, value, id)
% setEffective Replace only the effective projection of one derived sibling.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
    value
    id (1, 1) string
end
arguments (Output)
    states macd.model.PropertyState
end
index = find(string({states.Path}) == path, 1);
if ~isempty(index), states(index) = states(index).withEffective(value, true, id); end
end

function states = setUnknown(states, path, id, reason, code)
% setUnknown Retain a reason instead of inventing an effective value.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
    id (1, 1) string
    reason (1, 1) string
    code (1, 1) string = "effect"
end
arguments (Output)
    states macd.model.PropertyState
end
index = find(string({states.Path}) == path, 1);
if ~isempty(index), states(index) = states(index).withEffective([], false, id, reason, code); end
end

function values = selectionCells(value)
% selectionCells Split item domains without evaluating or changing scalar text values.
arguments (Input)
    value
end
arguments (Output)
    values cell
end
if iscell(value)
    values = reshape(value, 1, []);
elseif ischar(value)
    values = {value};
else
    values = num2cell(reshape(value, 1, []));
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
