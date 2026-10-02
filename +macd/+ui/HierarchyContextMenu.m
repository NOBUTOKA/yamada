classdef HierarchyContextMenu < handle
    % HierarchyContextMenu Route tree context actions independently of selection.
    %   This adapter owns one editor menu and a transient right-click target. It
    %   requests document state and commands through narrow injected callbacks.

    properties (Access = private)
        Tree matlab.ui.container.Tree
        Menu matlab.ui.container.ContextMenu
        CallbackItem matlab.ui.container.Menu
        Registry macd.model.ComponentRegistry
        DocumentFcn function_handle
        CommandFcn function_handle
        TargetId string = ""
        TargetDocument macd.model.DocumentModel = macd.model.DocumentModel.empty
    end

    methods
        function obj = HierarchyContextMenu(figure, tree, registry, documentFcn, commandFcn)
            % HierarchyContextMenu Attach one shared native menu to an editor tree.
            arguments (Input)
                figure (1, 1) matlab.ui.Figure
                tree (1, 1) matlab.ui.container.Tree
                registry (1, 1) macd.model.ComponentRegistry
                documentFcn (1, 1) function_handle
                commandFcn (1, 1) function_handle
            end
            arguments (Output)
                obj (1, 1) macd.ui.HierarchyContextMenu
            end
            % Retain narrow command seams separately from transient menu targeting.
            obj.Tree = tree;
            obj.Registry = registry;
            obj.DocumentFcn = documentFcn;
            obj.CommandFcn = commandFcn;
            % A shared tree menu receives the native hit node even when it is unselected.
            obj.Menu = uicontextmenu(figure, "Tag", "macd-hierarchy-context", ...
                "ContextMenuOpeningFcn", @(~, event) obj.opening(event));
            obj.CallbackItem = uimenu(obj.Menu, "Text", "Manage Callbacks...", ...
                "Tag", "macd-manage-callbacks", "Enable", "off", ...
                "MenuSelectedFcn", @(~, ~) obj.invoke());
            tree.ContextMenu = obj.Menu;
        end

        function reset(obj)
            % reset Invalidate a context target before hierarchy or document replacement.
            arguments (Input)
                obj (1, 1) macd.ui.HierarchyContextMenu
            end
            obj.TargetId = "";
            obj.TargetDocument = macd.model.DocumentModel.empty;
            if ~isempty(obj.CallbackItem) && isvalid(obj.CallbackItem)
                obj.CallbackItem.Enable = "off";
            end
        end

        function delete(obj)
            % delete Release the editor menu and its transient target.
            arguments (Input)
                obj (1, 1) macd.ui.HierarchyContextMenu
            end
            obj.reset();
            if ~isempty(obj.Menu) && isvalid(obj.Menu), delete(obj.Menu), end
        end
    end

    methods (Access = private)
        function opening(obj, event)
            % opening Capture native right-click event data without changing selection.
            arguments (Input)
                obj (1, 1) macd.ui.HierarchyContextMenu
                event
            end
            obj.reset();
            info = event.InteractionInformation;
            node = info.Node;
            if isempty(node) || ~isscalar(node) || ~isvalid(node), return, end

            % Reject foreign nodes and resolve only the supplied native hit target.
            parent = node.Parent;
            while isa(parent, "matlab.ui.container.TreeNode"), parent = parent.Parent; end
            if parent ~= obj.Tree, return, end
            document = obj.DocumentFcn();
            if isempty(document), return, end
            component = document.getComponent(string(node.NodeData));
            if isempty(component), return, end
            parentFactory = "";
            if strlength(component.ParentId) > 0
                parentComponent = document.getComponent(component.ParentId);
                if ~isempty(parentComponent), parentFactory = parentComponent.Factory; end
            end
            callbacks = obj.Registry.getEffectiveCallbacks(component.Factory, parentFactory, component.CreationArguments);
            if isempty(callbacks), return, end
            obj.TargetId = component.Id;
            obj.TargetDocument = document;
            obj.CallbackItem.Enable = "on";
        end

        function invoke(obj)
            % invoke Revalidate the captured document and component before dispatch.
            arguments (Input)
                obj (1, 1) macd.ui.HierarchyContextMenu
            end
            document = obj.DocumentFcn();
            if isempty(document) || isempty(obj.TargetDocument) || ...
                    document ~= obj.TargetDocument || strlength(obj.TargetId) == 0 || ...
                    isempty(document.getComponent(obj.TargetId))
                obj.reset();
                return
            end
            obj.CommandFcn(obj.TargetId);
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
