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
        SourceSpans struct = struct("Declaration", macd.model.SourceSpan.empty, "Creation", macd.model.SourceSpan.empty)
        % Metadata - Extensible component-specific data not interpreted by the model.
        Metadata struct = struct()
    end

    properties (Dependent, SetAccess = private)
        % Settings - Independent values read through this owner's slots in the canonical document store.
        Settings macd.model.PropertySetting
    end

    properties (Dependent)
        % CreationArguments - Factory arguments projected from source settings and requested values.
        CreationArguments cell
    end

    properties (Access = private)
        InputClock macd.model.InputChangeClock = macd.model.InputChangeClock.empty
        CreationArgumentData cell = {}
        SettingStore macd.model.SourceSettingStore = macd.model.SourceSettingStore.empty
        SettingSlots double = zeros(1, 0)
        SettingData macd.model.PropertySetting = macd.model.PropertySetting.empty
        SettingView macd.model.PropertySetting = macd.model.PropertySetting.empty
        SettingViewRevision uint64 = intmax("uint64")
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

    methods (Access = ?macd.model.DocumentModel)
        function bindSettingStore(obj, store)
            % bindSettingStore Move detached value records into one acyclic document-owned canonical table.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                store (1, 1) macd.model.SourceSettingStore
            end
            if ~isempty(obj.SettingStore), return, end
            before = obj.SettingData;
            obj.SettingSlots = store.replace(obj.Id, zeros(1, 0), before);
            obj.rebindSettingReferences(before, store.get(obj.SettingSlots));
            obj.SettingStore = store;
            obj.SettingData = macd.model.PropertySetting.empty;
            obj.SettingViewRevision = intmax("uint64");
        end

        function rebindSettingReferences(obj, before, after)
            % rebindSettingReferences Retarget property projections when detached records receive canonical IDs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                before macd.model.PropertySetting
                after macd.model.PropertySetting
            end
            for entry = obj.Properties
                for field = ["SourceSettingId", "PendingSettingId"]
                    if ~isfield(entry.Metadata, field), continue, end
                    index = find(string({before.Id}) == string(entry.Metadata.(field)), 1);
                    if ~isempty(index), entry.Metadata.(field) = after(index).Id; end
                end
            end
        end

        function detachSettingStore(obj, store)
            % detachSettingStore Preserve removed components as independent values for structural history.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                store (1, 1) macd.model.SourceSettingStore
            end
            if isempty(obj.SettingStore) || obj.SettingStore ~= store, return, end
            obj.SettingData = store.get(obj.SettingSlots);
            store.replace(obj.Id, obj.SettingSlots, macd.model.PropertySetting.empty);
            obj.SettingSlots = zeros(1, 0);
            obj.SettingStore = macd.model.SourceSettingStore.empty;
            obj.SettingView = macd.model.PropertySetting.empty;
            obj.SettingViewRevision = intmax("uint64");
        end

        function result = usesSettingStore(obj, store)
            % usesSettingStore Reject shared component ownership instead of stealing another document's storage.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                store (1, 1) macd.model.SourceSettingStore
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = ~isempty(obj.SettingStore) && obj.SettingStore == store;
        end

        function values = projectedSettings(obj, projection)
            % projectedSettings Select this owner's prepared value records using stable slot indexes.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                projection (1, 1) struct
            end
            arguments (Output)
                values (1, 1) struct
            end
            values = struct("Before", projection.Before(obj.SettingSlots), "After", projection.After(obj.SettingSlots));
        end
    end

    methods (Access = {?macd.model.SourceLocationUpdate, ?macd.model.SourceLiteralTransaction})
        function applyProjectedSettings(obj, settings)
            % applyProjectedSettings Adopt transaction-validated value records without reconstructing unchanged payloads.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                settings macd.model.PropertySetting
            end
            obj.Settings = settings;
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

        function value = get.Settings(obj)
            % get.Settings Read a value view without serializing or exposing shared mutable Setting instances.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                value macd.model.PropertySetting
            end
            if isempty(obj.SettingStore)
                value = obj.SettingData;
            else
                revision = obj.SettingStore.Revision;
                if obj.SettingViewRevision ~= revision
                    obj.SettingView = obj.SettingStore.Records(obj.SettingSlots);
                    obj.SettingViewRevision = revision;
                end
                value = obj.SettingView;
            end
        end

        function set.Settings(obj, value)
            % set.Settings Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                value
            end
            if isempty(obj.SettingStore)
                obj.SettingData = value;
            else
                obj.SettingSlots = obj.SettingStore.replace(obj.Id, obj.SettingSlots, value);
                obj.rebindSettingReferences(value, obj.SettingStore.get(obj.SettingSlots));
            end
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
            if any([obj.Settings.Id] == setting.Id)
                id = macd.model.SettingIdAllocator.temporary();
                setting = setting.withIdentity(id, setting.SourceSnapshotId);
            end
            obj.Settings(end + 1) = setting;
            setting = obj.Settings(end);
            entry = obj.getProperty(setting.Path);
            if isempty(entry)
                entry = macd.model.PropertyEntry(setting.Path, [], obj.Origin);
                obj.Properties(end + 1) = entry;
            end
            entry.applySourceSetting(setting);
        end

        function synchronizeSourceSettings(obj, settings, factoryArguments)
            % synchronizeSourceSettings Publish validated current source bindings while retaining live property handles.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                settings macd.model.PropertySetting
                factoryArguments cell
            end
            % Drop projections only when their last owned source occurrence disappeared.
            paths = string({settings.Path});
            for index = numel(obj.Properties):-1:1
                entry = obj.Properties(index);
                if ~any(paths == entry.Path)
                    obj.Properties(index) = [];
                end
            end
            obj.CreationArgumentData = factoryArguments;
            obj.Settings = settings;
            settings = obj.Settings;
            for setting = settings
                entry = obj.getProperty(setting.Path);
                if isempty(entry)
                    entry = macd.model.PropertyEntry(setting.Path, [], obj.Origin);
                    obj.Properties(end + 1) = entry;
                end
                entry.applySourceSetting(setting);
                if isfield(entry.Metadata, "PendingSettingId")
                    entry.Metadata = rmfield(entry.Metadata, "PendingSettingId");
                end
            end
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

            values = obj.Settings;
            settings = values(string({values.Path}) == path);
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
                setting = obj.Settings(end);
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
