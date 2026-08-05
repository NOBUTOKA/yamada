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
        end
    end
end

%{
MatlabAppClassDesigner - Typed registry definition for a component property.
Copyright (C) 2026 MatlabAppClassDesigner contributors

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
