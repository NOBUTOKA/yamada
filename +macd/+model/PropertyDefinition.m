classdef PropertyDefinition
    % PropertyDefinition Describe one property supported by a component type.
    %   This immutable value class owns registry-level property capabilities,
    %   defaults, editability, and extension metadata. It does not store the
    %   current value or source state of a component instance; PropertyEntry owns
    %   that document-specific information.
    %
    %   Example:
    %       definition = macd.model.PropertyDefinition( ...
    %           "Text", "", true, true, struct());

    properties (SetAccess = private)
        % Path - Full supported property path, including nested property names.
        Path string = ""
        % DefaultValue - Default literal used when the definition has a default.
        DefaultValue = []
        % HasDefault - Whether DefaultValue is defined for this property.
        HasDefault logical = false
        % IsEditable - Whether the editor may change this property.
        IsEditable logical = true
        % Metadata - Extensible property capability and editor metadata.
        Metadata struct = struct()
        % Editor - Allowlisted editor adapter identifier for this property.
        Editor string = "literal"
        % Validator - Allowlisted literal validation identifier for this property.
        Validator string = "matlabLiteral"
        % PreviewPolicy - Whether a committed literal may reach Safe Preview.
        PreviewPolicy string = "apply"
        % ResetPolicy - Allowlisted rule for resetting an explicit value.
        ResetPolicy string = "remove"
        % DisplayName - User-facing property label supplied by the catalog.
        DisplayName string = ""
        % Category - Stable inspector category identifier supplied by the catalog.
        Category string = "General"
        % Order - Deterministic order within the inspector category.
        Order double = 0
        % ValueSchema - Typed literal constraints and adapter-specific options.
        ValueSchema struct = struct()
        % ApplicableStyles - Styles for which this property definition applies.
        ApplicableStyles string = strings(1, 0)
        % AuditDisposition - Catalog audit decision such as editable or readOnly.
        AuditDisposition string = "editable"
    end

    methods
        function obj = PropertyDefinition( ...
                path, defaultValue, hasDefault, isEditable, metadata)
            % PropertyDefinition Create an immutable property capability record.
            arguments (Input)
                path string = ""
                defaultValue = []
                hasDefault logical = false
                isEditable logical = true
                metadata struct = struct()
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertyDefinition
            end

            % Store the normalized capability data as one validated value object.
            obj.Path = path;
            obj.DefaultValue = defaultValue;
            obj.HasDefault = hasDefault;
            obj.IsEditable = isEditable;
            obj.Metadata = metadata;
            if isfield(metadata, "editor"), obj.Editor = string(metadata.editor); end
            if isfield(metadata, "validator"), obj.Validator = string(metadata.validator); end
            if isfield(metadata, "previewPolicy"), obj.PreviewPolicy = string(metadata.previewPolicy); end
            if isfield(metadata, "resetPolicy"), obj.ResetPolicy = string(metadata.resetPolicy); end
            if isfield(metadata, "displayName"), obj.DisplayName = string(metadata.displayName); end
            if isfield(metadata, "category"), obj.Category = string(metadata.category); end
            if isfield(metadata, "order"), obj.Order = double(metadata.order); end
            if isfield(metadata, "valueSchema"), obj.ValueSchema = metadata.valueSchema; end
            if isfield(metadata, "applicableStyles"), obj.ApplicableStyles = string(metadata.applicableStyles); end
            if isfield(metadata, "auditDisposition"), obj.AuditDisposition = string(metadata.auditDisposition); end
            if strlength(obj.DisplayName) == 0
                obj.DisplayName = path;
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
