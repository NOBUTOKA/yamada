classdef SubtreeSnapshot
    % SubtreeSnapshot Capture independent component data in stable hierarchy order.
    %   This value object validates hierarchy links and retains literal and source
    %   data without sharing component or property handles. Operation-specific
    %   source safety and destination validation belong to editing planners.

    properties (SetAccess = private)
        % RootId - Identity of the captured subtree root.
        RootId string = ""
        % Records - Parent-first immutable component and property data.
        Records struct = struct([])
    end

    methods
        function obj = SubtreeSnapshot(document, rootId)
            % SubtreeSnapshot Validate and capture one complete component subtree.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                rootId (1, 1) string
            end
            arguments (Output)
                obj (1, 1) macd.model.SubtreeSnapshot
            end

            % Reject ambiguous document identities before resolving hierarchy links.
            ids = string({document.Components.Id});
            if numel(unique(ids)) ~= numel(ids) || any(strlength(ids) == 0)
                error("macd:SubtreeSnapshot:InvalidHierarchy", "Component identities must be nonempty and unique.");
            end
            obj.RootId = rootId;
            pending = rootId;
            visited = strings(1, 0);
            while ~isempty(pending)
                id = pending(1);
                pending(1) = [];
                component = document.getComponent(id);
                if isempty(component)
                    error("macd:SubtreeSnapshot:MissingComponent", "A subtree component does not exist.");
                end
                if any(visited == id)
                    error("macd:SubtreeSnapshot:InvalidHierarchy", "The subtree contains a cycle or repeated child.");
                end
                visited(end + 1) = id; %#ok<AGROW>

                % Validate both directions, including children omitted from the parent list.
                expected = ids(string({document.Components.ParentId}) == id);
                if numel(unique(component.Children)) ~= numel(component.Children) || ...
                        ~isequal(sort(expected), sort(component.Children))
                    error("macd:SubtreeSnapshot:InvalidHierarchy", "Parent and child links disagree.");
                end
                if strlength(component.ParentId) > 0
                    parent = document.getComponent(component.ParentId);
                    if isempty(parent) || sum(parent.Children == id) ~= 1
                        error("macd:SubtreeSnapshot:InvalidHierarchy", "The component parent link is invalid.");
                    end
                elseif id ~= document.RootComponentId
                    error("macd:SubtreeSnapshot:InvalidHierarchy", "Only the document root may have no parent.");
                end
                record = macd.model.SubtreeSnapshot.capture(component);
                if isempty(obj.Records), obj.Records = record; else, obj.Records(end + 1) = record; end
                pending = [component.Children, pending]; %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function record = capture(component)
            % capture Store all component fields and independent property values.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                record (1, 1) struct
            end

            % Reject payloads that would retain live objects or callable behavior.
            macd.model.SubtreeSnapshot.validateValue(component.CreationArguments);
            macd.model.SubtreeSnapshot.validateValue(component.Metadata);
            macd.model.SubtreeSnapshot.validateValue(component.SourceSpans);
            properties = struct("Path", {}, "ValueKind", {}, "LiteralValue", {}, ...
                "SourceExpression", {}, "IsEditable", {}, "Origin", {}, "SourceSpan", {}, "Metadata", {}, "Diagnostics", {});
            for index = 1:numel(component.Properties)
                entry = component.Properties(index);
                macd.model.SubtreeSnapshot.validateValue(entry.LiteralValue);
                macd.model.SubtreeSnapshot.validateValue(entry.Metadata);
                properties(end + 1) = struct("Path", entry.Path, "ValueKind", entry.ValueKind, ...
                    "LiteralValue", {entry.LiteralValue}, "SourceExpression", entry.SourceExpression, ...
                    "IsEditable", entry.IsEditable, "Origin", entry.Origin, "SourceSpan", entry.SourceSpan, ...
                    "Metadata", entry.Metadata, "Diagnostics", entry.Diagnostics); %#ok<AGROW>
            end
            record = struct("Id", component.Id, "Name", component.Name, "Factory", component.Factory, ...
                "DeclaredType", component.DeclaredType, "Origin", component.Origin, ...
                "ParentId", component.ParentId, "Children", component.Children, ...
                "CreationArguments", {component.CreationArguments}, "IsEditable", component.IsEditable, ...
                "Properties", properties, "SourceSpans", component.SourceSpans, ...
                "Metadata", component.Metadata, "Diagnostics", component.Diagnostics);
        end

        function validateValue(value)
            % validateValue Allow only known value data, recursively checking containers.
            arguments (Input)
                value
            end

            % Keep unknown object classes out of clipboard snapshots without evaluating them.
            if iscell(value)
                for index = 1:numel(value)
                    macd.model.SubtreeSnapshot.validateValue(value{index});
                end
            elseif isstruct(value)
                names = fieldnames(value);
                for index = 1:numel(value)
                    for field = 1:numel(names)
                        macd.model.SubtreeSnapshot.validateValue(value(index).(names{field}));
                    end
                end
            elseif ~(isnumeric(value) || islogical(value) || ischar(value) || isstring(value) || ...
                    isa(value, "datetime") || isa(value, "duration") || isa(value, "calendarDuration") || ...
                    isa(value, "categorical") || isa(value, "macd.model.SourceSpan") || isa(value, "macd.model.Diagnostic"))
                error("macd:SubtreeSnapshot:UnsupportedValue", "Snapshot data contains an unsupported value class.");
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
