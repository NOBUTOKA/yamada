classdef PropertyState
    % PropertyState Separate explicit source values, requested values, and effective state.
    %   This immutable value object carries a resolver result without sharing a
    %   mutable PropertyEntry. Defaults and setter effects never become source
    %   occurrences or user history entries.

    properties (SetAccess = private)
        % Path - Property represented by this state.
        Path string = ""
        % EffectPolicy - Audited application family selected by the property definition.
        EffectPolicy string = "none"
        % EffectStatus - Review status; unknown literals use a stored-input assumption.
        EffectStatus string = "unknown"
        % LastSettingId - Last original occurrence or pending-setting identity.
        LastSettingId double = 0
        % ExplicitKind - absent, pending, literal, or expression source form.
        ExplicitKind string = "absent"
        % ExplicitValue - Original literal retained by the last setting record.
        ExplicitValue = []
        % SourceExpression - Unevaluated original expression, when present.
        SourceExpression string = ""
        % RequestedValue - Current literal projection, including any replacement request.
        RequestedValue = []
        % HasRequestedValue - Whether the current projection contains a literal.
        HasRequestedValue logical = false
        % EffectiveValue - Resolved initial value, meaningful only when IsKnown is true.
        EffectiveValue = []
        % IsKnown - Whether the finite model resolves a value, including unaudited stored inputs.
        IsKnown logical = false
        % EffectKey - Opaque setting, creation, or pending-intent reference within its document context.
        EffectKey string = ""
        % EffectSettingId - Numeric occurrence address, or zero when the effect is not a Setting.
        EffectSettingId double = 0
        % IsEditable - Whether catalog and source ownership permit a replacement request.
        IsEditable logical = false
        % Reason - Explanation when the effective value cannot be resolved.
        Reason string = "No audited initial value is available."
        % ReasonCode - Stable category for unknown state, separate from user-facing prose.
        ReasonCode string = "missing-default"
        % ReadOnlyReason - Explanation when source ownership or the catalog prevents editing.
        ReadOnlyReason string = ""
    end

    methods
        function obj = PropertyState(definition, entry, setting)
            % PropertyState Capture independent explicit and requested values and an audited seed.
            arguments (Input)
                definition (1, 1) yamada.model.PropertyDefinition = yamada.model.PropertyDefinition()
                entry yamada.model.PropertyEntry = yamada.model.PropertyEntry.empty
                setting yamada.model.PropertySetting = yamada.model.PropertySetting.empty
            end
            arguments (Output)
                obj (1, 1) yamada.model.PropertyState
            end

            % Seed from inert audited data without materializing an explicit property.
            obj.Path = definition.Path;
            obj.EffectPolicy = definition.Application.EffectPolicy;
            obj.EffectStatus = definition.Application.EffectStatus;
            obj.IsEditable = definition.IsEditable && definition.AuditDisposition == "editable";
            if ~obj.IsEditable, obj.ReadOnlyReason = "The catalog marks this property as read-only."; end
            if definition.Application.EffectStatus == "unsupported"
                obj.IsEditable = false;
                obj.ReadOnlyReason = definition.Application.EffectReason;
            end
            if definition.Application.EffectStatus ~= "unsupported" && definition.Application.HasInitialValue
                obj.EffectiveValue = definition.Application.InitialValue;
                obj.IsKnown = true;
                obj.Reason = "";
                obj.ReasonCode = "";
            elseif definition.Application.EffectStatus ~= "unsupported" && definition.HasDefault
                obj.EffectiveValue = definition.DefaultValue;
                obj.IsKnown = true;
                obj.Reason = "";
                obj.ReasonCode = "";
            end
            if isempty(entry), return, end
            obj.IsEditable = obj.IsEditable && entry.IsEditable;
            if ~entry.IsEditable, obj.ReadOnlyReason = "The final source setting is not a certain editable literal."; end
            obj.HasRequestedValue = entry.ValueKind == "literal";
            if obj.HasRequestedValue, obj.RequestedValue = entry.LiteralValue; end
            if ~isempty(setting)
                obj.LastSettingId = setting.Id;
                obj.ExplicitKind = setting.ValueKind;
                obj.ExplicitValue = setting.LiteralValue;
                obj.SourceExpression = setting.SourceExpression;
                if setting.Method == "generated", obj.ExplicitKind = "pending"; end
            else
                obj.ExplicitKind = entry.ValueKind;
                obj.ExplicitValue = entry.LiteralValue;
                obj.SourceExpression = entry.SourceExpression;
            end
        end

        function obj = withSourceSettings(obj, settings)
            % withSourceSettings Refresh expression spelling after a proven identifier-only edit.
            arguments (Input)
                obj yamada.model.PropertyState
                settings yamada.model.PropertySetting
            end
            arguments (Output)
                obj yamada.model.PropertyState
            end
            for index = 1:numel(obj)
                setting = settings([settings.Id] == obj(index).LastSettingId);
                if ~isempty(setting), obj(index).SourceExpression = setting.SourceExpression; end
            end
        end

        function [obj, valid] = remapIdentities(obj, sourceSettings, targetSettings, sourceOwners, targetOwners)
            % remapIdentities Rebind immutable occurrence and creation references after a proven semantic publication.
            arguments (Input)
                obj yamada.model.PropertyState
                sourceSettings (1, :) double
                targetSettings (1, :) double
                sourceOwners (1, :) string
                targetOwners (1, :) string
            end
            arguments (Output)
                obj yamada.model.PropertyState
                valid (1, 1) logical
            end
            valid = true;
            for index = find([obj.LastSettingId] ~= 0 | strlength(string({obj.EffectKey})) > 0)
                if obj(index).LastSettingId ~= 0
                    position = find(sourceSettings == obj(index).LastSettingId, 1);
                    if isempty(position), valid = false; return, end
                    obj(index).LastSettingId = targetSettings(position);
                end
                if obj(index).EffectSettingId ~= 0
                    position = find(sourceSettings == obj(index).EffectSettingId, 1);
                    if isempty(position), valid = false; return, end
                    obj(index).EffectSettingId = targetSettings(position);
                    obj(index).EffectKey = string(targetSettings(position));
                elseif startsWith(obj(index).EffectKey, "creation:")
                    position = find(sourceOwners == extractAfter(obj(index).EffectKey, "creation:"), 1);
                    if isempty(position), valid = false; return, end
                    obj(index).EffectKey = "creation:" + targetOwners(position);
                end
            end
        end

        function obj = withReadOnly(obj, reason)
            % withReadOnly Preserve catalog intent while exposing an implementation edit boundary.
            arguments (Input)
                obj (1, 1) yamada.model.PropertyState
                reason (1, 1) string
            end
            arguments (Output)
                obj (1, 1) yamada.model.PropertyState
            end
            obj.IsEditable = false;
            obj.ReadOnlyReason = reason;
        end

        function obj = withEffective(obj, value, known, settingId, reason, reasonCode)
            % withEffective Return a new state without changing explicit records or requests.
            arguments (Input)
                obj (1, 1) yamada.model.PropertyState
                value
                known (1, 1) logical
                settingId (1, 1) string = ""
                reason (1, 1) string = ""
                reasonCode (1, 1) string = "unresolved"
            end
            arguments (Output)
                obj (1, 1) yamada.model.PropertyState
            end
            obj.IsKnown = known;
            obj.EffectKey = settingId;
            numeric = str2double(settingId);
            obj.EffectSettingId = 0;
            if isfinite(numeric) && numeric ~= 0 && fix(numeric) == numeric, obj.EffectSettingId = numeric; end
            obj.Reason = reason;
            obj.ReasonCode = reasonCode;
            obj.EffectiveValue = [];
            if known
                obj.EffectiveValue = value;
                obj.ReasonCode = "";
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
