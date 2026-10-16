classdef ButtonSelectionPolicy
    % ButtonSelectionPolicy Resolve finite button-group selection in initialization order.
    %   Only radio buttons, legacy toggle buttons, and simple owned SelectedObject
    %   references participate. App code, callbacks, and handle expressions are never run.

    methods (Static)
        function result = deferValue(component, path)
            % deferValue Schedule generated exclusive values after sibling construction.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                path (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = path == "Value" && any(component.Factory == ["uiradiobutton", "uitogglebutton"]);
        end

        function [settings, creations] = insertionSurface(component, document)
            % insertionSurface Expose only proven group events to the bounded insertion planner.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                settings macd.model.PropertySetting
                creations double
            end
            settings = macd.model.PropertySetting.empty;
            creations = zeros(1, 0);
            group = macd.model.ButtonSelectionPolicy.group(component, document);
            if isempty(group), return, end
            members = document.Components(string({document.Components.ParentId}) == group.Id | ...
                string({document.Components.Id}) == group.Id);
            for member = members
                if member.Origin ~= "parsed" || ~member.IsEditable, continue, end
                constructor = member.Settings(string({member.Settings.Method}) == "nameValue");
                safe = all([constructor.IsCertain]) && all(string({constructor.ValueKind}) == "literal");
                for setting = constructor
                    if setting.Path == "CreateFcn" && ~isempty(setting.LiteralValue), safe = false; end
                end
                if safe && isfield(member.Metadata, "InitializationCreationCertain") && ...
                        member.Metadata.InitializationCreationCertain
                    creations(end + 1) = member.SourceSpans.Creation.StartOffset; %#ok<AGROW>
                end
                owned = member.Settings(ismember(string({member.Settings.Path}), ["Value", "SelectedObject"]));
                for setting = owned
                    reference = setting.Path == "SelectedObject" && ...
                        ~isempty(regexp(char(strtrim(setting.SourceExpression)), '^app\.[A-Za-z]\w*$', 'once'));
                    if setting.IsCertain && (setting.ValueKind == "literal" || reference)
                        settings(end + 1) = setting; %#ok<AGROW>
                    end
                end
            end
        end

        function result = requiresCombinedPlan(component, document)
            % requiresCombinedPlan Require actual emitted ordering for pending group changes.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            group = macd.model.ButtonSelectionPolicy.group(component, document);
            result = false;
            if isempty(group), return, end
            members = document.Components(string({document.Components.ParentId}) == group.Id | ...
                string({document.Components.Id}) == group.Id);
            result = any(arrayfun(@(member) macd.source.PropertySourcePlan.needsPlan(document, member), members)) || ...
                (any(string({members.Origin}) == "parsed") && any(string({members.Origin}) ~= "parsed"));
        end

        function [states, diagnostics] = resolve(states, component, document, registry)
            % resolve Project one group's final child values without manufacturing settings.
            arguments (Input)
                states macd.model.PropertyState
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                states macd.model.PropertyState
                diagnostics macd.model.Diagnostic
            end
            diagnostics = macd.model.Diagnostic.empty;
            group = macd.model.ButtonSelectionPolicy.group(component, document);
            if isempty(group), return, end
            paths = string({states.Path});
            path = "Value";
            if component.Id == group.Id, path = "SelectedObject"; end
            index = find(paths == path, 1);
            if isempty(index), return, end
            % Recursive generation uses conservative state until the complete source exists.
            if macd.model.ButtonSelectionPolicy.requiresCombinedPlan(component, document)
                states(index) = states(index).withEffective([], false, "", ...
                    "Button selection requires the complete emitted initialization candidate.", "button-selection");
                return
            end
            children = document.Components(string({document.Components.ParentId}) == group.Id & ...
                ismember(string({document.Components.Factory}), ["uiradiobutton", "uitogglebutton"]));
            if numel(unique(string({children.Factory}))) > 1
                states(index) = states(index).withEffective([], false, "", ...
                    "RadioButton and ToggleButton cannot share one ButtonGroup.", "button-selection");
                return
            end
            members = [group children];
            events = macd.model.ButtonSelectionPolicy.events(members, document, registry);
            present = false(1, numel(children));
            creationCertain = false(1, numel(children));
            creationOrder = zeros(1, 0);
            selected = 0;
            known = true;
            effectId = "";
            for event = events
                child = event.Member - 1;
                if event.Path == "creation"
                    if child == 0, continue, end
                    present(child) = true;
                    creationCertain(child) = event.Known;
                    creationOrder(end + 1) = child; %#ok<AGROW>
                    known = known && event.Known;
                    if selected == 0 && known, selected = child; end
                    effectId = event.Id;
                elseif event.Path == "Value" && child > 0
                    if ~event.Known || ~present(child)
                        known = false;
                    elseif logical(event.Value)
                        selected = child;
                        known = all(creationCertain(present));
                    elseif isempty(creationOrder)
                        known = false;
                    else
                        candidates = creationOrder(creationOrder ~= child);
                        if isempty(candidates)
                            if ~event.Constructor
                                diagnostics(end + 1) = macd.model.Diagnostic("invalid-property-sequence", "error", ...
                                    "A sole radio or toggle child cannot be deselected by a Value assignment.", children(child).Id); %#ok<AGROW>
                            end
                            candidates = child;
                        end
                        selected = candidates(1);
                        known = all(creationCertain(present));
                    end
                    effectId = event.Id;
                elseif event.Path == "SelectedObject" && child == 0
                    selected = 0;
                    known = false;
                    if strlength(event.Expression) > 0
                        target = regexp(char(strtrim(event.Expression)), '^app\.([A-Za-z]\w*)$', 'tokens', 'once');
                        if ~isempty(target)
                            originalNames = arrayfun(@(item) document.sourceComponentName(item.Id), children);
                            match = find((string({children.Name}) == string(target{1}) | originalNames == string(target{1})) & present, 1);
                            if ~isempty(match), selected = match; known = all(creationCertain(present)); end
                        end
                    end
                    effectId = event.Id;
                end
            end
            if component.Id == group.Id
                states(index) = states(index).withEffective([], false, effectId, ...
                    "SelectedObject is a source-only handle reference; child Value states represent the resolved selection.", "selection-reference");
            else
                child = find(string({children.Id}) == component.Id, 1);
                states(index) = states(index).withEffective(double(selected == child), known && present(child), effectId, ...
                    "Button selection depends on an uncertain creation, Value, or SelectedObject setting.", "button-selection");
            end
        end
    end

    methods (Static, Access = private)
        function group = group(component, document)
            % group Find the managed parent of an eligible radio or toggle button.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                group macd.model.ComponentRecord
            end
            group = macd.model.ComponentRecord.empty;
            if component.Factory == "uibuttongroup"
                group = component;
            elseif any(component.Factory == ["uiradiobutton", "uitogglebutton"])
                parent = document.getComponent(component.ParentId);
                if ~isempty(parent) && parent.Factory == "uibuttongroup", group = parent; end
            end
        end

        function events = events(members, document, registry)
            % events Merge global source visits with canonical generated initialization.
            arguments (Input)
                members macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                events (1, :) struct
            end
            events = struct("Sequence", {}, "Member", {}, "Path", {}, "Value", {}, "Known", {}, "Expression", {}, "Id", {}, "Constructor", {});
            tail = 0;
            for member = document.Components
                if ~isempty(member.Settings), tail = max(tail, max([member.Settings.Sequence])); end
                if isfield(member.Metadata, "InitializationCreationSequence")
                    tail = max(tail, member.Metadata.InitializationCreationSequence);
                end
            end
            for index = 1:numel(members)
                member = members(index);
                tail = tail + 1;
                sequence = tail;
                known = member.Origin ~= "parsed";
                if member.Origin == "parsed" && isfield(member.Metadata, "InitializationCreationSequence")
                    sequence = member.Metadata.InitializationCreationSequence;
                    known = member.Metadata.InitializationCreationCertain;
                end
                events(end + 1) = struct("Sequence", sequence, "Member", index, "Path", "creation", ...
                    "Value", [], "Known", known, "Expression", "", "Id", "creation:" + member.Id, "Constructor", true); %#ok<AGROW>
                for setting = member.Settings
                    if setting.Method == "generated" || ~any(setting.Path == ["Value", "SelectedObject"]), continue, end
                    value = setting.LiteralValue;
                    entry = member.getProperty(setting.Path);
                    if ~isempty(entry) && entry.ValueKind == "literal" && isfield(entry.Metadata, "SourceSettingId") && ...
                            string(entry.Metadata.SourceSettingId) == setting.Id, value = entry.LiteralValue; end
                    known = setting.IsCertain && setting.ValueKind == "literal";
                    if setting.Path == "Value", known = known && isValidValue(value); end
                    expression = "";
                    if setting.IsCertain, expression = setting.SourceExpression; end
                    events(end + 1) = struct("Sequence", setting.Sequence, "Member", index, "Path", setting.Path, ...
                        "Value", {value}, "Known", known, "Expression", expression, "Id", setting.Id, "Constructor", setting.Method == "nameValue"); %#ok<AGROW>
                end
                entries = macd.model.PropertyApplicationPlanner.forComponent(member, document, registry);
                if member.Origin == "parsed", entries = entries(string({entries.Origin}) == "generated"); end
                for entry = entries
                    if ~any(entry.Path == ["Value", "SelectedObject"]), continue, end
                    tail = tail + 1;
                    known = entry.ValueKind == "literal";
                    if entry.Path == "Value", known = known && isValidValue(entry.LiteralValue); end
                    events(end + 1) = struct("Sequence", tail, "Member", index, "Path", entry.Path, ...
                        "Value", {entry.LiteralValue}, "Known", known, "Expression", entry.SourceExpression, ...
                        "Id", "pending:" + member.Id + ":" + entry.Path, "Constructor", false); %#ok<AGROW>
                end
            end
            % Generated emitters configure exclusive values only after all siblings exist.
            deferred = find(~[events.Constructor] & string({events.Path}) == "Value" & ...
                arrayfun(@(event) members(event.Member).Origin ~= "parsed", events));
            for index = deferred
                tail = tail + 1;
                events(index).Sequence = tail;
            end
            [~, order] = sort([events.Sequence]);
            events = events(order);
        end
    end
end

function result = isValidValue(value)
% isValidValue Check the finite native radio/toggle Value domain without coercion.
arguments (Input)
    value
end
arguments (Output)
    result (1, 1) logical
end
result = (isnumeric(value) || islogical(value)) && isreal(value) && isscalar(value) && any(value == [0 1]);
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
