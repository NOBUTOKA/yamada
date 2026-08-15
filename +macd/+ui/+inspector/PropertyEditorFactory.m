classdef PropertyEditorFactory
    % PropertyEditorFactory Create allowlisted native inspector editors.
    %   This factory maps catalog editor identifiers to project-owned controls and
    %   never evaluates catalog text as MATLAB code.

    methods (Static)
        function control = create(parent, definition, commitFcn)
            % create Construct one editor control for a typed property definition.
            arguments (Input)
                parent
                definition (1, 1) macd.model.PropertyDefinition
                commitFcn (1, 1) function_handle
            end

            switch definition.Editor
                case {"logical", "onOff"}
                    control = uicheckbox(parent, "Text", "", "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(source.Value));
                    control.UserData = definition.Editor;
                case "enum"
                    items = macd.ui.inspector.PropertyEditorFactory.enumItems(definition);
                    control = uidropdown(parent, "Items", cellstr(items), ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn( ...
                        macd.source.LiteralEncoder.encode(char(source.Value))));
                case "asset"
                    control = uipanel(parent, "BorderType", "none", ...
                        "Tag", "macd-inspector-asset-editor");
                    grid = uigridlayout(control, [1 2], "Padding", [0 0 0 0], ...
                        "ColumnWidth", {"1x", 34}, "ColumnSpacing", 3);
                    edit = uieditfield(grid, "text", "Tag", "macd-inspector-asset-path", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(string(source.Value)));
                    browse = uibutton(grid, "Text", "...", "Tag", "macd-inspector-asset-browse", ...
                        "ButtonPushedFcn", @(~, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.browseAsset(control, commitFcn));
                    control.UserData = struct("Edit", edit, "Browse", browse);
                case "number"
                    control = uieditfield(parent, "numeric", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(source.Value));
                    macd.ui.inspector.PropertyEditorFactory.applyNumberSchema( ...
                        control, definition.ValueSchema);
                case "color"
                    control = uibutton(parent, "Text", "", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.pickColor(source, commitFcn));
                case "stringList"
                    control = uibutton(parent, "Text", "", ...
                        "Tag", "macd-inspector-string-list-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.StringListEditorDialog.open(source.UserData, commitFcn));
                case "multilineText"
                    control = uitextarea(parent, "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.commitTextArea(source, commitFcn));
                case "structuredData"
                    control = uibutton(parent, "Text", "Edit data", ...
                        "Tag", "macd-inspector-structured-data-editor", ...
                        "ButtonPushedFcn", @(source, ~) ...
                        macd.ui.inspector.StructuredDataEditorDialog.open(source.UserData, commitFcn));
                case {"literal", "text", "numericVector"}
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor", ...
                        "ValueChangedFcn", @(source, ~) commitFcn(string(source.Value)));
                case "url"
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor-url", ...
                        "ValueChangedFcn", @(source, ~) ...
                        macd.ui.inspector.PropertyEditorFactory.commitUrl(source, commitFcn));
                otherwise
                    control = uieditfield(parent, "text", ...
                        "Tag", "macd-inspector-property-editor");
                    control.UserData = "readOnlyFallback";
            end
        end

        function result = supportsEditing(definition)
            % supportsEditing Return whether the definition has a native editable adapter.
            arguments (Input)
                definition (1, 1) macd.model.PropertyDefinition
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = any(definition.Editor == ["literal", "text", "logical", ...
                "onOff", "enum", "number", "numericVector", "color", "stringList", ...
                "multilineText", "url", "asset", "structuredData"]);
            if definition.Editor == "enum" && ~isfield(definition.ValueSchema, "values")
                result = false;
            end
        end

        function synchronize(control, value, isEditable, rawValue)
            % synchronize Load a model value into one factory-created editor.
            arguments (Input)
                control
                value (1, 1) string
                isEditable (1, 1) logical
                rawValue = []
            end

            if isprop(control, "Tag") && control.Tag == "macd-inspector-asset-editor"
                parts = control.UserData;
                if ischar(rawValue) && isrow(rawValue)
                    parts.Edit.Value = string(rawValue);
                elseif isstring(rawValue) && isscalar(rawValue)
                    parts.Edit.Value = rawValue;
                else
                    parts.Edit.Value = string(value);
                end
                parts.Edit.Editable = isEditable;
                parts.Browse.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            elseif isa(control, "matlab.ui.control.CheckBox")
                logicalValue = value;
                if ~isempty(rawValue)
                    logicalValue = string(rawValue);
                end
                control.Value = logicalValue == "on" || logicalValue == "true" || logicalValue == "1";
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            elseif isa(control, "matlab.ui.control.DropDown")
                % Prefer the raw char or string value over its inspector literal rendering.
                selectedValue = value;
                if (ischar(rawValue) && isrow(rawValue)) || ...
                        (isstring(rawValue) && isscalar(rawValue))
                    selectedValue = string(rawValue);
                end
                % Retain documented or runtime defaults absent from an incomplete enum contract.
                items = string(control.Items);
                if ~any(items == selectedValue)
                    control.Items = cellstr([items(:); selectedValue]);
                end
                control.Value = char(selectedValue);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
            elseif isa(control, "matlab.ui.control.NumericEditField")
                number = str2double(value);
                if ~isnan(number)
                    control.Value = number;
                end
                control.Editable = isEditable;
            elseif isa(control, "matlab.ui.control.Button")
                control.Text = char(value);
                control.Enable = macd.ui.inspector.PropertyEditorFactory.onOff(isEditable);
                if control.Tag == "macd-inspector-string-list-editor"
                    control.UserData = rawValue;
                    control.Text = macd.ui.inspector.PropertyEditorFactory.listSummary(rawValue);
                    return
                end
                if control.Tag == "macd-inspector-structured-data-editor"
                    control.UserData = rawValue;
                    control.Text = macd.ui.inspector.PropertyEditorFactory.structuredSummary(rawValue, value);
                    return
                end
                [rgb, isLiteral] = macd.source.MatlabLiteralParser.parse(value);
                if isLiteral && isnumeric(rgb) && isequal(size(rgb), [1 3]) && ...
                        all(isfinite(rgb)) && all(rgb >= 0) && all(rgb <= 1)
                    control.BackgroundColor = rgb;
                    control.UserData = rgb;
                else
                    control.BackgroundColor = [0.94 0.94 0.94];
                    control.UserData = [];
                end
            elseif isa(control, "matlab.ui.control.TextArea")
                if iscell(rawValue) || (isstring(rawValue) && ~isscalar(rawValue))
                    control.Value = rawValue;
                elseif ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue))
                    control.Value = {char(rawValue)};
                else
                    control.Value = {char(value)};
                end
                control.UserData = rawValue;
                control.Editable = isEditable;
            elseif isprop(control, "UserData") && ...
                    isequal(control.Tag, "macd-inspector-property-editor-url")
                control.UserData = rawValue;
                if ischar(rawValue) && isrow(rawValue)
                    control.Value = string(rawValue);
                elseif isstring(rawValue) && isscalar(rawValue)
                    control.Value = rawValue;
                else
                    control.Value = string(value);
                end
                control.Editable = isEditable;
            else
                control.Value = char(value);
                control.Editable = isEditable && ~macd.ui.inspector.PropertyEditorFactory.isReadOnlyFallback(control);
            end
        end

        function value = editorValue(control)
            % editorValue Return the current adapter value without parsing or committing it.
            arguments (Input)
                control
            end

            if isprop(control, "Tag") && control.Tag == "macd-inspector-asset-editor"
                value = control.UserData.Edit.Value;
            elseif isa(control, "matlab.ui.control.CheckBox") || ...
                    isa(control, "matlab.ui.control.NumericEditField") || ...
                    isa(control, "matlab.ui.control.EditField") || ...
                    isa(control, "matlab.ui.control.TextArea")
                value = control.Value;
            elseif isa(control, "matlab.ui.control.Button")
                value = control.UserData;
            else
                value = [];
            end
        end

        function restoreDraft(control, value)
            % restoreDraft Restore an uncommitted adapter value without invoking its callback.
            arguments (Input)
                control
                value
            end

            if isprop(control, "Tag") && control.Tag == "macd-inspector-asset-editor"
                parts = control.UserData;
                parts.Edit.Value = value;
            elseif isa(control, "matlab.ui.control.CheckBox") || ...
                    isa(control, "matlab.ui.control.NumericEditField") || ...
                    isa(control, "matlab.ui.control.EditField") || ...
                    isa(control, "matlab.ui.control.TextArea")
                control.Value = value;
            elseif isa(control, "matlab.ui.control.Button")
                control.UserData = value;
                if control.Tag == "macd-inspector-string-list-editor"
                    control.Text = macd.ui.inspector.PropertyEditorFactory.listSummary(value);
                elseif control.Tag == "macd-inspector-structured-data-editor"
                    control.Text = macd.ui.inspector.PropertyEditorFactory.structuredSummary(value, "");
                elseif isnumeric(value) && isequal(size(value), [1 3])
                    control.BackgroundColor = value;
                end
            end
        end
    end

    methods (Static, Access = private)
        function items = enumItems(definition)
            % enumItems Extract finite enum choices from the definition schema.
            items = strings(1, 0);
            if isfield(definition.ValueSchema, "values")
                items = string(definition.ValueSchema.values);
            end
            if isempty(items)
                items = "";
            end
        end

        function result = onOff(value)
            % onOff Convert a logical enable flag to the MATLAB UI token.
            if value
                result = "on";
            else
                result = "off";
            end
        end

        function result = isReadOnlyFallback(control)
            % isReadOnlyFallback Identify controls created for deferred editor kinds.
            result = isstring(control.UserData) && isscalar(control.UserData) && ...
                control.UserData == "readOnlyFallback";
        end

        function applyNumberSchema(control, schema)
            % applyNumberSchema Apply supported scalar constraints to a numeric editor.
            arguments (Input)
                control (1, 1) matlab.ui.control.NumericEditField
                schema (1, 1) struct
            end

            if isfield(schema, "minimum")
                control.Limits(1) = schema.minimum;
            end
            if isfield(schema, "maximum")
                control.Limits(2) = schema.maximum;
            end
            if isfield(schema, "integer") && schema.integer
                control.RoundFractionalValues = "on";
            end
        end

        function pickColor(control, commitFcn)
            % pickColor Open the native picker and commit a valid RGB row vector.
            arguments (Input)
                control (1, 1) matlab.ui.control.Button
                commitFcn (1, 1) function_handle
            end

            current = control.UserData;
            if ~isnumeric(current) || ~isequal(size(current), [1 3])
                current = [0 0 0];
            end
            selected = uisetcolor(current);
            if isnumeric(selected) && isequal(size(selected), [1 3]) && ...
                    all(isfinite(selected)) && all(selected >= 0) && all(selected <= 1)
                commitFcn(selected);
            end
            owner = ancestor(control, "figure");
            if ~isempty(owner) && isvalid(owner)
                focus(owner);
            end
        end

        function text = listSummary(value)
            % listSummary Describe a string-list value without flattening its shape.
            if isstring(value)
                text = sprintf("%d-by-%d string", size(value, 1), size(value, 2));
            elseif iscell(value)
                text = sprintf("%d item cell list", numel(value));
            else
                text = "Edit list";
            end
        end

        function text = structuredSummary(value, fallback)
            % structuredSummary Describe safe structured data without coercing its type.
            try
                text = macd.source.LiteralEncoder.encode(value);
            catch
                text = string(fallback);
                if strlength(text) == 0
                    text = "Unsupported data";
                end
            end
            if strlength(text) > 42
                text = extractBefore(text, 40) + "...";
            end
        end

        function commitTextArea(control, commitFcn)
            % commitTextArea Preserve scalar char/string representation when possible.
            draft = control.Value;
            original = control.UserData;
            if ischar(original) && isrow(original) && iscell(draft) && numel(draft) == 1
                draft = char(draft{1});
            elseif isstring(original) && isscalar(original) && iscell(draft) && numel(draft) == 1
                draft = string(draft{1});
            elseif iscell(draft)
                % TextArea returns visual lines as a column; source literals use a row cell array.
                draft = reshape(draft, 1, []);
            end
            commitFcn(draft);
        end

        function commitUrl(control, commitFcn)
            % commitUrl Commit a URL as plain text while preserving char/string style.
            draft = string(control.Value);
            if contains(draft, newline) || contains(draft, char(13))
                return
            end
            original = control.UserData;
            if ischar(original)
                commitFcn(char(draft));
            else
                commitFcn(draft);
            end
        end

        function browseAsset(container, commitFcn)
            % browseAsset Select an asset path without reading or evaluating the file.
            [name, folder] = uigetfile({"*.*", "All files"}, "Select asset");
            if isequal(name, 0) || isequal(folder, 0)
                return
            end
            selected = fullfile(folder, name);
            original = container.UserData.Edit.Value;
            if ischar(original)
                commitFcn(char(selected));
            else
                commitFcn(string(selected));
            end
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
