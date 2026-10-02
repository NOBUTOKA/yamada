classdef CallbackState
    % CallbackState Describe one callback binding and its validated source ownership.
    %   This value object carries discovery results for UI availability and later
    %   model transactions. It does not evaluate expressions or mutate documents.

    properties (SetAccess = private)
        % Name - Catalog callback property name.
        Name string = ""
        % State - Absent, editable, or unsupported binding state.
        State string = "unsupported"
        % Reason - Explanation when mutation cannot be proven safe.
        Reason string = ""
        % HandlerName - Method referenced by a supported binding.
        HandlerName string = ""
        % BindingSpan - Owned assignment range, including an explicit empty binding.
        BindingSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % MethodSpan - Complete owned handler declaration, help, body, and end.
        MethodSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % BindingAnchor - Offset after component creation for a new binding.
        BindingAnchor double = 0
        % MethodAnchor - Offset before the closing end of an instance methods block.
        MethodAnchor double = 0
    end

    methods
        function obj = CallbackState(name, state, reason, handlerName, bindingSpan, methodSpan, bindingAnchor, methodAnchor)
            % CallbackState Store one immutable callback availability result.
            arguments (Input)
                name (1, 1) string
                state (1, 1) string {mustBeMember(state, ["absent", "editable", "unsupported"])}
                reason (1, 1) string = ""
                handlerName (1, 1) string = ""
                bindingSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
                methodSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
                bindingAnchor (1, 1) double = 0
                methodAnchor (1, 1) double = 0
            end
            arguments (Output)
                obj (1, 1) macd.model.CallbackState
            end

            % Retain ownership data without attaching mutable document objects.
            obj.Name = name;
            obj.State = state;
            obj.Reason = reason;
            obj.HandlerName = handlerName;
            obj.BindingSpan = bindingSpan;
            obj.MethodSpan = methodSpan;
            obj.BindingAnchor = bindingAnchor;
            obj.MethodAnchor = methodAnchor;
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
