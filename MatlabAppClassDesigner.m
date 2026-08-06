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
        PreviewRenderer macd.ui.PreviewRenderer
        UIFigure matlab.ui.Figure
        MainGrid matlab.ui.container.GridLayout
        CommandGrid matlab.ui.container.GridLayout
        LeftGrid matlab.ui.container.GridLayout
        PaletteTable matlab.ui.control.Table
        AddComponentButton matlab.ui.control.Button
        DeleteComponentButton matlab.ui.control.Button
        UndoButton matlab.ui.control.Button
        RedoButton matlab.ui.control.Button
        SaveMenuItem matlab.ui.container.Menu
        SavePathConfirmed logical = false
        HierarchyTree matlab.ui.container.Tree
        PreviewPanel matlab.ui.container.Panel
        InspectorTable matlab.ui.control.Table
        DiagnosticsDrawer matlab.ui.container.Panel
        DiagnosticsGrid matlab.ui.container.GridLayout
        DiagnosticsSummaryLabel matlab.ui.control.Label
        DiagnosticsToggleButton matlab.ui.control.Button
        DiagnosticsTable matlab.ui.control.Table
        StatusLabel matlab.ui.control.Label
        DiagnosticsExpanded logical = false
        SelectedPaletteFactory string = ""
    end

    methods
        function app = MatlabAppClassDesigner()
            % MatlabAppClassDesigner Create the editor shell and an empty document.
            arguments (Output)
                app (1, 1) MatlabAppClassDesigner
            end

            % Keep capability definitions shared by New, Open, preview, and validation.
            app.Registry = macd.model.ComponentRegistry.createDefault();
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
                "Position", [100 100 1280 760]);
            app.MainGrid = uigridlayout(app.UIFigure, [3 3]);
            app.MainGrid.RowHeight = {38, "1x", 150};
            app.MainGrid.ColumnWidth = {230, "1x", 330};

            app.CommandGrid = uigridlayout(app.MainGrid, [1 5]);
            app.CommandGrid.ColumnWidth = {"1x", 70, 70, 70, 70};
            app.CommandGrid.Layout.Row = 1;
            app.CommandGrid.Layout.Column = [1 3];
            app.StatusLabel = uilabel(app.CommandGrid, "Text", "Ready");
            app.StatusLabel.Layout.Column = 1;
            app.AddComponentButton = uibutton(app.CommandGrid, "Text", "Add", ...
                "ButtonPushedFcn", @(~, ~) app.addComponentButtonPushed());
            app.AddComponentButton.Layout.Column = 2;
            app.DeleteComponentButton = uibutton(app.CommandGrid, "Text", "Delete", ...
                "ButtonPushedFcn", @(~, ~) app.deleteComponentButtonPushed());
            app.DeleteComponentButton.Layout.Column = 3;
            app.UndoButton = uibutton(app.CommandGrid, "Text", "Undo", ...
                "ButtonPushedFcn", @(~, ~) app.undoButtonPushed());
            app.UndoButton.Layout.Column = 4;
            app.RedoButton = uibutton(app.CommandGrid, "Text", "Redo", ...
                "ButtonPushedFcn", @(~, ~) app.redoButtonPushed());
            app.RedoButton.Layout.Column = 5;

            app.LeftGrid = uigridlayout(app.MainGrid, [2 1]);
            app.LeftGrid.RowHeight = {150, "1x"};
            app.LeftGrid.Layout.Row = 2;
            app.LeftGrid.Layout.Column = 1;
            app.PaletteTable = uitable(app.LeftGrid, ...
                "ColumnName", {"Component", "Category"}, ...
                "ColumnEditable", [false false], ...
                "CellSelectionCallback", @(~, event) ...
                app.paletteSelectionChanged(event));
            app.PaletteTable.Layout.Row = 1;
            app.HierarchyTree = uitree(app.LeftGrid, ...
                "SelectionChangedFcn", @(~, event) app.hierarchySelectionChanged(event));
            app.HierarchyTree.Layout.Row = 2;
            app.PreviewPanel = uipanel(app.MainGrid, "Title", "Safe preview");
            app.PreviewPanel.Layout.Row = 2;
            app.PreviewPanel.Layout.Column = 2;
            app.InspectorTable = uitable(app.MainGrid, ...
                "ColumnName", {"Property", "Value", "State"}, ...
                "ColumnEditable", [false false false]);
            app.InspectorTable.Layout.Row = 2;
            app.InspectorTable.Layout.Column = 3;
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

            % Keep menu actions connected to the same command methods as the former buttons.
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
                event matlab.ui.eventdata.TreeSelectionChangedData
            end

            % NodeData carries only the stable model identity, never a UI handle.
            if isempty(event.SelectedNodes) || isempty(event.SelectedNodes.NodeData)
                return
            end
            app.SelectedComponentId = string(event.SelectedNodes.NodeData);
            app.refreshInspector();
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
            for index = 1:numel(factories)
                factory = factories(index);
                if ~app.isPaletteFactory(factory)
                    continue
                end
                definition = app.Registry.get(factory);
                category = "Other";
                if isfield(definition.Metadata, "Category")
                    category = string(definition.Metadata.Category);
                end
                rows(end + 1, :) = {char(factory), char(category)}; %#ok<AGROW>
            end
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
                app.SelectedPaletteFactory = string(app.PaletteTable.Data{row, 1});
            end
            app.refreshEditCommands();
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

        function refreshEditCommands(app)
            % refreshEditCommands Synchronize palette and edit command enablement.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            if isempty(app.Document)
                return
            end
            app.AddComponentButton.Enable = "off";
            if strlength(app.SelectedPaletteFactory) > 0 && ...
                    ~isempty(app.insertionParent(app.SelectedPaletteFactory))
                app.AddComponentButton.Enable = "on";
            end
            component = app.selectedComponent();
            canDelete = ~isempty(component) && component.Id ~= app.Document.RootComponentId && ...
                isempty(component.Children) && component.IsEditable;
            app.DeleteComponentButton.Enable = "off";
            if canDelete
                app.DeleteComponentButton.Enable = "on";
            end
            app.UndoButton.Enable = "off";
            app.RedoButton.Enable = "off";
            if app.Document.canUndo()
                app.UndoButton.Enable = "on";
            end
            if app.Document.canRedo()
                app.RedoButton.Enable = "on";
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
            if isfield(definition.Metadata, "ProgrammaticOnly")
                result = result && ~logical(definition.Metadata.ProgrammaticOnly);
            end
            if isfield(definition.Metadata, "Category")
                result = result && string(definition.Metadata.Category) ~= "FigureTools";
            end
            if isfield(definition.Metadata, "RequiresParentComponent")
                result = result && ~logical(definition.Metadata.RequiresParentComponent);
            end
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
            [~, diagnostics] = app.PreviewRenderer.render( ...
                app.Document, app.PreviewPanel);
            if ~isempty(diagnostics)
                app.Document.Diagnostics = [app.Document.Diagnostics diagnostics];
                app.refreshDiagnostics(app.Document.Diagnostics);
            end
        end

        function refreshInspector(app)
            % refreshInspector Show the selected component's source-safe properties.
            arguments (Input)
                app (1, 1) MatlabAppClassDesigner
            end

            % Display expressions as read-only source text rather than evaluating them.
            component = app.selectedComponent();
            if isempty(component)
                app.InspectorTable.Data = cell(0, 3);
                return
            end
            data = cell(numel(component.Properties), 3);
            for index = 1:numel(component.Properties)
                entry = component.Properties(index);
                data{index, 1} = char(entry.Path);
                if entry.ValueKind == "literal"
                    data{index, 2} = char(macd.source.LiteralEncoder.encode(entry.LiteralValue));
                else
                    data{index, 2} = char(entry.SourceExpression);
                end
                if entry.IsEditable
                    data{index, 3} = "Editable";
                else
                    data{index, 3} = "Read-only source";
                end
                data{index, 3} = char(data{index, 3});
            end
            app.InspectorTable.Data = data;
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
