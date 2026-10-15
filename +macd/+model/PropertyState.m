classdef PropertyState
    % PropertyState Separate explicit source values, requested values, and effective state.
    %   This immutable value object carries a resolver result without sharing a
    %   mutable PropertyEntry. Defaults and setter effects never become source
    %   occurrences or user history entries.

    properties (SetAccess = private)
        % Path - Property represented by this state.
        Path string = ""
        % LastSettingId - Last original occurrence or pending-setting identity.
        LastSettingId string = ""
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
        % IsKnown - Whether supported evidence determines the effective value.
        IsKnown logical = false
        % EffectSettingId - Occurrence or pending intent that last determined the state.
        EffectSettingId string = ""
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
                definition (1, 1) macd.model.PropertyDefinition = macd.model.PropertyDefinition()
                entry macd.model.PropertyEntry = macd.model.PropertyEntry.empty
                setting macd.model.PropertySetting = macd.model.PropertySetting.empty
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertyState
            end

            % Seed from inert audited data without materializing an explicit property.
            obj.Path = definition.Path;
            obj.IsEditable = definition.IsEditable && definition.AuditDisposition == "editable";
            if ~obj.IsEditable, obj.ReadOnlyReason = "The catalog marks this property as read-only."; end
            if definition.Application.HasInitialValue
                obj.EffectiveValue = definition.Application.InitialValue;
                obj.IsKnown = true;
                obj.Reason = "";
                obj.ReasonCode = "";
            elseif definition.HasDefault
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

        function obj = withEffective(obj, value, known, settingId, reason, reasonCode)
            % withEffective Return a new state without changing explicit records or requests.
            arguments (Input)
                obj (1, 1) macd.model.PropertyState
                value
                known (1, 1) logical
                settingId (1, 1) string = ""
                reason (1, 1) string = ""
                reasonCode (1, 1) string = "unresolved"
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertyState
            end
            obj.IsKnown = known;
            obj.EffectSettingId = settingId;
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
