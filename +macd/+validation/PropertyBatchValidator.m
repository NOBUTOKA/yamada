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
                    if string(rule.kind) ~= "sameLengthAs"
                        continue
                    end
                    referencePath = string(rule.property);
                    if ~transaction.hasValue(referencePath)
                        continue
                    end
                    if numel(value) ~= numel(transaction.value(referencePath))
                        message = "The value must have the same number of elements as " + ...
                            referencePath + ".";
                        return
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
