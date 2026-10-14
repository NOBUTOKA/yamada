classdef ComponentClipboard < handle
    % ComponentClipboard Hold one independent subtree snapshot for a single document.
    %   Copy does not edit history. Cut replaces clipboard contents only after
    %   successful deletion, and Paste retains contents for repeated use.

    properties (Access = private)
        Document macd.model.DocumentModel = macd.model.DocumentModel.empty
        Snapshot macd.model.SubtreeSnapshot = macd.model.SubtreeSnapshot.empty
        PasteCount double = 0
    end

    methods
        function copy(obj, document, id, registry)
            % copy Replace clipboard contents only after validating a complete snapshot.
            arguments (Input)
                obj (1, 1) macd.model.ComponentClipboard
                document (1, 1) macd.model.DocumentModel
                id (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
            end
            snapshot = document.copySubtree(id, registry);
            obj.Document = document;
            obj.Snapshot = snapshot;
            obj.PasteCount = 0;
        end

        function cut(obj, document, id, registry)
            % cut Atomically delete the subtree before replacing clipboard contents.
            arguments (Input)
                obj (1, 1) macd.model.ComponentClipboard
                document (1, 1) macd.model.DocumentModel
                id (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
            end
            snapshot = document.copySubtree(id, registry);
            document.removeSubtree(id, registry);
            obj.Document = document;
            obj.Snapshot = snapshot;
            obj.PasteCount = 0;
        end

        function component = paste(obj, document, targetId, registry, measuredPosition)
            % paste Insert under the nearest compatible target ancestor with deterministic offsets.
            arguments (Input)
                obj (1, 1) macd.model.ComponentClipboard
                document (1, 1) macd.model.DocumentModel
                targetId (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
                measuredPosition double {mustBeFinite} = []
            end
            arguments (Output)
                component (1, 1) macd.model.ComponentRecord
            end
            if ~obj.hasContents(document)
                error("macd:ComponentClipboard:Empty", "No subtree is available for this document.");
            end
            parentId = obj.destination(document, targetId, registry);
            component = document.pasteSubtree(obj.Snapshot, parentId, registry, measuredPosition, ...
                [10 10] * (obj.PasteCount + 1));
            obj.PasteCount = obj.PasteCount + 1;
        end

        function parentId = destination(obj, document, targetId, registry)
            % destination Resolve the nearest catalog-compatible ancestor without changing state.
            arguments (Input)
                obj (1, 1) macd.model.ComponentClipboard
                document (1, 1) macd.model.DocumentModel
                targetId (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                parentId (1, 1) string
            end
            parentId = "";
            if ~obj.hasContents(document), return, end
            root = obj.Snapshot.Records(1);
            definition = registry.get(root.Factory, root.CreationArguments);
            candidate = document.getComponent(targetId);
            visited = strings(1, 0);
            while ~isempty(candidate)
                if any(visited == candidate.Id)
                    error("macd:ComponentClipboard:InvalidDestination", "Destination ancestry contains a cycle.");
                end
                visited(end + 1) = candidate.Id; %#ok<AGROW>
                if any(definition.AllowedParentFactories == candidate.Factory)
                    parentId = candidate.Id;
                    return
                end
                candidate = document.getComponent(candidate.ParentId);
            end
            error("macd:ComponentClipboard:InvalidDestination", "No compatible paste destination exists.");
        end

        function result = hasContents(obj, document)
            % hasContents Report whether the current document owns this clipboard snapshot.
            arguments (Input)
                obj (1, 1) macd.model.ComponentClipboard
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = ~isempty(obj.Document) && obj.Document == document && ~isempty(obj.Snapshot);
        end

        function clear(obj)
            % clear Release clipboard ownership after successful document replacement.
            arguments (Input)
                obj (1, 1) macd.model.ComponentClipboard
            end
            obj.Document = macd.model.DocumentModel.empty;
            obj.Snapshot = macd.model.SubtreeSnapshot.empty;
            obj.PasteCount = 0;
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
