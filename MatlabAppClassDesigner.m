classdef MatlabAppClassDesigner < matlab.apps.AppBase
    % MatlabAppClassDesigner Edit programmatic AppBase classes without executing them.
    %   This application coordinates the shared document model, conservative source
    %   parser, source generators, hierarchy browser, safe preview, property
    %   inspector, and diagnostics. It never instantiates an opened application.
    %
    %   Example:
    %       editor = MatlabAppClassDesigner();

    properties (SetAccess = private)
        % Document - Current new or parsed AppBase document, when available.
        Document macd.model.DocumentModel = macd.model.DocumentModel.empty
        % SelectedComponentId - Stable identity selected in the hierarchy browser.
        SelectedComponentId string = ""
    end

    properties (Access = private)
        Registry macd.model.ComponentRegistry
        DefaultValueProvider macd.ui.inspector.DefaultValueProvider
        PreviewRenderer macd.ui.PreviewRenderer
        UIFigure matlab.ui.Figure
        MainGrid matlab.ui.container.GridLayout
        CommandGrid matlab.ui.container.GridLayout
        RightGrid matlab.ui.container.GridLayout
        PaletteTable matlab.ui.control.Table
        EditorToolbar matlab.ui.container.Toolbar
        UndoTool matlab.ui.container.toolbar.PushTool
        RedoTool matlab.ui.container.toolbar.PushTool
        SaveMenuItem matlab.ui.container.Menu
        DeleteMenuItem matlab.ui.container.Menu
        EditUndoMenuItem matlab.ui.container.Menu
        EditRedoMenuItem matlab.ui.container.Menu
        SavePathConfirmed logical = false
        HierarchyPanel matlab.ui.container.Panel
        HierarchyGrid matlab.ui.container.GridLayout
        HierarchyTree matlab.ui.container.Tree
        PreviewPanel matlab.ui.container.Panel
        InspectorPanel matlab.ui.container.Panel
        InspectorGrid matlab.ui.container.GridLayout
        InspectorView macd.ui.inspector.InspectorView
        InspectorRows macd.ui.inspector.InspectorPropertyRow = macd.ui.inspector.InspectorPropertyRow.empty
        InspectorComponentId string = ""
        InspectorSurfaceKey string = ""
        InspectorViewState containers.Map = containers.Map("KeyType", "char", "ValueType", "any")
        PreviewHandles containers.Map
        PreviewTabSelections containers.Map = containers.Map("KeyType", "char", "ValueType", "double")
        TabLayoutTimer timer = timer.empty
        TabLayoutSignature string = ""
        TabLayoutStableCount double = 0
        TabLayoutPollCount double = 0
        InteractionOverlay matlab.ui.control.HTML
        InteractionComponentId string = ""
        InteractionKind string = ""
        InteractionStartPoint double = [0 0]
        InteractionStartPosition double = [0 0 0 0]
        InteractionPosition double = [0 0 0 0]
        PreviewScale double = 1
        DiagnosticsDrawer matlab.ui.container.Panel
        DiagnosticsGrid matlab.ui.container.GridLayout
        DiagnosticsSummaryLabel matlab.ui.control.Label
        DiagnosticsToggleButton matlab.ui.control.Button
        DiagnosticsTable matlab.ui.control.Table
        StatusLabel matlab.ui.control.Label
        DiagnosticsExpanded logical = false
        SelectedPaletteFactory string = ""
        PaletteFactories string = strings(1, 0)
    end

    methods
        function app = MatlabAppClassDesigner()
            % MatlabAppClassDesigner Create the editor shell and an empty document.
            arguments (Output)
                app (1, 1) MatlabAppClassDesigner
            end

            % Keep capability definitions shared by New, Open, preview, and validation.
            app.Registry = macd.model.ComponentRegistry.createDefault();
            app.DefaultValueProvider = macd.ui.inspector.DefaultValueProvider(app.Registry);
            app.PreviewRenderer = macd.ui.PreviewRenderer(app.Registry);
            app.createComponents();
            app.createMenus();
            app.newDocument("UntitledApp");
            app.UIFigure.Visible = "on";
        end

        function delete(app)
            % delete Release the editor figure when the application is deleted.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Stop deferred UI work before releasing the editor figure.
            if ~isempty(app.TabLayoutTimer) && isvalid(app.TabLayoutTimer)
                stop(app.TabLayoutTimer);
                wait(app.TabLayoutTimer);
                delete(app.TabLayoutTimer);
                app.TabLayoutTimer = timer.empty;
            end

            % Avoid deleting an already closed figure during AppBase cleanup.
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            % createComponents Build the editor-owned interface controls.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Compose the command bar, browsers, preview, and diagnostic surfaces.
            app.UIFigure = uifigure("Visible", "off", ...
                "Name", "MATLAB App Class Designer", ...
                "Position", [100 100 1280 760], ...
                "WindowKeyPressFcn", @(~, event) app.editorKeyPressed(event));
            app.MainGrid = uigridlayout(app.UIFigure, [3 3]);
            app.MainGrid.RowHeight = {38, "1x", 150};
            app.MainGrid.ColumnWidth = {230, "1x", 330};

            app.CommandGrid = uigridlayout(app.MainGrid, [1 1]);
            app.CommandGrid.Layout.Row = 1;
            app.CommandGrid.Layout.Column = [1 3];
            app.StatusLabel = uilabel(app.CommandGrid, "Text", "Ready");
            app.StatusLabel.Layout.Column = 1;
            app.EditorToolbar = uitoolbar(app.UIFigure);
            undoData = load(fullfile(matlabroot, "toolbox", "matlab", ...
                "icons", "undo.mat"));
            redoData = load(fullfile(matlabroot, "toolbox", "matlab", ...
                "icons", "redo.mat"));
            app.UndoTool = uipushtool(app.EditorToolbar, ...
                "CData", undoData.undoCData, "Tooltip", "Undo (Ctrl+Z)", ...
                "ClickedCallback", @(~, ~) app.undoButtonPushed());
            app.RedoTool = uipushtool(app.EditorToolbar, ...
                "CData", redoData.redoCData, "Tooltip", "Redo (Ctrl+R)", ...
                "ClickedCallback", @(~, ~) app.redoButtonPushed());

            app.PaletteTable = uitable(app.MainGrid, ...
                "ColumnName", {"Component", "Category"}, ...
                "ColumnEditable", [false false], ...
                "CellSelectionCallback", @(~, event) ...
                app.paletteSelectionChanged(event), ...
                "DoubleClickedFcn", @(~, event) ...
                app.paletteDoubleClicked(event));
            app.PaletteTable.Layout.Row = 2;
            app.PaletteTable.Layout.Column = 1;

            app.PreviewPanel = uipanel(app.MainGrid, "Title", "Safe preview");
            app.PreviewPanel.Layout.Row = 2;
            app.PreviewPanel.Layout.Column = 2;

            app.RightGrid = uigridlayout(app.MainGrid, [2 1]);
            app.RightGrid.RowHeight = {"1x", "1x"};
            app.RightGrid.Layout.Row = 2;
            app.RightGrid.Layout.Column = 3;
            app.HierarchyPanel = uipanel(app.RightGrid, "Title", "Hierarchy");
            app.HierarchyPanel.Layout.Row = 1;
            app.HierarchyGrid = uigridlayout(app.HierarchyPanel, [1 1]);
            app.HierarchyGrid.Padding = [0 0 0 0];
            app.HierarchyTree = uitree(app.HierarchyGrid, ...
                "SelectionChangedFcn", @(~, event) app.hierarchySelectionChanged(event));

            app.InspectorPanel = uipanel(app.RightGrid, "Title", "Properties");
            app.InspectorPanel.Layout.Row = 2;
            app.InspectorGrid = uigridlayout(app.InspectorPanel, [1 1]);
            app.InspectorGrid.Padding = [0 0 0 0];
            app.InspectorView = macd.ui.inspector.InspectorView(app.InspectorGrid);
            app.DiagnosticsDrawer = uipanel(app.MainGrid);
            app.DiagnosticsDrawer.Layout.Row = 3;
            app.DiagnosticsDrawer.Layout.Column = [1 3];
            app.DiagnosticsGrid = uigridlayout(app.DiagnosticsDrawer, [2 2]);
            app.DiagnosticsGrid.RowHeight = {30, "1x"};
            app.DiagnosticsGrid.ColumnWidth = {"1x", 100};
            app.DiagnosticsSummaryLabel = uilabel(app.DiagnosticsGrid, ...
                "Text", "Diagnostics: No diagnostics");
            app.DiagnosticsToggleButton = uibutton(app.DiagnosticsGrid, ...
                "Text", "Show", ...
                "ButtonPushedFcn", @(~, ~) app.toggleDiagnostics());
            app.DiagnosticsToggleButton.Layout.Column = 2;
            app.DiagnosticsTable = uitable(app.DiagnosticsGrid, ...
                "ColumnName", {"Severity", "Code", "Component", "Message"}, ...
                "ColumnEditable", [false false false false]);
            app.DiagnosticsTable.Layout.Row = 2;
            app.DiagnosticsTable.Layout.Column = [1 2];
            app.setDiagnosticsDrawer(false);
        end

        function createMenus(app)
            % createMenus Build the menu bar and keyboard accelerators.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Keep file actions separate from editing commands and shortcuts.
            fileMenu = uimenu(app.UIFigure, "Text", "&File");
            uimenu(fileMenu, "Text", "&New", "Accelerator", "N", ...
                "MenuSelectedFcn", @(~, ~) app.newButtonPushed());
            uimenu(fileMenu, "Text", "&Open...", "Accelerator", "O", ...
                "MenuSelectedFcn", @(~, ~) app.openButtonPushed());
            app.SaveMenuItem = uimenu(fileMenu, "Text", "&Save", ...
                "Accelerator", "S", "Enable", "off", ...
                "MenuSelectedFcn", @(~, ~) app.saveButtonPushed());
            uimenu(fileMenu, "Text", "Save As...", ...
                "MenuSelectedFcn", @(~, ~) app.saveAsButtonPushed());

            editMenu = uimenu(app.UIFigure, "Text", "&Edit");
            app.DeleteMenuItem = uimenu(editMenu, "Text", "&Delete", ...
                "MenuSelectedFcn", @(~, ~) app.deleteComponentButtonPushed());
            app.EditUndoMenuItem = uimenu(editMenu, "Text", "&Undo", ...
                "Accelerator", "Z", ...
                "MenuSelectedFcn", @(~, ~) app.undoButtonPushed());
            app.EditRedoMenuItem = uimenu(editMenu, "Text", "&Redo", ...
                "Accelerator", "R", ...
                "MenuSelectedFcn", @(~, ~) app.redoButtonPushed());

            toolsMenu = uimenu(app.UIFigure, "Text", "&Tools");
            uimenu(toolsMenu, "Text", "&Validate", ...
                "MenuSelectedFcn", @(~, ~) app.validateButtonPushed());
            uimenu(toolsMenu, "Text", "&Diff Preview", ...
                "MenuSelectedFcn", @(~, ~) app.diffButtonPushed());
        end

        function newButtonPushed(app)
            % newButtonPushed Request a class name and start a new empty document.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Keep creation in the same model pipeline used by parsed documents.
            answer = inputdlg("MATLAB class name:", "New App", [1 50], ...
                {"UntitledApp"});
            if isempty(answer)
                return
            end
            app.newDocument(string(answer{1}));
        end

        function openButtonPushed(app)
            % openButtonPushed Select and parse an existing AppBase source file.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Parse source only; no constructor, callback, or helper method is run.
            [fileName, folder] = uigetfile("*.m", "Open AppBase class");
            if isequal(fileName, 0)
                app.focusEditor();
                return
            end
            app.focusEditor();
            app.openDocument(string(fullfile(folder, fileName)));
        end

        function saveAsButtonPushed(app)
            % saveAsButtonPushed Generate safely and save source to a selected path.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Require a fresh diagnostic pass before exposing a potentially unsafe save.
            [source, diagnostics] = app.generateSource();
            app.refreshDiagnostics(diagnostics);
            if strlength(source) == 0 || macd.validation.ModelValidator.hasErrors(diagnostics)
                app.setStatus("Save is blocked by errors.");
                return
            end
            [fileName, folder] = uiputfile("*.m", "Save AppBase class", ...
                char(app.Document.ClassName + ".m"));
            if isequal(fileName, 0)
                return
            end
            filePath = string(fullfile(folder, fileName));
            app.writeUtf8(filePath, source);
            app.Document.FilePath = filePath;
            app.SavePathConfirmed = true;
            app.updateSaveState(diagnostics);
            app.setStatus("Saved " + filePath);
        end

        function saveButtonPushed(app)
            % saveButtonPushed Generate and save the current document to its known path.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Require an explicit path from Open or Save As before writing in place.
            if ~app.SavePathConfirmed || strlength(app.Document.FilePath) == 0
                app.setStatus("Save is unavailable until a file is selected.");
                app.updateSaveState(app.Document.Diagnostics);
                return
            end
            [source, diagnostics] = app.generateSource();
            app.refreshDiagnostics(diagnostics);
            app.updateSaveState(diagnostics);
            if strlength(source) == 0 || macd.validation.ModelValidator.hasErrors(diagnostics)
                app.setStatus("Save is blocked by errors.");
                return
            end
            app.writeUtf8(app.Document.FilePath, source);
            if strlength(app.Document.OriginalText) > 0
                app.Document.OriginalText = source;
            end
            app.Document.GeneratedText = source;
            app.setStatus("Saved " + app.Document.FilePath);
        end

        function validateButtonPushed(app)
            % validateButtonPushed Validate the shared document and refresh the shell.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Validation is model-only and is safe for both new and opened documents.
            diagnostics = macd.validation.ModelValidator.validate(app.Document, app.Registry);
            app.refreshDiagnostics(diagnostics);
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                app.setStatus("Validation found blocking errors.");
            else
                app.setStatus("Validation completed without blocking errors.");
            end
            app.updateSaveState(diagnostics);
        end

        function diffButtonPushed(app)
            % diffButtonPushed Display original and generated source side by side.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Generate through the matching source owner without writing a file.
            [source, diagnostics] = app.generateSource();
            app.refreshDiagnostics(diagnostics);
            if strlength(source) == 0
                app.setStatus("Diff preview is unavailable while generation has errors.");
                return
            end
            window = uifigure("Name", "Source Diff Preview", "Position", [180 180 1100 650]);
            grid = uigridlayout(window, [2 2]);
            grid.RowHeight = {22, "1x"};
            uilabel(grid, "Text", "Original source");
            uilabel(grid, "Text", "Generated source");
            original = uitextarea(grid, "Value", cellstr(app.Document.OriginalText), ...
                "Editable", "off");
            original.Layout.Row = 2;
            original.Layout.Column = 1;
            generated = uitextarea(grid, "Value", cellstr(source), "Editable", "off");
            generated.Layout.Row = 2;
            generated.Layout.Column = 2;
        end

        function newDocument(app, className)
            % newDocument Create and display a new empty shared document model.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                className string
            end

            % Factory-owned defaults keep new documents compatible with generation.
            app.clearInspector();
            app.Document = macd.model.NewAppFactory.createEmpty(className, app.Registry);
            app.SelectedComponentId = app.Document.RootComponentId;
            app.refreshShell();
            app.setStatus("Created new document " + className);
            app.SavePathConfirmed = false;
            app.updateSaveState(app.Document.Diagnostics);
        end

        function openDocument(app, filePath)
            % openDocument Parse one source file and display its supported model.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                filePath string
            end

            % Preserve parser diagnostics even if a malformed source has no model.
            [document, diagnostics] = macd.source.AppSourceParser.parseFile(filePath, app.Registry);
            app.clearInspector();
            app.Document = document;
            if ~isempty(document.Components)
                app.SelectedComponentId = document.RootComponentId;
            else
                app.SelectedComponentId = "";
            end
            app.refreshShell();
            app.refreshDiagnostics(diagnostics);
            app.SavePathConfirmed = ~macd.validation.ModelValidator.hasErrors(diagnostics);
            app.updateSaveState(diagnostics);
            app.setStatus("Opened " + filePath);
        end

        function hierarchySelectionChanged(app, event)
            % hierarchySelectionChanged Select the component stored on a tree node.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                event
            end

            % NodeData carries only the stable model identity, never a UI handle.
            if isempty(event.SelectedNodes) || isempty(event.SelectedNodes.NodeData)
                return
            end
            componentId = string(event.SelectedNodes.NodeData);
            if componentId ~= app.SelectedComponentId
                app.SelectedComponentId = componentId;
                app.refreshInspector();
            end
            app.updateInteractionOverlay();
        end

        function refreshShell(app)
            % refreshShell Rebuild all document-derived editor surfaces.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Set the drawer state before measuring the preview panel geometry.
            app.refreshHierarchy();
            app.refreshPalette();
            app.refreshDiagnostics(app.Document.Diagnostics);
            drawnow;
            app.refreshPreview();
            app.refreshInspector();
            app.refreshEditCommands();
        end

        function refreshPalette(app)
            % refreshPalette Populate the palette from eligible registry definitions.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Keep the palette deterministic while retaining registry categories.
            factories = app.Registry.listFactories();
            rows = cell(0, 2);
            paletteFactories = strings(1, 0);
            for index = 1:numel(factories)
                factory = factories(index);
                if ~app.isPaletteFactory(factory)
                    continue
                end
                definition = app.Registry.get(factory);
                category = "Other";
                category = definition.Category;
                displayName = app.Registry.displayName(factory);
                rows(end + 1, :) = {char(displayName), char(category)}; %#ok<AGROW>
                paletteFactories(end + 1) = factory; %#ok<AGROW>
            end
            app.PaletteFactories = paletteFactories;
            app.PaletteTable.Data = rows;
        end

        function paletteSelectionChanged(app, event)
            % paletteSelectionChanged Store the selected palette factory name.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                event
            end

            % CellSelectionCallback may report an empty selection after refresh.
            app.SelectedPaletteFactory = "";
            if isempty(event.Indices)
                app.refreshEditCommands();
                return
            end
            row = event.Indices(1, 1);
            if row <= size(app.PaletteTable.Data, 1)
                app.SelectedPaletteFactory = app.PaletteFactories(row);
            end
            app.refreshEditCommands();
        end

        function paletteDoubleClicked(app, event)
            % paletteDoubleClicked Insert the explicitly double-clicked palette item.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                event
            end

            interaction = event.InteractionInformation;
            row = interaction.Row;
            if isempty(row)
                return
            end
            if row >= 1 && row <= numel(app.PaletteFactories)
                app.SelectedPaletteFactory = app.PaletteFactories(row);
                app.addComponentButtonPushed();
            end
        end

        function addComponentButtonPushed(app)
            % addComponentButtonPushed Insert the selected palette component.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            parent = app.insertionParent(app.SelectedPaletteFactory);
            if isempty(parent)
                app.setStatus("Select a compatible parent before adding a component.");
                return
            end
            try
                component = app.Document.insertComponent(app.Registry, ...
                    app.SelectedPaletteFactory, parent.Id);
            catch exception
                app.setStatus(string(exception.message));
                app.refreshEditCommands();
                return
            end
            app.SelectedComponentId = component.Id;
            app.refreshShell();
            app.setStatus("Added " + component.Name);
        end

        function deleteComponentButtonPushed(app)
            % deleteComponentButtonPushed Delete the selected leaf explicitly.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            component = app.selectedComponent();
            if isempty(component)
                return
            end
            parentId = component.ParentId;
            try
                app.Document.removeComponent(component.Id);
            catch exception
                app.setStatus(string(exception.message));
                app.refreshEditCommands();
                return
            end
            app.SelectedComponentId = parentId;
            app.refreshShell();
            app.setStatus("Deleted " + component.Name);
        end

        function undoButtonPushed(app)
            % undoButtonPushed Undo the most recent model edit.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            try
                app.Document.undo();
            catch exception
                app.setStatus(string(exception.message));
                return
            end
            app.ensureSelectionExists();
            app.refreshShell();
            app.setStatus("Undid last edit.");
        end

        function redoButtonPushed(app)
            % redoButtonPushed Redo the next model edit.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            try
                app.Document.redo();
            catch exception
                app.setStatus(string(exception.message));
                return
            end
            app.ensureSelectionExists();
            app.refreshShell();
            app.setStatus("Redid edit.");
        end

        function editorKeyPressed(app, event)
            % editorKeyPressed Dispatch Delete and Ctrl-based edit shortcuts.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                event
            end

            modifiers = string(event.Modifier);
            hasControl = any(modifiers == "control") || any(modifiers == "command");
            if strcmpi(event.Key, "delete") && ~hasControl
                app.deleteComponentButtonPushed();
            elseif hasControl && strcmpi(event.Key, "z")
                app.undoButtonPushed();
            elseif hasControl && strcmpi(event.Key, "r")
                app.redoButtonPushed();
            end
        end

        function refreshEditCommands(app)
            % refreshEditCommands Synchronize palette and edit command enablement.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if isempty(app.Document)
                return
            end
            component = app.selectedComponent();
            canDelete = ~isempty(component) && component.Id ~= app.Document.RootComponentId && ...
                isempty(component.Children) && component.IsEditable;
            app.DeleteMenuItem.Enable = "off";
            if canDelete
                app.DeleteMenuItem.Enable = "on";
            end
            app.UndoTool.Enable = "off";
            app.RedoTool.Enable = "off";
            app.EditUndoMenuItem.Enable = "off";
            app.EditRedoMenuItem.Enable = "off";
            if app.Document.canUndo()
                app.UndoTool.Enable = "on";
                app.EditUndoMenuItem.Enable = "on";
            end
            if app.Document.canRedo()
                app.RedoTool.Enable = "on";
                app.EditRedoMenuItem.Enable = "on";
            end
        end

        function parent = insertionParent(app, factory)
            % insertionParent Find the nearest selected ancestor accepting a factory.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                factory string
            end
            arguments (Output)
                parent
            end

            parent = [];
            if strlength(factory) == 0 || isempty(app.Document)
                return
            end
            candidate = app.selectedComponent();
            while ~isempty(candidate)
                definition = app.Registry.get(factory);
                if any(definition.AllowedParentFactories == candidate.Factory)
                    parent = candidate;
                    return
                end
                if strlength(candidate.ParentId) == 0
                    return
                end
                candidate = app.Document.getComponent(candidate.ParentId);
            end
        end

        function result = isPaletteFactory(app, factory)
            % isPaletteFactory Report whether a factory is in the initial edit scope.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                factory string
            end
            arguments (Output)
                result (1, 1) logical
            end

            definition = app.Registry.get(factory);
            result = ~definition.IsRoot;
            result = result && ~definition.IsProgrammaticOnly && ...
                definition.Category ~= "FigureTools" && ...
                ~definition.RequiresParentComponent;
        end

        function ensureSelectionExists(app)
            % ensureSelectionExists Move selection to the root after undoable removal.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end
            if isempty(app.selectedComponent())
                app.SelectedComponentId = app.Document.RootComponentId;
            end
        end

        function refreshHierarchy(app)
            % refreshHierarchy Rebuild the component browser from parent links.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Delete old nodes so the browser cannot retain stale model identities.
            delete(app.HierarchyTree.Children);
            if isempty(app.Document) || strlength(app.Document.RootComponentId) == 0
                return
            end
            app.addHierarchyNode([], app.Document.RootComponentId);
        end

        function node = addHierarchyNode(app, parentNode, componentId)
            % addHierarchyNode Add a component and its descendants to the tree.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                parentNode
                componentId string
            end
            arguments (Output)
                node matlab.ui.container.TreeNode
            end

            % Resolve the record before exposing its name in an editor control.
            component = app.Document.getComponent(componentId);
            label = component.Name + " (" + component.Factory + ")";
            if isempty(parentNode)
                node = uitreenode(app.HierarchyTree, "Text", label, "NodeData", component.Id);
            else
                node = uitreenode(parentNode, "Text", label, "NodeData", component.Id);
            end
            for index = 1:numel(component.Children)
                app.addHierarchyNode(node, component.Children(index));
            end
            if component.Id == app.SelectedComponentId
                app.HierarchyTree.SelectedNodes = node;
            end
        end

        function refreshPreview(app)
            % refreshPreview Render registered component data without running input code.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % The preview is disposable editor state and never shares opened handles.
            delete(app.PreviewPanel.Children);
            if isempty(app.Document) || strlength(app.Document.RootComponentId) == 0
                return
            end
            root = app.Document.getComponent(app.Document.RootComponentId);
            app.PreviewPanel.Title = "Safe preview: " + root.Name;
            [app.PreviewHandles, diagnostics] = app.PreviewRenderer.render( ...
                app.Document, app.PreviewPanel);
            app.restorePreviewTabSelections();
            app.updatePreviewScale(root);
            app.createInteractionOverlay();
            app.updateInteractionOverlay();
            app.scheduleOverlayRefresh();
            if ~isempty(diagnostics)
                app.Document.Diagnostics = [app.Document.Diagnostics diagnostics];
                app.refreshDiagnostics(app.Document.Diagnostics);
            end
        end

        function updatePreviewScale(app, root)
            % updatePreviewScale Recover source-to-preview pixel scale.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                root (1, 1) macd.model.ComponentRecord
            end

            % The renderer fits the source figure into its editor-owned surface.
            app.PreviewScale = 1;
            position = root.getProperty("Position");
            surfaces = app.PreviewPanel.Children;
            if isempty(position) || position.ValueKind ~= "literal" || ...
                    numel(position.LiteralValue) ~= 4 || isempty(surfaces)
                return
            end
            sourceSize = double(position.LiteralValue(3:4));
            surface = surfaces(1);
            if sourceSize(1) > 0 && sourceSize(2) > 0 && ...
                    isprop(surface, "Position")
                app.PreviewScale = double(surface.Position(3)) / sourceSize(1);
            end
        end

        function createInteractionOverlay(app)
            % createInteractionOverlay Add the transparent SVG editing surface.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % The overlay owns pointer capture and never changes preview controls.
            overlayPath = fullfile(fileparts(mfilename("fullpath")), ...
                "resources", "EditorInteractionOverlay.html");
            app.InteractionOverlay = uihtml(app.PreviewPanel, ...
                "HTMLSource", overlayPath, ...
                "HTMLEventReceivedFcn", @(~, event) ...
                app.interactionOverlayEvent(event));
            innerPosition = double(app.PreviewPanel.InnerPosition);
            app.InteractionOverlay.Position = [0 0 innerPosition(3:4)];
        end

        function updateInteractionOverlay(app)
            % updateInteractionOverlay Send component silhouettes to the SVG layer.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if isempty(app.InteractionOverlay) || ~isvalid(app.InteractionOverlay) || ...
                    isempty(app.PreviewHandles)
                return
            end
            components = struct("id", {}, "x", {}, "y", {}, "width", {}, ...
                "height", {}, "shape", {}, "selected", {}, "tabGroup", {}, ...
                "tabTitles", {}, "tabSelected", {});
            keys = app.PreviewHandles.keys();
            for index = 1:numel(keys)
                componentId = string(keys{index});
                component = app.Document.getComponent(componentId);
                if isempty(component) || component.Id == app.Document.RootComponentId || ...
                        strlength(component.ParentId) == 0 || component.Factory == "uitab" || ...
                        ~app.isVisibleInSelectedTab(component.Id)
                    continue
                end
                parent = app.Document.getComponent(component.ParentId);
                position = component.getProperty("Position");
                if isempty(parent) || parent.Factory == "uigridlayout" || ...
                        isempty(position) || position.ValueKind ~= "literal" || ...
                        ~isnumeric(position.LiteralValue) || numel(position.LiteralValue) ~= 4
                    continue
                end
                rectangle = app.previewDisplayPosition(app.PreviewHandles(keys{index}));
                if componentId == app.InteractionComponentId
                    rectangle = app.interactionDisplayPosition(componentId, rectangle);
                end
                definition = app.Registry.get(component.Factory);
                tabTitles = strings(1, 0);
                tabSelected = 0;
                if component.Factory == "uitabgroup"
                    children = component.Children;
                    for childIndex = 1:numel(children)
                        child = app.Document.getComponent(children(childIndex));
                        title = child.getProperty("Title");
                        if ~isempty(title) && title.ValueKind == "literal" && ...
                                isstring(title.LiteralValue)
                            tabTitles(end + 1) = title.LiteralValue; %#ok<AGROW>
                        else
                            tabTitles(end + 1) = ""; %#ok<AGROW>
                        end
                    end
                    preview = app.PreviewHandles(keys{index});
                    if ~isempty(preview.SelectedTab)
                        selected = find(preview.Children == preview.SelectedTab, 1);
                        if ~isempty(selected)
                            tabSelected = selected;
                        end
                    end
                end
                components(end + 1) = struct( ...
                    "id", char(component.Id), "x", rectangle(1), "y", rectangle(2), ...
                    "width", rectangle(3), "height", rectangle(4), ...
                    "shape", char(definition.overlayShapeFor(component.CreationArguments)), ...
                    "selected", component.Id == app.SelectedComponentId, ...
                    "tabGroup", component.Factory == "uitabgroup", ...
                    "tabTitles", tabTitles, "tabSelected", tabSelected); %#ok<AGROW>
            end
            innerPosition = double(app.PreviewPanel.InnerPosition);
            app.InteractionOverlay.Data = struct("width", innerPosition(3), ...
                "height", innerPosition(4), "components", components);
        end

        function interactionOverlayEvent(app, event)
            % interactionOverlayEvent Process pointer events from the SVG overlay.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                event
            end

            if string(event.HTMLEventName) ~= "Pointer"
                return
            end
            data = event.HTMLEventData;
            point = [double(data.x) double(data.y)];
            phase = string(data.phase);
            if phase == "tabselect"
                app.selectTabFromOverlay(string(data.componentId), double(data.tabIndex));
            elseif phase == "pointerdown"
                app.beginOverlayInteraction(string(data.componentId), ...
                    string(data.handle), point);
            elseif phase == "pointermove"
                app.moveOverlayInteraction(point);
            elseif phase == "pointerup" || phase == "pointercancel"
                app.finishOverlayInteraction();
            end
        end

        function beginOverlayInteraction(app, componentId, handle, point)
            % beginOverlayInteraction Select a component and begin a move or resize.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId (1, 1) string
                handle (1, 1) string
                point (1, 2) double
            end

            component = app.Document.getComponent(componentId);
            if isempty(component)
                return
            end
            position = component.getProperty("Position");
            if isempty(position) || position.ValueKind ~= "literal" || ...
                    ~isnumeric(position.LiteralValue) || numel(position.LiteralValue) ~= 4
                return
            end
            app.SelectedComponentId = componentId;
            app.InteractionComponentId = componentId;
            app.InteractionKind = handle;
            if strlength(handle) == 0
                app.InteractionKind = "move";
            end
            app.InteractionStartPoint = point;
            app.InteractionStartPosition = double(position.LiteralValue);
            app.InteractionPosition = app.InteractionStartPosition;
            app.refreshHierarchy();
            app.refreshInspector();
            app.updateInteractionOverlay();
        end

        function selectTabFromOverlay(app, componentId, tabIndex)
            % selectTabFromOverlay Select a preview tab from an overlay click.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId (1, 1) string
                tabIndex (1, 1) double
            end

            if isempty(app.PreviewHandles) || ~isKey(app.PreviewHandles, char(componentId))
                return
            end
            group = app.PreviewHandles(char(componentId));
            if ~isa(group, "matlab.ui.container.TabGroup") || isempty(group.Children)
                return
            end
            tabCount = numel(group.Children);
            if ~isfinite(tabIndex) || tabIndex < 1 || tabIndex > tabCount
                return
            end
            tabIndex = round(tabIndex);
            try
                group.SelectedTab = group.Children(tabIndex);
                app.PreviewTabSelections(char(componentId)) = tabIndex;
                app.scheduleOverlayRefresh();
            catch exception
                app.setStatus(string(exception.message));
            end
        end

        function visible = isVisibleInSelectedTab(app, componentId)
            % isVisibleInSelectedTab Check whether a component belongs to the active tab.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId string
            end
            arguments (Output)
                visible (1, 1) logical
            end

            visible = true;
            component = app.Document.getComponent(componentId);
            while ~isempty(component) && strlength(component.ParentId) > 0
                if component.Factory == "uitab"
                    group = app.Document.getComponent(component.ParentId);
                    if ~isempty(group) && group.Factory == "uitabgroup" && ...
                            isKey(app.PreviewHandles, char(group.Id)) && ...
                            isKey(app.PreviewHandles, char(component.Id))
                        groupPreview = app.PreviewHandles(char(group.Id));
                        tabPreview = app.PreviewHandles(char(component.Id));
                        visible = isequal(groupPreview.SelectedTab, tabPreview);
                        return
                    end
                end
                component = app.Document.getComponent(component.ParentId);
            end
        end

        function scheduleOverlayRefresh(app)
            % scheduleOverlayRefresh Refresh tab-child geometry after layout completion.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if isempty(app.Document) || ~any([app.Document.Components.Factory] == "uitabgroup")
                return
            end
            if isempty(app.TabLayoutTimer) || ~isvalid(app.TabLayoutTimer)
                app.TabLayoutTimer = timer("ExecutionMode", "fixedSpacing", ...
                    "Period", 0.05, "TasksToExecute", 40, ...
                    "TimerFcn", @(timerObject, ~) ...
                    app.refreshOverlayAfterTabLayout(timerObject), ...
                    "ErrorFcn", @(timerObject, ~) stop(timerObject));
            elseif strcmp(app.TabLayoutTimer.Running, "on")
                stop(app.TabLayoutTimer);
            end
            app.TabLayoutSignature = "";
            app.TabLayoutStableCount = 0;
            app.TabLayoutPollCount = 0;
            start(app.TabLayoutTimer);
        end

        function refreshOverlayAfterTabLayout(app, timerObject)
            % refreshOverlayAfterTabLayout Update geometry after deferred tab layout.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                timerObject timer
            end

            if isempty(app.UIFigure) || ~isvalid(app.UIFigure) || ...
                    isempty(app.TabLayoutTimer) || ~isvalid(app.TabLayoutTimer) || ...
                    ~isequal(timerObject, app.TabLayoutTimer)
                return
            end
            try
                drawnow;
                signature = app.activeTabGeometrySignature();
            catch
                if isvalid(timerObject)
                    stop(timerObject);
                end
                return
            end
            app.TabLayoutPollCount = app.TabLayoutPollCount + 1;
            if signature == app.TabLayoutSignature
                app.TabLayoutStableCount = app.TabLayoutStableCount + 1;
            else
                app.TabLayoutSignature = signature;
                app.TabLayoutStableCount = 0;
            end
            if app.TabLayoutStableCount >= 2 || app.TabLayoutPollCount >= 40
                stop(timerObject);
                app.updateInteractionOverlay();
            end
        end

        function signature = activeTabGeometrySignature(app)
            % activeTabGeometrySignature Summarize visible preview geometry for polling.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end
            arguments (Output)
                signature (1, 1) string
            end

            parts = strings(1, 0);
            keys = sort(string(app.PreviewHandles.keys()));
            for index = 1:numel(keys)
                component = app.Document.getComponent(keys(index));
                if isempty(component) || component.Factory == "uitab" || ...
                        ~app.isVisibleInSelectedTab(component.Id)
                    continue
                end
                preview = app.PreviewHandles(char(component.Id));
                if ~isvalid(preview)
                    continue
                end
                position = component.getProperty("Position");
                if isempty(position) || position.ValueKind ~= "literal" || ...
                        ~isnumeric(position.LiteralValue) || numel(position.LiteralValue) ~= 4
                    continue
                end
                rectangle = app.previewDisplayPosition(preview);
                parts(end + 1) = component.Id + ":" + ...
                    strjoin(string(round(rectangle)), ","); %#ok<AGROW>
            end
            signature = strjoin(parts, "|");
        end

        function restorePreviewTabSelections(app)
            % restorePreviewTabSelections Restore transient preview tab selections after rendering.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if isempty(app.PreviewTabSelections) || isempty(app.PreviewHandles)
                return
            end
            keys = app.PreviewTabSelections.keys();
            for index = 1:numel(keys)
                componentId = keys{index};
                if ~isKey(app.PreviewHandles, componentId)
                    continue
                end
                group = app.PreviewHandles(componentId);
                if ~isa(group, "matlab.ui.container.TabGroup") || isempty(group.Children)
                    continue
                end
                tabIndex = app.PreviewTabSelections(componentId);
                if tabIndex >= 1 && tabIndex <= numel(group.Children)
                    group.SelectedTab = group.Children(tabIndex);
                end
            end
        end

        function moveOverlayInteraction(app, point)
            % moveOverlayInteraction Update the overlay-only candidate geometry.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                point (1, 2) double
            end

            if strlength(app.InteractionComponentId) == 0
                return
            end
            delta = (point - app.InteractionStartPoint) / max(app.PreviewScale, eps);
            if app.InteractionKind == "move"
                app.InteractionPosition = app.movedPosition( ...
                    app.InteractionComponentId, app.InteractionStartPosition, delta);
            else
                position = app.resizedPosition(app.InteractionStartPosition, delta, ...
                    app.InteractionKind);
                app.InteractionPosition = app.applyResizePolicy(position, ...
                    app.InteractionStartPosition, app.InteractionKind);
            end
            app.updateInteractionOverlay();
        end

        function finishOverlayInteraction(app)
            % finishOverlayInteraction Commit one completed overlay gesture.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if strlength(app.InteractionComponentId) == 0
                return
            end
            componentId = app.InteractionComponentId;
            position = app.InteractionPosition;
            startPosition = app.InteractionStartPosition;
            app.InteractionComponentId = "";
            app.InteractionKind = "";
            if ~isequal(position, startPosition)
                try
                    app.Document.setProperty(componentId, "Position", position);
                catch exception
                    app.setStatus(string(exception.message));
                end
            end
            app.refreshShell();
        end

        function position = movedPosition(app, componentId, startPosition, delta)
            % movedPosition Apply a bounded absolute-position translation.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId (1, 1) string
                startPosition (1, 4) double
                delta (1, 2) double
            end
            arguments (Output)
                position (1, 4) double
            end

            component = app.Document.getComponent(componentId);
            preview = app.PreviewHandles(char(componentId));
            parent = preview.Parent;
            if isprop(parent, "InnerPosition")
                bounds = double(parent.InnerPosition(3:4)) / max(app.PreviewScale, eps);
            else
                bounds = double(parent.Position(3:4)) / max(app.PreviewScale, eps);
            end
            position = startPosition;
            position(1:2) = round(startPosition(1:2) + delta);
            position(1) = max(0, min(position(1), bounds(1) - position(3)));
            position(2) = max(0, min(position(2), bounds(2) - position(4)));
            if isempty(component)
                position = startPosition;
            end
        end

        function rectangle = interactionDisplayPosition(app, componentId, actual)
            % interactionDisplayPosition Preserve runtime control dimensions while editing.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId (1, 1) string
                actual (1, 4) double
            end
            arguments (Output)
                rectangle (1, 4) double
            end

            rectangle = actual;
            if app.InteractionKind == "move"
                delta = app.InteractionPosition(1:2) - app.InteractionStartPosition(1:2);
                rectangle(1:2) = actual(1:2) + delta .* app.PreviewScale;
                return
            end
            rectangle(1:2) = actual(1:2) + ...
                (app.InteractionPosition(1:2) - app.InteractionStartPosition(1:2)) .* app.PreviewScale;
            rectangle(3:4) = app.InteractionPosition(3:4) .* app.PreviewScale;
            component = app.Document.getComponent(componentId);
            definition = app.Registry.get(component.Factory);
            constraint = definition.resizeConstraintFor(component.CreationArguments);
            if constraint == "fixedHeight"
                % MATLAB keeps the slider-like control height independent of Position.
                rectangle(4) = actual(4);
            elseif constraint == "aspectRatio"
                rectangle(4) = rectangle(3) * actual(4) / max(actual(3), eps);
            end
            if contains(app.InteractionKind, "w")
                rectangle(1) = actual(1) + actual(3) - rectangle(3);
            end
        end

        function attachPreviewCallbacks(app)
            % attachPreviewCallbacks Attach editor-only selection callbacks to previews.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if isempty(app.PreviewHandles)
                return
            end
            keys = app.PreviewHandles.keys();
            for index = 1:numel(keys)
                componentId = string(keys{index});
                preview = app.PreviewHandles(keys{index});
                if isprop(preview, "ButtonDownFcn")
                    preview.ButtonDownFcn = @(~, ~) ...
                        app.previewComponentButtonDown(componentId);
                end
            end
        end

        function refreshSelectionHandles(app)
            % refreshSelectionHandles Rebuild eight handles for an absolute selection.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Selection adornments are disposable editor-owned controls.
            if ~isempty(app.ResizeHandles)
                delete(app.ResizeHandles(isvalid(app.ResizeHandles)));
            end
            app.ResizeHandles = matlab.ui.container.Panel.empty;
            component = app.selectedComponent();
            if isempty(component) || component.Id == app.Document.RootComponentId || ...
                    strlength(component.ParentId) == 0 || isempty(app.PreviewHandles) || ...
                    ~isKey(app.PreviewHandles, char(component.Id))
                return
            end
            parent = app.Document.getComponent(component.ParentId);
            position = component.getProperty("Position");
            if isempty(position) || position.ValueKind ~= "literal" || ...
                    ~isnumeric(position.LiteralValue) || parent.Factory == "uigridlayout"
                return
            end
            preview = app.PreviewHandles(char(component.Id));
            displayPosition = app.previewDisplayPosition(preview);
            kinds = ["sw", "s", "se", "w", "e", "nw", "n", "ne"];
            for index = 1:numel(kinds)
                point = app.resizeHandlePosition(displayPosition, kinds(index));
                handle = uipanel(app.PreviewPanel, "Position", [point 8 8], ...
                    "BorderType", "line", "BackgroundColor", [0.2 0.4 0.9], ...
                    "ButtonDownFcn", @(~, ~) ...
                    app.resizeHandleButtonDown(kinds(index)));
                app.ResizeHandles(end + 1) = handle;
            end
        end

        function position = previewDisplayPosition(app, preview)
            % previewDisplayPosition Return a preview handle rectangle in panel pixels.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                preview
            end
            arguments (Output)
                position (1, 4) double
            end

            % Use MATLAB's pixel conversion so nested panels and borders are included.
            position = double(getpixelposition(preview, true));
            parentPosition = double(getpixelposition(app.PreviewPanel, true));
            position(1:2) = position(1:2) - parentPosition(1:2);
        end

        function position = resizeHandlePosition(app, target, kind) %#ok<INUSD>
            % resizeHandlePosition Place one 8-pixel handle at a rectangle corner.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner %#ok<INUSA>
                target (1, 4) double
                kind (1, 1) string
            end
            arguments (Output)
                position (1, 2) double
            end

            x = target(1);
            y = target(2);
            if contains(kind, "e")
                x = target(1) + target(3) - 4;
            elseif ~contains(kind, "w")
                x = target(1) + target(3) / 2 - 4;
            else
                x = target(1) - 4;
            end
            if contains(kind, "n")
                y = target(2) + target(4) - 4;
            elseif ~contains(kind, "s")
                y = target(2) + target(4) / 2 - 4;
            else
                y = target(2) - 4;
            end
            position = [x y];
        end

        function resizeHandleButtonDown(app, kind)
            % resizeHandleButtonDown Begin one source-coordinate resize gesture.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                kind (1, 1) string
            end

            component = app.selectedComponent();
            if isempty(component)
                return
            end
            position = component.getProperty("Position");
            if isempty(position) || position.ValueKind ~= "literal"
                return
            end
            app.ResizeTargetId = component.Id;
            app.ResizeKind = kind;
            app.ResizeStartPoint = double(app.UIFigure.CurrentPoint);
            app.ResizeStartPosition = double(position.LiteralValue);
            app.UIFigure.WindowButtonMotionFcn = @(~, ~) app.resizeHandleMoved();
            app.UIFigure.WindowButtonUpFcn = @(~, ~) app.resizeHandleFinished();
        end

        function resizeHandleMoved(app)
            % resizeHandleMoved Update one resize handle gesture in the preview.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if strlength(app.ResizeTargetId) == 0 || isempty(app.PreviewHandles)
                return
            end
            key = char(app.ResizeTargetId);
            if ~isKey(app.PreviewHandles, key)
                return
            end
            delta = (double(app.UIFigure.CurrentPoint) - app.ResizeStartPoint) / ...
                max(app.PreviewScale, eps);
            position = app.resizedPosition(app.ResizeStartPosition, delta, app.ResizeKind);
            position = app.applyResizePolicy(position, app.ResizeStartPosition, app.ResizeKind);
            preview = app.PreviewHandles(key);
            displayPosition = position .* app.PreviewScale;
            % Set the size pair together; constrained controls otherwise emit
            % aspect-ratio warnings when Position is replaced.
            preview.Position(1:2) = displayPosition(1:2);
            preview.Position(3:4) = displayPosition(3:4);
        end

        function resizeHandleFinished(app)
            % resizeHandleFinished Commit one completed resize to the document model.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if strlength(app.ResizeTargetId) == 0 || isempty(app.PreviewHandles)
                return
            end
            componentId = app.ResizeTargetId;
            preview = app.PreviewHandles(char(componentId));
            position = round(double(preview.Position) / max(app.PreviewScale, eps));
            app.UIFigure.WindowButtonMotionFcn = [];
            app.UIFigure.WindowButtonUpFcn = [];
            app.ResizeTargetId = "";
            app.ResizeKind = "";
            if ~isequal(position, app.ResizeStartPosition)
                app.Document.setProperty(componentId, "Position", position);
            end
            app.refreshShell();
        end

        function position = resizedPosition(app, startPosition, delta, kind) %#ok<INUSD>
            % resizedPosition Apply one directional resize with a one-pixel minimum.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner %#ok<INUSA>
                startPosition (1, 4) double
                delta (1, 2) double
                kind (1, 1) string
            end
            arguments (Output)
                position (1, 4) double
            end

            position = startPosition;
            if contains(kind, "w")
                position(1) = startPosition(1) + delta(1);
                position(3) = startPosition(3) - delta(1);
            elseif contains(kind, "e")
                position(3) = startPosition(3) + delta(1);
            end
            if contains(kind, "s")
                position(2) = startPosition(2) + delta(2);
                position(4) = startPosition(4) - delta(2);
            elseif contains(kind, "n")
                position(4) = startPosition(4) + delta(2);
            end
            if position(3) < 1
                position(1) = position(1) - (1 - position(3));
                position(3) = 1;
            end
            if position(4) < 1
                position(2) = position(2) - (1 - position(4));
                position(4) = 1;
            end
            position = round(position);
        end

        function position = applyResizePolicy(app, position, startPosition, kind)
            % applyResizePolicy Apply registry-defined control size constraints.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                position (1, 4) double
                startPosition (1, 4) double
                kind (1, 1) string
            end
            arguments (Output)
                position (1, 4) double
            end

            % Registry metadata captures documented MATLAB control constraints.
            component = app.selectedComponent();
            if isempty(component)
                return
            end
            definition = app.Registry.get(component.Factory);
            policy = definition.resizeConstraintFor(component.CreationArguments);
            if policy == "fixedHeight"
                position(2) = startPosition(2);
                position(4) = startPosition(4);
                return
            end
            if policy ~= "aspectRatio"
                return
            end
            ratio = startPosition(3) / max(startPosition(4), 1);
            if ~isempty(app.PreviewHandles) && isKey(app.PreviewHandles, char(component.Id))
                runtimePosition = app.previewDisplayPosition( ...
                    app.PreviewHandles(char(component.Id)));
                ratio = runtimePosition(3) / max(runtimePosition(4), eps);
            end
            horizontal = contains(kind, "e") || contains(kind, "w");
            vertical = contains(kind, "n") || contains(kind, "s");
            if horizontal && ~vertical
                position(4) = position(3) / max(ratio, eps);
            elseif vertical && ~horizontal
                position(3) = position(4) * ratio;
            else
                widthDelta = abs(position(3) - startPosition(3));
                heightDelta = abs(position(4) - startPosition(4));
                if widthDelta >= heightDelta * ratio
                    position(4) = position(3) / max(ratio, eps);
                else
                    position(3) = position(4) * ratio;
                end
            end
            if contains(kind, "w")
                position(1) = startPosition(1) + startPosition(3) - position(3);
            end
            position(3:4) = max(round(position(3:4)), 1);
        end

        function previewComponentButtonDown(app, componentId)
            % previewComponentButtonDown Select and begin absolute drag editing.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId string
            end

            component = app.Document.getComponent(componentId);
            if isempty(component)
                return
            end
            app.SelectedComponentId = componentId;
            app.refreshInspector();
            if component.Id == app.Document.RootComponentId || ...
                    strlength(component.ParentId) == 0
                return
            end
            parent = app.Document.getComponent(component.ParentId);
            position = component.getProperty("Position");
            if isempty(position) || position.ValueKind ~= "literal" || ...
                    ~isnumeric(position.LiteralValue) || parent.Factory == "uigridlayout"
                app.refreshEditCommands();
                return
            end
            app.DragComponentId = componentId;
            app.DragStartPoint = double(app.UIFigure.CurrentPoint);
            app.DragStartPosition = double(position.LiteralValue);
            app.UIFigure.WindowButtonMotionFcn = @(~, ~) app.previewDragMoved();
            app.UIFigure.WindowButtonUpFcn = @(~, ~) app.previewDragFinished();
            app.refreshEditCommands();
        end

        function previewDragMoved(app)
            % previewDragMoved Move the preview handle while preserving source units.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if strlength(app.DragComponentId) == 0 || isempty(app.PreviewHandles)
                return
            end
            key = char(app.DragComponentId);
            if ~isKey(app.PreviewHandles, key)
                return
            end
            preview = app.PreviewHandles(key);
            delta = (double(app.UIFigure.CurrentPoint) - app.DragStartPoint) / ...
                max(app.PreviewScale, eps);
            position = app.DragStartPosition;
            position(1:2) = round(position(1:2) + delta(1:2));
            parent = preview.Parent;
            if isprop(parent, "InnerPosition")
                bounds = double(parent.InnerPosition);
            else
                bounds = double(parent.Position);
            end
            position(1) = max(0, min(position(1), bounds(3) - position(3)));
            position(2) = max(0, min(position(2), bounds(4) - position(4)));
            preview.Position = position .* [app.PreviewScale app.PreviewScale ...
                app.PreviewScale app.PreviewScale];
        end

        function previewDragFinished(app)
            % previewDragFinished Commit one completed preview drag to the model.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if strlength(app.DragComponentId) == 0 || isempty(app.PreviewHandles)
                return
            end
            componentId = app.DragComponentId;
            preview = app.PreviewHandles(char(componentId));
            sourcePosition = double(preview.Position) / max(app.PreviewScale, eps);
            sourcePosition = round(sourcePosition);
            app.UIFigure.WindowButtonMotionFcn = [];
            app.UIFigure.WindowButtonUpFcn = [];
            app.DragComponentId = "";
            if ~isequal(sourcePosition, app.DragStartPosition)
                try
                    app.Document.setProperty(componentId, "Position", sourcePosition);
                catch exception
                    app.setStatus(string(exception.message));
                end
            end
            app.refreshShell();
        end

        function message = inspectorValueCommitted(app, componentId, path, value)
            % inspectorValueCommitted Parse and commit one native property-row value.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId (1, 1) string
                path (1, 1) string
                value
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            component = app.Document.getComponent(componentId);
            if isempty(component) || componentId ~= app.SelectedComponentId
                message = "Selection changed before the edit could be applied.";
                return
            end
            entry = component.getProperty(path);
            if ~isempty(entry) && ~entry.IsEditable
                message = "This source-backed property is read-only.";
                app.setStatus(message);
                return
            end
            if ischar(value) || (isstring(value) && isscalar(value))
                [value, isLiteral] = macd.source.MatlabLiteralParser.parse(string(value));
                if ~isLiteral
                    message = "Enter a supported MATLAB literal.";
                    app.setStatus(message);
                    return
                end
            end
            definition = app.inspectorDefinition(component, path);
            message = app.validateInspectorValue(definition, value);
            if strlength(message) > 0
                app.setStatus(message);
                return
            end
            try
                app.Document.setProperty(component.Id, path, value);
            catch exception
                message = string(exception.message);
                app.setStatus(message);
                return
            end
            % Revalidate immediately so property-row commits refresh diagnostics.
            macd.validation.ModelValidator.validate(app.Document, app.Registry);
            app.refreshShell();
        end

        function refreshInspector(app)
            % refreshInspector Rebuild or synchronize the current inspector surface.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            component = app.selectedComponent();
            if isempty(component)
                app.clearInspector();
                return
            end
            surfaceKey = app.inspectorSurfaceKey(component);
            if component.Id ~= app.InspectorComponentId || ...
                    surfaceKey ~= app.InspectorSurfaceKey
                app.rebuildInspector(component, surfaceKey);
            else
                app.refreshInspectorValues(component);
            end
        end

        function rebuildInspector(app, component, surfaceKey)
            % rebuildInspector Replace inspector rows for a new effective surface.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                component (1, 1) macd.model.ComponentRecord
                surfaceKey (1, 1) string
            end

            % Rebuild all category and row controls for a changed surface only.
            states = app.inspectorStates(component);
            [states, categories] = app.sortedInspectorStates(states);
            app.saveInspectorViewState();
            app.InspectorView.clear();
            app.InspectorRows = macd.ui.inspector.InspectorPropertyRow.empty;
            content = app.InspectorView.contentGrid();
            content.RowHeight = repmat({"fit"}, 1, numel(categories));
            contentHeight = 0;
            for categoryIndex = 1:numel(categories)
                category = categories(categoryIndex);
                indices = find(arrayfun(@(state) state.Definition.Category == category, states));
                contentHeight = contentHeight + 40 + 31 * numel(indices);
                section = macd.ui.inspector.InspectorCategorySection(content, category, numel(indices));
                section.setLayoutRow(categoryIndex);
                for rowIndex = 1:numel(indices)
                    state = states(indices(rowIndex));
                    row = macd.ui.inspector.InspectorPropertyRow(section.contentGrid(), rowIndex, ...
                        component.Id, state.Definition, @(id, path, text) ...
                        app.inspectorValueCommitted(id, path, text));
                    app.InspectorRows(end + 1) = row;
                end
            end
            app.InspectorView.setContentHeight(max(contentHeight, 1));
            app.synchronizeInspectorRows(component, states);
            app.restoreInspectorViewState(component.Id);
            app.InspectorComponentId = component.Id;
            app.InspectorSurfaceKey = surfaceKey;
        end

        function refreshInspectorValues(app, component)
            % refreshInspectorValues Synchronize values without replacing the surface.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                component (1, 1) macd.model.ComponentRecord
            end

            % Preserve row controls when explicit values, history, or preview change.
            states = app.inspectorStates(component);
            [states, ~] = app.sortedInspectorStates(states);
            if numel(states) ~= numel(app.InspectorRows)
                app.rebuildInspector(component, app.inspectorSurfaceKey(component));
                return
            end
            app.synchronizeInspectorRows(component, states);
        end

        function clearInspector(app)
            % clearInspector Remove transient inspector state for no selection.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            app.InspectorRows = macd.ui.inspector.InspectorPropertyRow.empty;
            app.InspectorComponentId = "";
            app.InspectorSurfaceKey = "";
            app.InspectorViewState = containers.Map("KeyType", "char", "ValueType", "any");
            app.InspectorView.clear();
        end

        function saveInspectorViewState(app)
            % saveInspectorViewState Cache invalid drafts before the active row tree is destroyed.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if strlength(app.InspectorComponentId) == 0 || isempty(app.InspectorRows)
                return
            end
            states = arrayfun(@(row) row.snapshotTransientState(), app.InspectorRows);
            app.InspectorViewState(char(app.InspectorComponentId)) = states;
        end

        function restoreInspectorViewState(app, componentId)
            % restoreInspectorViewState Restore compatible invalid drafts for a rebuilt component.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                componentId (1, 1) string
            end

            key = char(componentId);
            if ~isKey(app.InspectorViewState, key)
                return
            end
            states = app.InspectorViewState(key);
            for stateIndex = 1:numel(states)
                for rowIndex = 1:numel(app.InspectorRows)
                    app.InspectorRows(rowIndex).restoreTransientState(states(stateIndex));
                end
            end
        end

        function [states, categories] = sortedInspectorStates(app, states)
            % sortedInspectorStates Order effective definitions by declared category and order.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner %#ok<INUSD>
                states
            end
            arguments (Output)
                states
                categories (1, :) string
            end

            categories = unique(arrayfun(@(state) state.Definition.Category, states), "stable");
            ordered = states([]);
            for category = categories
                members = states(arrayfun(@(state) state.Definition.Category == category, states));
                [~, order] = sort(arrayfun(@(state) state.Definition.Order, members));
                ordered = [ordered, members(order)]; %#ok<AGROW>
            end
            states = ordered;
        end

        function states = inspectorStates(app, component)
            % inspectorStates Append retained source-only entries to effective definitions.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                component (1, 1) macd.model.ComponentRecord
            end

            % Preserve unsupported source assignments without making them editable.
            states = app.Document.getEffectivePropertyStates(app.Registry, component.Id);
            definition = app.Registry.get(component.Factory);
            style = definition.styleFor(component.CreationArguments);
            applicable = arrayfun(@(state) isempty(state.Definition.ApplicableStyles) || ...
                any(state.Definition.ApplicableStyles == style), states);
            states = states(applicable);
            effectivePaths = arrayfun(@(state) state.Definition.Path, states);
            for index = 1:numel(component.Properties)
                entry = component.Properties(index);
                if any(effectivePaths == entry.Path)
                    continue
                end
                metadata = struct("category", "Source", "order", index, ...
                    "auditDisposition", "readOnly", "displayName", entry.Path);
                sourceState = struct("Definition", macd.model.PropertyDefinition( ...
                    entry.Path, [], false, false, metadata), "Entry", entry, ...
                    "IsExplicit", true);
                states(end + 1) = sourceState; %#ok<AGROW>
            end
        end

        function definition = inspectorDefinition(app, component, path)
            % inspectorDefinition Find one currently effective inspector definition.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                component (1, 1) macd.model.ComponentRecord
                path (1, 1) string
            end
            arguments (Output)
                definition (1, 1) macd.model.PropertyDefinition
            end

            states = app.inspectorStates(component);
            index = find(arrayfun(@(state) state.Definition.Path == path, states), 1);
            if isempty(index)
                definition = macd.model.PropertyDefinition(path, [], false, false, ...
                    struct("auditDisposition", "readOnly"));
            else
                definition = states(index).Definition;
            end
        end

        function message = validateInspectorValue(app, definition, value)
            % validateInspectorValue Reject invalid editor values before model mutation.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner %#ok<INUSD>
                definition (1, 1) macd.model.PropertyDefinition
                value
            end
            arguments (Output)
                message (1, 1) string
            end

            message = "";
            schema = definition.ValueSchema;
            if definition.Editor == "enum" && isfield(schema, "values") && ...
                    ~any(string(schema.values) == string(value))
                message = "Choose one of the declared values.";
                return
            end
            if definition.Editor == "number"
                if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
                    message = "Enter one finite number.";
                    return
                end
                if isfield(schema, "minimum") && value < schema.minimum
                    message = "Value is below the allowed minimum.";
                    return
                end
                if isfield(schema, "maximum") && value > schema.maximum
                    message = "Value is above the allowed maximum.";
                    return
                end
                if isfield(schema, "integer") && schema.integer && value ~= floor(value)
                    message = "Enter an integer value.";
                    return
                end
            elseif definition.Editor == "numericVector"
                if ~isnumeric(value) || (~isempty(value) && ~isvector(value)) || any(~isfinite(value))
                    message = "Enter a finite numeric vector.";
                    return
                end
                if ~isempty(value) && isfield(schema, "length") && numel(value) ~= schema.length
                    message = "Enter a vector with the required number of values.";
                    return
                end
                if isfield(schema, "minimum") && any(value < schema.minimum)
                    message = "Vector values are below the allowed minimum.";
                    return
                end
            end
        end

        function synchronizeInspectorRows(app, component, states)
            % synchronizeInspectorRows Load current model values into stable native rows.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                component (1, 1) macd.model.ComponentRecord
                states
            end

            parentFactory = "";
            if strlength(component.ParentId) > 0
                parentFactory = app.Document.getComponent(component.ParentId).Factory;
            end
            definitions = arrayfun(@(state) state.Definition, states);
            defaults = app.DefaultValueProvider.resolveAll(component, parentFactory, definitions);
            for index = 1:numel(states)
                entry = states(index).Entry;
                value = "";
                rawValue = [];
                editable = states(index).Definition.IsEditable && ...
                    states(index).Definition.AuditDisposition == "editable";
                if ~isempty(entry)
                    value = macd.ui.InspectorValueFormatter.format(entry);
                    if entry.ValueKind == "literal"
                        rawValue = entry.LiteralValue;
                    end
                    editable = editable && entry.IsEditable;
                else
                    if defaults.Found(index)
                        defaultValue = defaults.Values{index};
                        defaultEntry = macd.model.PropertyEntry(states(index).Definition.Path, defaultValue);
                        value = macd.ui.InspectorValueFormatter.format(defaultEntry);
                        rawValue = defaultValue;
                    end
                end
                app.InspectorRows(index).synchronize(value, editable, rawValue);
            end
        end

        function key = inspectorSurfaceKey(app, component)
            % inspectorSurfaceKey Identify one component's ordered editor surface.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                component (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                key (1, 1) string
            end

            % Include identity, parent context, style, and all definition-owned rows.
            parentFactory = "";
            if strlength(component.ParentId) > 0
                parent = app.Document.getComponent(component.ParentId);
                parentFactory = parent.Factory;
            end
            definition = app.Registry.get(component.Factory);
            style = definition.styleFor(component.CreationArguments);
            states = app.Document.getEffectivePropertyStates(app.Registry, component.Id);
            paths = arrayfun(@(state) state.Definition.Path, states);
            sourcePaths = strings(1, 0);
            for index = 1:numel(component.Properties)
                entry = component.Properties(index);
                if ~any(paths == entry.Path)
                    sourcePaths(end + 1) = entry.Path;
                end
            end
            key = strjoin([component.Id, component.Factory, parentFactory, style, ...
                paths, sourcePaths], "|");
        end
        function refreshDiagnostics(app, diagnostics)
            % refreshDiagnostics Present structured diagnostics in the bottom table.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                diagnostics macd.model.Diagnostic
            end

            % Keep errors and warnings visible without modal interruption.
            data = cell(numel(diagnostics), 4);
            for index = 1:numel(diagnostics)
                diagnostic = diagnostics(index);
                data{index, 1} = char(diagnostic.Severity);
                data{index, 2} = char(diagnostic.Code);
                data{index, 3} = char(diagnostic.ComponentId);
                data{index, 4} = char(diagnostic.Message);
            end
            app.DiagnosticsTable.Data = data;
            errorCount = 0;
            warningCount = 0;
            for index = 1:numel(diagnostics)
                errorCount = errorCount + (diagnostics(index).Severity == "error");
                warningCount = warningCount + (diagnostics(index).Severity == "warning");
            end
            if errorCount > 0 || warningCount > 0
                app.DiagnosticsSummaryLabel.Text = compose( ...
                    "Diagnostics: %d error(s), %d warning(s)", ...
                    errorCount, warningCount);
                app.setDiagnosticsDrawer(true);
            else
                app.DiagnosticsSummaryLabel.Text = "Diagnostics: No diagnostics";
                app.setDiagnosticsDrawer(false);
            end
        end

        function [source, diagnostics] = generateSource(app)
            % generateSource Select the canonical or round-trip generator for the document.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end
            arguments (Output)
                source string
                diagnostics macd.model.Diagnostic
            end

            % RoundTripGenerator delegates new documents to the canonical generator.
            [source, diagnostics] = macd.source.RoundTripGenerator(app.Registry).generate(app.Document);
        end

        function component = selectedComponent(app)
            % selectedComponent Return the selected record or an empty result.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end
            arguments (Output)
                component
            end

            % Guard the lookup for parse failures that produce no root component.
            component = [];
            if ~isempty(app.Document) && strlength(app.SelectedComponentId) > 0
                component = app.Document.getComponent(app.SelectedComponentId);
            end
        end

        function writeUtf8(app, filePath, source)
            % writeUtf8 Write source bytes as UTF-8 without a byte-order mark.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                filePath string
                source string
            end

            % Write bytes directly so the selected document line endings are preserved.
            if ~isvalid(app.UIFigure)
                error("macd:MatlabAppClassDesigner:ClosedEditor", ...
                    "The editor is closed and cannot save source.");
            end
            fileId = fopen(filePath, "wb");
            if fileId < 0
                error("macd:MatlabAppClassDesigner:SaveFailed", ...
                    "Could not open ""%s"" for writing.", filePath);
            end
            cleanup = onCleanup(@() fclose(fileId));
            fwrite(fileId, unicode2native(char(source), "UTF-8"), "uint8");
            clear cleanup
        end

        function setStatus(app, message)
            % setStatus Update the concise editor status text.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                message string
            end

            % Keep status text separate from persistent document diagnostics.
            app.StatusLabel.Text = message;
        end

        function focusEditor(app)
            % focusEditor Bring the editor figure to the foreground after a dialog.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Restore the app window after native dialogs return focus to MATLAB.
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.Visible = "on";
                drawnow;
                figure(app.UIFigure);
                drawnow;
            end
        end

        function updateSaveState(app, diagnostics)
            % updateSaveState Enable Save only for a confirmed path without fatal errors.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                diagnostics macd.model.Diagnostic
            end

            % Keep the menu state synchronized with the current safety validation.
            if app.SavePathConfirmed && ~macd.validation.ModelValidator.hasErrors(diagnostics)
                app.SaveMenuItem.Enable = "on";
            else
                app.SaveMenuItem.Enable = "off";
            end
        end

        function toggleDiagnostics(app)
            % toggleDiagnostics Toggle the diagnostics drawer near its summary.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Preserve the current diagnostics while changing only the drawer state.
            app.setDiagnosticsDrawer(~app.DiagnosticsExpanded);
        end

        function setDiagnosticsDrawer(app, isExpanded)
            % setDiagnosticsDrawer Show or collapse the diagnostics table drawer.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
                isExpanded (1, 1) logical
            end

            % Resize the bottom grid row so collapsed diagnostics do not consume space.
            app.DiagnosticsExpanded = isExpanded;
            if isExpanded
                app.MainGrid.RowHeight = {38, "1x", 150};
                app.DiagnosticsTable.Visible = "on";
                app.DiagnosticsToggleButton.Text = "Hide";
            else
                app.MainGrid.RowHeight = {38, "1x", 42};
            app.DiagnosticsTable.Visible = "off";
            app.DiagnosticsToggleButton.Text = "Show";
            end
        end
    end
end

%{
MatlabAppClassDesigner - Main editor shell for programmatic AppBase classes.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
