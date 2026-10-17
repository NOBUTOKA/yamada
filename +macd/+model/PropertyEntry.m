classdef PropertyEntry < handle
    % PropertyEntry Retain one component property in the intermediate model.
    %   This handle class distinguishes editable literals from unevaluated,
    %   source-backed expressions and retains related diagnostics and metadata.
    %   It does not validate component-specific property support.

    properties (SetAccess = private)
        % Path - Full component property path, including nested property names.
        Path string = ""
        % ValueKind - Storage form: unset, literal, or expression.
        ValueKind string {mustBeMember(ValueKind, ["unset", "literal", "expression"])} = "unset"
        % LiteralValue - Safely editable literal value when ValueKind is literal.
        LiteralValue = []
        % SourceExpression - Unevaluated MATLAB expression retained from source.
        SourceExpression string = ""
        % IsEditable - Whether the editor may replace the stored value.
        IsEditable logical = true
        % Origin - Provenance label such as generated or parsed.
        Origin string = "generated"
    end

    properties
        % SourceSpan - Optional macd.model.SourceSpan for the source assignment.
        SourceSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % Diagnostics - Diagnostics associated with this property value.
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
        % Metadata - Extensible property data not interpreted by the core model.
        Metadata struct = struct()
    end

    properties (Access = private)
        InputClock macd.model.InputChangeClock = macd.model.InputChangeClock.empty
    end

    methods (Access = ?macd.model.ComponentRecord)
        function bindInputClock(obj, clock)
            % bindInputClock Track owned writes without retaining the owning document.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                clock (1, 1) macd.model.InputChangeClock
            end
            if ~isempty(obj.InputClock)
                if obj.InputClock ~= clock
                    obj.InputClock.disable();
                    clock.disable();
                end
                return
            end
            obj.InputClock = clock;
        end
    end

    methods (Access = private)
        function noteInput(obj, value)
            % noteInput Notify the token only after evaluation has attached it to a complete object.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            % Construction and materialization run without an attached token.
            if ~isempty(obj.InputClock), obj.InputClock.touch(value); end
        end
    end

    methods
        function set.Path(obj, value)
            % set.Path Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.Path = value;
            obj.noteInput(value);
        end

        function set.ValueKind(obj, value)
            % set.ValueKind Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.ValueKind = value;
            obj.noteInput(value);
        end

        function set.LiteralValue(obj, value)
            % set.LiteralValue Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.LiteralValue = value;
            obj.noteInput(value);
        end

        function set.SourceExpression(obj, value)
            % set.SourceExpression Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.SourceExpression = value;
            obj.noteInput(value);
        end

        function set.IsEditable(obj, value)
            % set.IsEditable Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.IsEditable = value;
            obj.noteInput(value);
        end

        function set.Origin(obj, value)
            % set.Origin Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.Origin = value;
            obj.noteInput(value);
        end

        function set.SourceSpan(obj, value)
            % set.SourceSpan Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.SourceSpan = value;
            obj.noteInput(value);
        end

        function set.Metadata(obj, value)
            % set.Metadata Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end
            obj.Metadata = value;
            obj.noteInput(value);
        end

        function record = toStruct(obj)
            % toStruct Retain independent current-value and source-binding snapshot data.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
            end
            arguments (Output)
                record (1, 1) struct
            end

            record = struct("Path", obj.Path, "ValueKind", obj.ValueKind, ...
                "LiteralValue", {obj.LiteralValue}, "SourceExpression", obj.SourceExpression, ...
                "IsEditable", obj.IsEditable, "Origin", obj.Origin, "SourceSpan", obj.SourceSpan, ...
                "Metadata", obj.Metadata, "Diagnostics", obj.Diagnostics);
        end

        function applySourceSetting(obj, setting)
            % applySourceSetting Project one original occurrence into the editable value view.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                setting (1, 1) macd.model.PropertySetting
            end

            % Parsed occurrences may replace earlier expressions without editing source.
            obj.ValueKind = setting.ValueKind;
            obj.LiteralValue = setting.LiteralValue;
            obj.SourceExpression = setting.SourceExpression;
            obj.IsEditable = setting.IsEditable;
            if ~obj.IsEditable && setting.ValueKind == "literal"
                obj.ValueKind = "expression";
                obj.SourceExpression = macd.source.LiteralEncoder.encode(setting.LiteralValue);
                obj.LiteralValue = [];
            end
            obj.SourceSpan = setting.SourceSpan;
            obj.Metadata.SourceSettingId = setting.Id;
            obj.Metadata.SettingMethod = setting.Method;
            obj.Metadata.SettingSyntax = setting.Syntax;
            obj.Metadata.ValueSpan = setting.ValueSpan;
            obj.Metadata.SourceSnapshotId = setting.SourceSnapshotId;
        end

        function obj = PropertyEntry(path, value, origin)
            % PropertyEntry Create a literal component property entry.
            arguments (Input)
                path string = ""
                value = []
                origin string = "generated"
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertyEntry
            end

            % Preserve property defaults for the no-input constructor.
            if nargin == 0
                return
            end

            % Store a new entry as an editable literal by default.
            obj.Path = path;
            obj.ValueKind = "literal";
            obj.LiteralValue = value;
            obj.Origin = origin;
        end

        function setLiteral(obj, value)
            % setLiteral Replace this entry with a safely representable value.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end

            % Clear any prior source expression when the literal is edited.
            obj.ValueKind = "literal";
            obj.LiteralValue = value;
            obj.SourceExpression = "";
        end

        function setSourceExpression(obj, expression)
            % setSourceExpression Retain an unevaluated expression as read-only.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                expression string
            end

            % Source expressions must never be treated as editable literals.
            obj.ValueKind = "expression";
            obj.LiteralValue = [];
            obj.SourceExpression = expression;
            obj.IsEditable = false;
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
