classdef ComponentRecord < handle
    % ComponentRecord Represent one UI component without hard-coded UI types.
    %   This handle class owns component identity, hierarchy links, creation data,
    %   property entries, and source metadata. Component-specific rules belong to
    %   ComponentRegistry rather than this record.
    %
    %   Example:
    %       label = macd.model.ComponentRecord( ...
    %           "label-1", "StatusLabel", "uilabel", ...
    %           "matlab.ui.control.Label", "generated");
    %       label.setProperty("Text", "Ready");

    properties (SetAccess = private)
        % Id - Stable identity used for hierarchy and source associations.
        Id string = ""
        % Factory - MATLAB UI factory function used to create the component.
        Factory string = ""
        % DeclaredType - MATLAB class declared for the generated app property.
        DeclaredType string = ""
        % Origin - Provenance label such as generated or parsed.
        Origin string = "generated"
        % Children - Ordered stable identities of direct child components.
        Children string = strings(1, 0)
        % Properties - Ordered macd.model.PropertyEntry handle objects.
        Properties macd.model.PropertyEntry = macd.model.PropertyEntry.empty
        % Settings - Original source occurrences and pending generated occurrences.
        Settings macd.model.PropertySetting = macd.model.PropertySetting.empty
    end

    properties
        % Name - Editable MATLAB property name for the component.
        Name string = ""
        % ParentId - Stable identity of the parent component, or empty for a root.
        ParentId string = ""
        % IsEditable - Whether the component can be changed by the editor.
        IsEditable logical = true
        % Diagnostics - Diagnostics currently associated with this component.
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
        % SourceSpans - Named source locations retained from parsed code.
        SourceSpans struct = struct("Declaration", [], "Creation", [])
        % Metadata - Extensible component-specific data not interpreted by the model.
        Metadata struct = struct()
    end

    properties (Dependent)
        % CreationArguments - Factory arguments projected from source settings and requested values.
        CreationArguments cell
    end

    properties (Access = private)
        InputClock macd.model.InputChangeClock = macd.model.InputChangeClock.empty
        CreationArgumentData cell = {}
    end

    methods (Access = ?macd.model.DocumentModel)
        function bindInputClock(obj, clock)
            % bindInputClock Track owned writes without retaining the owning document.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
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
            for entry = reshape(obj.Properties, 1, []), entry.bindInputClock(clock); end
        end
    end

    methods (Access = private)
        function noteInput(obj, value)
            % noteInput Notify the token only after evaluation has attached it to a complete object.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            % Construction and materialization run without an attached token.
            if ~isempty(obj.InputClock), obj.InputClock.touch(value); end
        end

        function noteInputCollection(obj, value)
            % noteInputCollection Attach new owned records before recording their collection write.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value macd.model.PropertyEntry
            end
            if isempty(obj.InputClock), return, end
            for item = reshape(value, 1, []), item.bindInputClock(obj.InputClock); end
            obj.InputClock.touch([]);
        end
    end

    methods
        function set.Id(obj, value)
            % set.Id Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Id = value;
            obj.noteInput(value);
        end

        function set.Factory(obj, value)
            % set.Factory Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Factory = value;
            obj.noteInput(value);
        end

        function set.DeclaredType(obj, value)
            % set.DeclaredType Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.DeclaredType = value;
            obj.noteInput(value);
        end

        function set.Origin(obj, value)
            % set.Origin Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Origin = value;
            obj.noteInput(value);
        end

        function set.Children(obj, value)
            % set.Children Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Children = value;
            obj.noteInput(value);
        end

        function set.Properties(obj, value)
            % set.Properties Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Properties = value;
            obj.noteInputCollection(obj.Properties);
        end

        function set.Settings(obj, value)
            % set.Settings Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Settings = value;
            obj.noteInput(value);
        end

        function set.Name(obj, value)
            % set.Name Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Name = value;
            obj.noteInput(value);
        end

        function set.ParentId(obj, value)
            % set.ParentId Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.ParentId = value;
            obj.noteInput(value);
        end

        function set.IsEditable(obj, value)
            % set.IsEditable Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.IsEditable = value;
            obj.noteInput(value);
        end

        function set.SourceSpans(obj, value)
            % set.SourceSpans Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.SourceSpans = value;
            obj.noteInput(value);
        end

        function set.Metadata(obj, value)
            % set.Metadata Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.Metadata = value;
            obj.noteInput(value);
        end

        function set.CreationArgumentData(obj, value)
            % set.CreationArgumentData Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            obj.CreationArgumentData = value;
            obj.noteInput(value);
        end

        function records = settingSnapshot(obj)
            % settingSnapshot Serialize all immutable occurrences for reversible document operations.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                records (1, :) struct
            end

            records = struct("Path", {}, "Value", {}, "Location", {});
            for setting = obj.Settings
                records(end + 1) = setting.toStruct(); %#ok<AGROW>
            end
        end

        function entry = restoreProperty(obj, record)
            % restoreProperty Restore one captured value and binding without replacing unrelated handles.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                record (1, 1) struct
            end
            arguments (Output)
                entry (1, 1) macd.model.PropertyEntry
            end

            entry = macd.model.PropertyEntry(record.Path, record.LiteralValue, record.Origin);
            if record.ValueKind == "expression", entry.setSourceExpression(record.SourceExpression); end
            entry.SourceSpan = record.SourceSpan;
            entry.Metadata = record.Metadata;
            entry.Diagnostics = record.Diagnostics;
            index = find(string({obj.Properties.Path}) == record.Path, 1);
            if isempty(index), obj.Properties(end + 1) = entry; else, obj.Properties(index) = entry; end
        end

        function factoryArguments = get.CreationArguments(obj)
            % get.CreationArguments Project constructor values without a second mutable source owner.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                factoryArguments cell
            end

            factoryArguments = obj.CreationArgumentData;
            for setting = obj.Settings
                index = setting.FactoryArgumentIndex;
                if index == 0, continue, end
                value = setting.LiteralValue;
                entry = obj.getProperty(setting.Path);
                if ~isempty(entry) && entry.ValueKind == "literal" && ...
                        isfield(entry.Metadata, "SourceSettingId") && entry.Metadata.SourceSettingId == setting.Id
                    value = entry.LiteralValue;
                end
                factoryArguments{index} = value;
            end
        end

        function set.CreationArguments(obj, values)
            % set.CreationArguments Initialize legacy factory inputs before source occurrences exist.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                values cell
            end

            if any(string({obj.Settings.Method}) ~= "generated")
                error("macd:ComponentRecord:SourceOwnedArguments", ...
                    "Parsed constructor values must be edited through their property settings.");
            end
            obj.CreationArgumentData = values;
        end

        function recordSetting(obj, setting)
            % recordSetting Append a parsed occurrence and refresh the current value projection.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                setting (1, 1) macd.model.PropertySetting
            end

            % Original occurrences and editable requested values have distinct owners.
            obj.Settings(end + 1) = setting;
            entry = obj.getProperty(setting.Path);
            if isempty(entry)
                entry = macd.model.PropertyEntry(setting.Path, [], obj.Origin);
                obj.Properties(end + 1) = entry;
            end
            entry.applySourceSetting(setting);
        end

        function settings = getSettings(obj, path)
            % getSettings Return a property's original occurrences with the last at the end.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                path (1, 1) string
            end
            arguments (Output)
                settings macd.model.PropertySetting
            end

            settings = obj.Settings(string({obj.Settings.Path}) == path);
        end

        function restoreSettings(obj, records)
            % restoreSettings Restore immutable source occurrences without changing pending values.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                records struct
            end

            settings = macd.model.PropertySetting.empty;
            for record = records
                settings(end + 1) = macd.model.PropertySetting( ...
                    record.Path, record.Value, record.Location); %#ok<AGROW>
            end
            obj.Settings = settings;
        end

        function obj = ComponentRecord(id, name, factory, declaredType, origin)
            % ComponentRecord Create an extensible intermediate component record.
            arguments (Input)
                id string = ""
                name string = ""
                factory string = ""
                declaredType string = ""
                origin string = "generated"
            end
            arguments (Output)
                obj (1, 1) macd.model.ComponentRecord
            end

            % Preserve property defaults for the no-input constructor.
            if nargin == 0
                return
            end

            % Store identity and source-origin fields in the shared string form.
            obj.Id = id;
            obj.Name = name;
            obj.Factory = factory;
            obj.DeclaredType = declaredType;
            obj.Origin = origin;
        end

        function restoreProperties(obj, records)
            % restoreProperties Replace property handles from independent snapshot records.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                records struct
            end

            % Build the complete replacement before updating the live collection.
            entries = macd.model.PropertyEntry.empty;
            for record = records
                entry = macd.model.PropertyEntry(record.Path, record.LiteralValue, record.Origin);
                if record.ValueKind == "expression"
                    entry.setSourceExpression(record.SourceExpression);
                elseif record.ValueKind ~= "literal"
                    error("macd:ComponentRecord:InvalidSnapshot", "Unsupported property storage kind.");
                end
                entry.SourceSpan = record.SourceSpan;
                entry.Metadata = record.Metadata;
                entry.Diagnostics = record.Diagnostics;
                entries(end + 1) = entry; %#ok<AGROW>
            end
            obj.Properties = entries;
        end

        function entry = setProperty(obj, path, value)
            % setProperty Add or update an editable property by its full path.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                path string
                value
            end
            arguments (Output)
                entry (1, 1) macd.model.PropertyEntry
            end

            % Reuse an existing entry so its metadata and source span survive.
            entry = obj.getProperty(path);
            if isempty(entry)
                entry = macd.model.PropertyEntry(path, value, "generated");
                sequence = 1;
                if ~isempty(obj.Settings), sequence = max([obj.Settings.Sequence]) + 1; end
                setting = macd.model.PropertySetting(path, value, struct( ...
                    "SourceSnapshotId", "pending:" + obj.Id, "Sequence", sequence));
                obj.Settings(end + 1) = setting;
                entry.Metadata.PendingSettingId = setting.Id;
                obj.Properties(end + 1) = entry;
            else
                if ~entry.IsEditable
                    error("macd:ComponentRecord:ReadOnlyProperty", ...
                        "Property ""%s"" is source-backed and read-only.", path);
                end
                entry.setLiteral(value);
            end
        end

        function entry = getProperty(obj, path)
            % getProperty Find a property entry by path, or return empty.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                path string
            end
            arguments (Output)
                entry macd.model.PropertyEntry
            end

            % Preserve insertion order while performing the path lookup.
            entry = macd.model.PropertyEntry.empty;
            for index = 1:numel(obj.Properties)
                candidate = obj.Properties(index);
                if candidate.Path == path
                    entry = candidate;
                    return
                end
            end
        end

        function removeProperty(obj, path)
            % removeProperty Remove one editable property entry by full path.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                path string
            end

            % Keep removal explicit so undo can restore an absent property state.
            entry = obj.getProperty(path);
            if isempty(entry)
                return
            end
            obj.Properties(obj.Properties == entry) = [];
            pending = string({obj.Settings.Path}) == path & string({obj.Settings.Method}) == "generated";
            obj.Settings(pending) = [];
        end

        function addChild(obj, childId)
            % addChild Append a child identifier unless it is already present.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                childId string
            end

            % Child order is significant for deterministic source generation.
            if ~any(obj.Children == childId)
                obj.Children(end + 1) = childId;
            end
        end

        function removeChild(obj, childId)
            % removeChild Remove one child identifier after a document deletion.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                childId string
            end

            % Keep the ordered hierarchy consistent with the document collection.
            obj.Children(obj.Children == childId) = [];
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
