classdef CallbackEdit
    % CallbackEdit Retain one callback transaction against an original source snapshot.
    %   This immutable value stores original deletion spans and generated handler
    %   text. Document history owns ordered snapshots of these pending intentions.

    properties (SetAccess = private)
        % ComponentId - Stable identity owning the binding.
        ComponentId string
        % Name - Callback property name.
        Name string
        % Action - Current addition or deletion intention.
        Action string
        % HandlerName - Generated handler name for an addition.
        HandlerName string
        % MethodText - Complete generated method for an addition.
        MethodText string
        % BindingSpan - Original assignment replaced or removed by this edit.
        BindingSpan macd.model.SourceSpan
        % MethodSpan - Original handler removed by this edit.
        MethodSpan macd.model.SourceSpan
        % BindingAnchor - Original creation offset used for insertion.
        BindingAnchor double
        % MethodAnchor - Original methods-block offset used for insertion.
        MethodAnchor double
        % OriginalSource - Snapshot against which the retained offsets were validated.
        OriginalSource string
    end

    methods
        function obj = CallbackEdit(componentId, name, action, handlerName, methodText, state, originalSource)
            % CallbackEdit Capture original ownership together with the resulting binding state.
            arguments (Input)
                componentId (1, 1) string
                name (1, 1) string
                action (1, 1) string {mustBeMember(action, ["Add", "Delete"])}
                handlerName (1, 1) string
                methodText (1, 1) string
                state (1, 1) macd.model.CallbackState
                originalSource (1, 1) string = ""
            end
            arguments (Output)
                obj (1, 1) macd.model.CallbackEdit
            end
            % Preserve source coordinates even when later edits change visible availability.
            obj.ComponentId = componentId;
            obj.Name = name;
            obj.Action = action;
            obj.HandlerName = handlerName;
            obj.MethodText = methodText;
            obj.BindingSpan = state.BindingSpan;
            obj.MethodSpan = state.MethodSpan;
            obj.BindingAnchor = state.BindingAnchor;
            obj.MethodAnchor = state.MethodAnchor;
            obj.OriginalSource = originalSource;
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
