classdef SubtreeReferencePolicy
    % SubtreeReferencePolicy Validate allowlisted component references without evaluation.
    %   SelectedTab references must target direct tabs; ContextMenu references
    %   must target a context menu owned by the same document root.

    methods (Static)
        function id = resolve(document, owner, path, expression, registry)
            % resolve Identify one static app member and prove its property-specific scope.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                owner (1, 1) yamada.model.ComponentRecord
                path (1, 1) string
                expression (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                id (1, 1) string
            end
            token = regexp(expression, '^\s*app\s*\.\s*(?<name>[A-Za-z]\w*)\s*$', 'names', 'once');
            if isempty(token)
                error("yamada:SubtreeReferencePolicy:UnsafeReference", "The reference is not a static component member.");
            end
            target = document.getComponentByName(document.effectiveMemberName(string(token.name)));
            if isempty(target)
                error("yamada:SubtreeReferencePolicy:UnsafeReference", "The referenced component does not exist.");
            end
            yamada.model.SubtreeReferencePolicy.validate(document, owner, path, target, registry);
            id = target.Id;
        end

        function validate(document, owner, path, target, registry)
            % validate Check the narrow property and hierarchy rules for one reference.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                owner (1, 1) yamada.model.ComponentRecord
                path (1, 1) string
                target (1, 1) yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
            end
            valid = path == "SelectedTab" && owner.Factory == "uitabgroup" && ...
                target.Factory == "uitab" && target.ParentId == owner.Id;
            if path == "ContextMenu"
                valid = target.Factory == "uicontextmenu" && target.ParentId == document.RootComponentId;
            end
            definition = registry.get(owner.Factory, owner.CreationArguments);
            valid = valid && any(string({definition.Properties.Path}) == path) && ...
                ~registry.isReadOnlyProperty(owner.Factory, path, owner.CreationArguments);
            if ~valid
                error("yamada:SubtreeReferencePolicy:UnsafeReference", "The reference has an unsupported property, type or hierarchy scope.");
            end
        end

        function lines = assignments(document, components, registry)
            % assignments Emit validated generated references after all target creation calls.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                components yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                lines string
            end
            lines = strings(1, 0);
            for owner = components
                for entry = owner.Properties
                    if ~isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                    target = document.getComponent(string(entry.Metadata.SubtreeReferenceId));
                    if isempty(target)
                        error("yamada:SubtreeReferencePolicy:UnsafeReference", "The reference target no longer exists.");
                    end
                    yamada.model.SubtreeReferencePolicy.validate(document, owner, entry.Path, target, registry);
                    lines(end + 1) = "app." + owner.Name + "." + entry.Path + " = app." + target.Name + ";"; %#ok<AGROW>
                end
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
