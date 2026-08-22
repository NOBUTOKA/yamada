classdef PropertyBatchValidator
    % PropertyBatchValidator Validate staged inspector values against one catalog surface.
    %   This static utility evaluates a PropertyTransaction against the effective
    %   PropertyDefinition array selected by ComponentRegistry. It has no UI and
    %   never mutates the document, so immediate and modal editors share exactly
    %   the same property and cross-property acceptance rules.

    methods (Static)
        function message = validate(definitions, transaction)
            % validate Check all staged values against the prospective effective state.
            arguments (Input)
                definitions macd.model.PropertyDefinition
                transaction (1, 1) macd.model.PropertyTransaction
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            changes = transaction.changes();
            for index = 1:numel(changes)
                definitionIndex = find([definitions.Path] == changes(index).Path, 1);
                if isempty(definitionIndex)
                    message = "This property is not available in the current component context.";
                    return
                end
                definition = definitions(definitionIndex);
                if ~definition.IsEditable || definition.AuditDisposition ~= "editable"
                    message = "This property is read-only.";
                    return
                end
                message = macd.validation.PropertyBatchValidator.validateValue( ...
                    definition, changes(index).Value, transaction);
                if strlength(message) > 0
                    return
                end
            end
        end
    end

    methods (Static, Access = private)
        function message = validateValue(definition, value, transaction)
            % validateValue Check one value and its cross-property constraints.
            arguments (Input)
                definition (1, 1) macd.model.PropertyDefinition
                value
                transaction (1, 1) macd.model.PropertyTransaction
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            schema = definition.ValueSchema;
            if isempty(value) && isfield(schema, "allowsEmpty") && schema.allowsEmpty
                return
            end
            if definition.Editor == "enum" && isfield(schema, "values") && ...
                    ~any(string(schema.values) == string(value))
                message = "Choose one of the declared values.";
                return
            end
            if definition.Editor == "number"
                message = macd.validation.PropertyBatchValidator.validateNumber(schema, value);
                if strlength(message) > 0
                    return
                end
            elseif definition.Editor == "numericVector"
                message = macd.validation.PropertyBatchValidator.validateNumericVector(schema, value);
                if strlength(message) > 0
                    return
                end
            elseif definition.Editor == "dateTime"
                message = macd.validation.PropertyBatchValidator.validateDateTime(schema, value);
                if strlength(message) > 0
                    return
                end
            elseif definition.Editor == "itemSelection"
                message = macd.validation.PropertyBatchValidator.validateItemSelection( ...
                    schema, value, transaction);
                if strlength(message) > 0
                    return
                end
            elseif isfield(schema, "shape") && string(schema.shape) == "fixedLengthVector" && ...
                    (~isvector(value) || ~isfield(schema, "fixedLength") || ...
                    numel(value) ~= schema.fixedLength)
                message = "Enter a vector with the required number of values.";
                return
            end
            if isfield(schema, "kind") && string(schema.kind) == "dayOfWeekList" && ...
                    ~macd.validation.PropertyBatchValidator.isDayOfWeekList(value)
                message = "Enter day numbers 1 through 7, a string vector, or a cell vector of day names.";
                return
            end
            if isfield(schema, "constraints")
                constraints = schema.constraints;
                if isstruct(constraints)
                    constraints = num2cell(constraints);
                end
                for constraint = constraints
                    rule = constraint{1};
                    switch string(rule.kind)
                        case "sameLengthAs"
                            referencePath = string(rule.property);
                            if transaction.hasValue(referencePath) && ...
                                    numel(value) ~= numel(transaction.value(referencePath))
                                message = "The value must have the same number of elements as " + ...
                                    referencePath + ".";
                                return
                            end
                        case "withinLimitsOf"
                            referencePath = string(rule.property);
                            if transaction.hasValue(referencePath)
                                message = macd.validation.PropertyBatchValidator.validateWithinDateLimits( ...
                                    value, transaction.value(referencePath));
                                if strlength(message) > 0
                                    return
                                end
                            end
                        case "strictlyIncreasing"
                            if numel(value) ~= 2 || value(1) >= value(2)
                                message = "The end date must be later than the start date.";
                                return
                            end
                        case "sortedAscending"
                            if numel(value) > 1 && any(value(1:end - 1) > value(2:end))
                                message = "Dates must be sorted in ascending order.";
                                return
                            end
                    end
                end
            end
        end

        function message = validateNumber(schema, value)
            % validateNumber Check one finite numeric scalar and documented bounds.
            message = "";
            if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
                message = "Enter one finite number.";
                return
            end
            if isfield(schema, "minimum") && value < schema.minimum
                message = "Value is below the allowed minimum.";
            elseif isfield(schema, "exclusiveMinimum") && schema.exclusiveMinimum && ...
                    isfield(schema, "minimum") && value <= schema.minimum
                message = "Value must be greater than the allowed minimum.";
            elseif isfield(schema, "maximum") && value > schema.maximum
                message = "Value is above the allowed maximum.";
            elseif isfield(schema, "exclusiveMaximum") && schema.exclusiveMaximum && ...
                    isfield(schema, "maximum") && value >= schema.maximum
                message = "Value must be less than the allowed maximum.";
            elseif isfield(schema, "integer") && schema.integer && value ~= floor(value)
                message = "Enter an integer value.";
            end
        end

        function message = validateNumericVector(schema, value)
            % validateNumericVector Check a finite or explicitly infinite numeric vector.
            message = "";
            allowsInfinity = isfield(schema, "allowsInfinity") && schema.allowsInfinity;
            if ~isnumeric(value) || (~isempty(value) && ~isvector(value)) || any(isnan(value)) || ...
                    (~allowsInfinity && any(~isfinite(value)))
                if allowsInfinity
                    message = "Enter a numeric vector without NaN.";
                else
                    message = "Enter a finite numeric vector.";
                end
                return
            end
            requiredLength = [];
            if isfield(schema, "fixedLength")
                requiredLength = schema.fixedLength;
            elseif isfield(schema, "length")
                requiredLength = schema.length;
            end
            if ~isempty(value) && ~isempty(requiredLength) && numel(value) ~= requiredLength
                message = "Enter a vector with the required number of values.";
            elseif isfield(schema, "minimum") && any(value < schema.minimum)
                message = "Vector values are below the allowed minimum.";
            elseif isfield(schema, "exclusiveMinimum") && schema.exclusiveMinimum && ...
                    isfield(schema, "minimum") && any(value <= schema.minimum)
                message = "Vector values must be greater than the allowed minimum.";
            elseif isfield(schema, "maximum") && any(value > schema.maximum)
                message = "Vector values are above the allowed maximum.";
            elseif isfield(schema, "exclusiveMaximum") && schema.exclusiveMaximum && ...
                    isfield(schema, "maximum") && any(value >= schema.maximum)
                message = "Vector values must be less than the allowed maximum.";
            end
        end

        function message = validateDateTime(schema, value)
            % validateDateTime Check one audited date-only datetime scalar or vector.
            arguments (Input)
                schema (1, 1) struct
                value
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            if ~isdatetime(value) || ~ismatrix(value)
                message = "Enter a datetime value.";
                return
            end
            if ~isempty(value.TimeZone) || any(~isnat(value) & ...
                    seconds(timeofday(value)) ~= 0, "all")
                message = "Dates must be timezone-free calendar dates.";
                return
            end
            if ~isfield(schema, "allowsNaT") || ~schema.allowsNaT
                if any(isnat(value), "all")
                    message = "This date property does not accept NaT.";
                    return
                end
            end
            shape = "any";
            if isfield(schema, "shape")
                shape = string(schema.shape);
            end
            switch shape
                case "scalar"
                    if ~isscalar(value)
                        message = "Enter one date.";
                    end
                case "fixedLengthVector"
                    length = 0;
                    if isfield(schema, "fixedLength")
                        length = schema.fixedLength;
                    end
                    if ~isvector(value) || numel(value) ~= length
                        message = "Enter the required number of dates.";
                    elseif isfield(schema, "orientation") && string(schema.orientation) == "row" && ...
                            size(value, 1) ~= 1
                        message = "Dates must be a row vector.";
                    end
                case "vector"
                    if ~isvector(value) && ~isempty(value)
                        message = "Enter a date vector.";
                    elseif isfield(schema, "orientation") && string(schema.orientation) == "column" && ...
                            ~isempty(value) && size(value, 2) ~= 1
                        message = "Dates must be a column vector.";
                    end
            end
        end

        function message = validateItemSelection(schema, value, transaction)
            % validateItemSelection Require selected literals to come from ItemsData or Items.
            arguments (Input)
                schema (1, 1) struct
                value
                transaction (1, 1) macd.model.PropertyTransaction
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            if ~transaction.hasValue("Items")
                % A source-backed or otherwise unavailable Items value cannot be
                % checked safely here.  The native editor only exposes candidates
                % when it can read Items, so do not misreport that state as an
                % empty list and reject an already selected literal.
                return
            end
            items = macd.validation.PropertyBatchValidator.itemSelectionCells( ...
                transaction.value("Items"));
            candidates = items;
            if transaction.hasValue("ItemsData") && ~isempty(transaction.value("ItemsData"))
                data = macd.validation.PropertyBatchValidator.itemSelectionCells( ...
                    transaction.value("ItemsData"));
                if numel(data) ~= numel(items)
                    message = "ItemsData must have the same number of values as Items.";
                    return
                end
                candidates = data;
            end
            if isempty(candidates)
                message = "Define at least one item before choosing a value.";
                return
            end
            selected = macd.validation.PropertyBatchValidator.itemSelectionCells(value);
            multiselect = false;
            if isfield(schema, "multiselectProperty")
                property = string(schema.multiselectProperty);
                multiselect = transaction.hasValue(property) && ...
                    macd.validation.PropertyBatchValidator.isOn(transaction.value(property));
            end
            if ~multiselect && numel(selected) ~= 1
                message = "Choose one item.";
                return
            end
            for index = 1:numel(selected)
                if ~any(cellfun(@(candidate) isequaln(candidate, selected{index}), candidates))
                    message = "Choose a value represented by Items.";
                    return
                end
            end
        end

        function values = itemSelectionCells(value)
            % itemSelectionCells Split selection-compatible scalar or vector forms into cells.
            arguments (Input)
                value
            end
            arguments (Output)
                values cell
            end

            if iscell(value)
                values = reshape(value, 1, []);
            elseif ischar(value) && isrow(value)
                values = {value};
            elseif isstring(value)
                values = num2cell(reshape(value, 1, []));
            elseif isvector(value)
                values = num2cell(reshape(value, 1, []));
            else
                values = cell(1, 0);
            end
        end

        function result = isOn(value)
            % isOn Interpret logical and documented on/off values for multi-selection state.
            result = (islogical(value) && isscalar(value) && value) || ...
                (((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && ...
                lower(string(value)) == "on");
        end

        function message = validateWithinDateLimits(value, limits)
            % validateWithinDateLimits Check a nonmissing scalar date against effective limits.
            arguments (Input)
                value
                limits
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            if ~isdatetime(value) || ~isscalar(value) || isnat(value) || ...
                    ~isdatetime(limits) || numel(limits) ~= 2 || any(isnat(limits))
                return
            end
            if value < limits(1) || value > limits(2)
                message = "The selected date must be within Limits.";
            end
        end

        function result = isDayOfWeekList(value)
            % isDayOfWeekList Identify one documented day-list representation.
            result = isempty(value) || (isnumeric(value) && isvector(value) && ...
                all(isfinite(value)) && all(value == floor(value)) && ...
                all(value >= 1 & value <= 7)) || ...
                (isstring(value) && isvector(value)) || ...
                (iscell(value) && isvector(value) && ...
                all(cellfun(@(item) ischar(item) && isrow(item), value)));
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
