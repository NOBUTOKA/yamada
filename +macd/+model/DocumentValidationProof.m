classdef DocumentValidationProof
    % DocumentValidationProof Retain independent validated values for one exact source and catalog.
    %   Publication maps parser/candidate occurrence identities onto live records.
    %   No component, property or evaluation-context handle is retained or adopted.
    properties (Access = private)
        SourceText string
        ClassName string
        RootName string
        Catalog macd.model.ComponentRegistry
        CatalogRevision uint64
        Owners struct
        Diagnostics macd.model.Diagnostic
    end
    methods (Access = ?macd.model.DocumentModel)
        function obj = DocumentValidationProof(document, registry, diagnostics)
            % DocumentValidationProof Capture immutable states only after the document certifies its full validation baseline.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                diagnostics macd.model.Diagnostic
            end
            arguments (Output)
                obj (1, 1) macd.model.DocumentValidationProof
            end
            obj.SourceText = document.CurrentText; obj.ClassName = document.ClassName;
            obj.RootName = document.getComponent(document.RootComponentId).Name;
            obj.Catalog = registry; obj.CatalogRevision = registry.Revision;
            obj.Diagnostics = diagnostics;
            obj.Owners = struct("Id", {}, "Name", {}, "Factory", {}, "DeclaredType", {}, "ParentName", {}, "ChildNames", {}, ...
                "CreationArguments", {}, "IsEditable", {}, "Spans", {}, "Settings", {}, "Properties", {}, "Resolved", {});
            context = document.evaluationContext(registry);
            for owner = document.Components
                [resolved, found] = context.lookup("states:" + owner.Id);
                assert(found, "macd:DocumentValidationProof:MissingState", "A full proof must retain every supported owner's states.");
                parent = document.getComponent(owner.ParentId); parentName = "";
                if ~isempty(parent), parentName = parent.Name; end
                childNames = strings(1, 0);
                for id = owner.Children
                    child = document.getComponent(id); if isempty(child), childNames(end + 1) = ""; else, childNames(end + 1) = child.Name; end %#ok<AGROW>
                end
                obj.Owners(end + 1) = struct("Id", owner.Id, "Name", owner.Name, "Factory", owner.Factory, ...
                    "DeclaredType", owner.DeclaredType, "ParentName", parentName, "ChildNames", sort(childNames), "CreationArguments", {owner.CreationArguments}, "IsEditable", owner.IsEditable, ...
                    "Spans", owner.SourceSpans, "Settings", owner.Settings, ...
                    "Properties", macd.model.DocumentValidationProof.propertyValues(owner), "Resolved", resolved);
            end
        end

        function [owners, diagnostics, ready] = rebind(obj, document, registry)
            % rebind Guard the exact semantic join before returning values with live owner and setting identities.
            arguments (Input)
                obj (1, 1) macd.model.DocumentValidationProof
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                owners (1, :) struct
                diagnostics macd.model.Diagnostic
                ready (1, 1) logical
            end
            owners = struct("ComponentId", {}, "Resolved", {}); diagnostics = macd.model.Diagnostic.empty; ready = false;
            if obj.Catalog ~= registry || obj.CatalogRevision ~= registry.Revision || ...
                    obj.ClassName ~= document.ClassName || numel(obj.Owners) ~= numel(document.Components), return, end
            mapping = macd.source.SourcePatchBatch.empty;
            if obj.SourceText ~= document.CurrentText
                % Saved output normalizes line endings; current history keeps its exact original text.
                if macd.source.SourceWriter.normalize(obj.SourceText, "LF") ~= ...
                        macd.source.SourceWriter.normalize(document.CurrentText, "LF"), return, end
                mapping = macd.model.SourceHistoryRebaser.lineChanges(obj.SourceText, document.CurrentText);
            end
            root = document.getComponent(document.RootComponentId);
            if isempty(root) || root.Name ~= obj.RootName, return, end
            sourceOwners = string({obj.Owners.Id}); targetOwners = strings(size(sourceOwners));
            [found, positions] = ismember(string({obj.Owners.Name}), string({document.Components.Name}));
            if ~all(found) || numel(unique(positions)) ~= numel(positions), return, end
            sourceIds = zeros(1, 0); targetIds = sourceIds;
            % Join semantic inputs independently of component and occurrence ID allocation.
            for index = 1:numel(obj.Owners)
                original = obj.Owners(index); owner = document.Components(positions(index));
                spans = original.Spans;
                if ~isempty(mapping)
                    for field = reshape(string(fieldnames(spans)), 1, [])
                        [spans.(field), valid] = mapping.mapSpan(spans.(field));
                        if ~valid, return, end
                    end
                end
                if isempty(owner) || owner.Factory ~= original.Factory || owner.DeclaredType ~= original.DeclaredType || ...
                        owner.IsEditable ~= original.IsEditable || ...
                        ~isequaln(owner.CreationArguments, original.CreationArguments) || ~isequaln(owner.SourceSpans, spans) || ...
                        ~isequaln(macd.model.DocumentValidationProof.propertyValues(owner), original.Properties)
                    return
                end
                parent = document.getComponent(owner.ParentId); parentName = "";
                if ~isempty(parent), parentName = parent.Name; end
                if parentName ~= original.ParentName, return, end
                childNames = strings(1, 0);
                for id = owner.Children
                    child = document.getComponent(id); if isempty(child), return, end
                    childNames(end + 1) = child.Name; %#ok<AGROW>
                end
                if ~isequal(sort(childNames), original.ChildNames), return, end
                current = owner.Settings; expected = original.Settings;
                if numel(current) ~= numel(expected), return, end
                for field = ["Path", "ValueKind", "LiteralValue", "SourceExpression", "Method", "Syntax", "Sequence", ...
                        "SourceSpan", "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan", "IsCertain", "IsEditable", "FactoryArgumentIndex"]
                    values = {expected.(field)};
                    if endsWith(field, "Span") && ~isempty(mapping)
                        [values, valid] = mapping.mapSpanCells(values);
                        if ~all(valid), return, end
                    end
                    if ~isequaln({current.(field)}, values), return, end
                end
                targetOwners(index) = owner.Id;
                sourceIds = [sourceIds [expected.Id]]; targetIds = [targetIds [current.Id]]; %#ok<AGROW>
            end
            for index = 1:numel(obj.Owners)
                resolved = obj.Owners(index).Resolved;
                [resolved.States, valid] = resolved.States.remapIdentities(sourceIds, targetIds, sourceOwners, targetOwners);
                if ~valid, return, end
                if ~isempty(mapping), resolved.Diagnostics = macd.model.SourceLocationUpdate.relocateDiagnostics(resolved.Diagnostics, mapping); end
                [resolved.Diagnostics, valid] = macd.model.DocumentValidationProof.mapDiagnostics(resolved.Diagnostics, sourceOwners, targetOwners);
                if ~valid, return, end
                owners(end + 1) = struct("ComponentId", targetOwners(index), "Resolved", resolved); %#ok<AGROW>
            end
            diagnostics = obj.Diagnostics;
            if ~isempty(mapping), diagnostics = macd.model.SourceLocationUpdate.relocateDiagnostics(diagnostics, mapping); end
            [diagnostics, ready] = macd.model.DocumentValidationProof.mapDiagnostics(diagnostics, sourceOwners, targetOwners);
        end
    end
    methods (Static, Access = private)
        function values = propertyValues(owner)
            % propertyValues Compare stored primary values without retaining handles or identity-dependent metadata.
            arguments (Input)
                owner (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                values (1, :) struct
            end
            values = struct("Path", {}, "Kind", {}, "Value", {}, "Expression", {}, "Editable", {});
            for entry = owner.Properties
                values(end + 1) = struct("Path", entry.Path, "Kind", entry.ValueKind, "Value", {entry.LiteralValue}, ...
                    "Expression", entry.SourceExpression, "Editable", entry.IsEditable); %#ok<AGROW>
            end
            if ~isempty(values), [~, order] = sort(string({values.Path})); values = values(order); end
        end

        function [diagnostics, valid] = mapDiagnostics(diagnostics, source, target)
            % mapDiagnostics Bind structured diagnostic locations to live component identities without changing text offsets.
            arguments (Input)
                diagnostics macd.model.Diagnostic
                source (1, :) string
                target (1, :) string
            end
            arguments (Output)
                diagnostics macd.model.Diagnostic
                valid (1, 1) logical
            end
            valid = true;
            for index = 1:numel(diagnostics)
                item = diagnostics(index); if strlength(item.ComponentId) == 0, continue, end
                owner = find(source == item.ComponentId, 1);
                if isempty(owner), valid = false; return, end
                diagnostics(index) = macd.model.Diagnostic(item.Code, item.Severity, item.Message, target(owner), item.SourceSpan);
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
