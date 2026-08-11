classdef ComponentCatalogLoader
    % ComponentCatalogLoader Build typed component definitions from strict JSON files.
    %   The loader reads an explicit R2024a manifest, expands ordered property
    %   groups, validates catalog data and symbolic behavior names, then returns a
    %   complete ComponentRegistry. A malformed catalog never returns a partial
    %   registry and never invokes catalog-provided executable code.

    methods (Static)
        function registry = load(catalogRoot)
            % load Validate one catalog root and return its complete runtime registry.
            arguments (Input)
                catalogRoot (1, 1) string = macd.catalog.ComponentCatalogLoader.defaultCatalogRoot()
            end
            arguments (Output)
                registry (1, 1) macd.model.ComponentRegistry
            end

            % Read all source data before creating the return registry.
            manifest = macd.catalog.ComponentCatalogLoader.readDocument(catalogRoot, "catalog.json");
            macd.catalog.ComponentCatalogLoader.requireFields(manifest, ["schemaVersion", ...
                "matlabRelease", "propertyGroupFiles", "componentFiles"], ...
                catalogRoot + "/catalog.json");
            macd.catalog.ComponentCatalogLoader.rejectUnknownFields(manifest, ["schemaVersion", ...
                "matlabRelease", "propertyGroupFiles", "componentFiles"], ...
                catalogRoot + "/catalog.json");
            if manifest.schemaVersion ~= 1 || string(manifest.matlabRelease) ~= "R2024a"
                macd.catalog.ComponentCatalogLoader.fail(catalogRoot + "/catalog.json", ...
                    "schemaVersion must be 1 and matlabRelease must be R2024a.");
            end
            groups = macd.catalog.ComponentCatalogLoader.readGroups(catalogRoot, ...
                macd.catalog.ComponentCatalogLoader.stringList(manifest.propertyGroupFiles, ...
                catalogRoot + "/catalog.json.propertyGroupFiles"));
            componentFiles = macd.catalog.ComponentCatalogLoader.stringList(manifest.componentFiles, ...
                catalogRoot + "/catalog.json.componentFiles");

            % Register only after every component definition has validated successfully.
            definitions = macd.model.ComponentDefinition.empty;
            factories = strings(1, 0);
            for index = 1:numel(componentFiles)
                relativePath = componentFiles(index);
                component = macd.catalog.ComponentCatalogLoader.readDocument(catalogRoot, relativePath);
                context = catalogRoot + "/" + relativePath;
                definition = macd.catalog.ComponentCatalogLoader.componentDefinition(component, groups, context);
                if any(factories == definition.Factory)
                    macd.catalog.ComponentCatalogLoader.fail(context + ".factory", ...
                        "Duplicate factory """ + definition.Factory + """.");
                end
                factories(end + 1) = definition.Factory; %#ok<AGROW>
                definitions(end + 1) = definition; %#ok<AGROW>
            end
            registry = macd.model.ComponentRegistry();
            for index = 1:numel(definitions)
                registry.register(definitions(index));
            end
        end

        function root = defaultCatalogRoot()
            % defaultCatalogRoot Return the packaged standard catalog location.
            arguments (Output)
                root (1, 1) string
            end

            % Resolve from this package file so the current folder is irrelevant.
            sourcePath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(sourcePath)));
            root = string(fullfile(projectRoot, "resources", "component-catalog", "v1"));
        end
    end

    methods (Static, Access = private)
        function groups = readGroups(root, files)
            % readGroups Read all manifest-listed property groups by their unique names.
            arguments (Input)
                root (1, 1) string
                files (1, :) string
            end
            arguments (Output)
                groups containers.Map
            end

            % Use an explicit map only after all group documents have passed validation.
            groups = containers.Map("KeyType", "char", "ValueType", "any");
            for index = 1:numel(files)
                relativePath = files(index);
                document = macd.catalog.ComponentCatalogLoader.readDocument(root, relativePath);
                context = root + "/" + relativePath;
                macd.catalog.ComponentCatalogLoader.requireFields(document, ["name", "entries"], context);
                macd.catalog.ComponentCatalogLoader.rejectUnknownFields(document, ["name", "entries"], context);
                name = macd.catalog.ComponentCatalogLoader.scalarString(document.name, context + ".name");
                if isKey(groups, char(name))
                    macd.catalog.ComponentCatalogLoader.fail(context + ".name", ...
                        "Duplicate property group """ + name + """.");
                end
                groups(char(name)) = struct("Entries", document.entries, "Context", context);
            end
        end

        function definition = componentDefinition(document, groups, context)
            % componentDefinition Convert one validated component document to a typed definition.
            arguments (Input)
                document struct
                groups containers.Map
                context (1, 1) string
            end
            arguments (Output)
                definition (1, 1) macd.model.ComponentDefinition
            end

            % Enforce the compact schema used by the generated R2024a catalog.
            required = ["factory", "declaredType", "allowedParentFactories", ...
                "isRoot", "creationArguments", "properties", "capabilities"];
            optional = "styleOverrides";
            macd.catalog.ComponentCatalogLoader.requireFields(document, required, context);
            macd.catalog.ComponentCatalogLoader.rejectUnknownFields(document, [required, optional], context);
            factory = macd.catalog.ComponentCatalogLoader.scalarString(document.factory, context + ".factory");
            declaredType = macd.catalog.ComponentCatalogLoader.scalarString(document.declaredType, ...
                context + ".declaredType");
            parents = macd.catalog.ComponentCatalogLoader.stringList(document.allowedParentFactories, ...
                context + ".allowedParentFactories");
            if ~islogical(document.isRoot) || ~isscalar(document.isRoot)
                macd.catalog.ComponentCatalogLoader.fail(context + ".isRoot", "Expected one logical value.");
            end
            creationArguments = macd.catalog.ComponentCatalogLoader.creationArguments( ...
                document.creationArguments, context + ".creationArguments");
            properties = macd.catalog.ComponentCatalogLoader.expandProperties(document.properties, groups, ...
                strings(1, 0), context + ".properties");
            capabilities = macd.catalog.ComponentCatalogLoader.capabilities(document.capabilities, ...
                context + ".capabilities");
            if isfield(document, "styleOverrides")
                capabilities.StyleOverrides = macd.catalog.ComponentCatalogLoader.styleOverrides( ...
                    document.styleOverrides, capabilities.SupportedStyles, ...
                    context + ".styleOverrides");
            end
            definition = macd.model.ComponentDefinition.fromPaths(factory, declaredType, ...
                parents, document.isRoot, creationArguments, properties, capabilities);
        end

        function properties = expandProperties(entries, groups, stack, context)
            % expandProperties Expand ordered property and group entries without cycles.
            arguments (Input)
                entries
                groups containers.Map
                stack (1, :) string
                context (1, 1) string
            end
            arguments (Output)
                properties macd.model.PropertyDefinition
            end

            % Append definitions in source order while rejecting duplicate property paths.
            properties = macd.model.PropertyDefinition.empty;
            entryList = macd.catalog.ComponentCatalogLoader.objectList(entries, context);
            for index = 1:numel(entryList)
                entry = entryList{index};
                entryContext = context + "[" + string(index) + "]";
                hasGroup = isfield(entry, "group");
                hasPath = isfield(entry, "path");
                if hasGroup == hasPath
                    macd.catalog.ComponentCatalogLoader.fail(entryContext, ...
                        "Each property entry must contain exactly one of group or path.");
                end
                if hasGroup
                    macd.catalog.ComponentCatalogLoader.rejectUnknownFields(entry, "group", entryContext);
                    groupName = macd.catalog.ComponentCatalogLoader.scalarString(entry.group, ...
                        entryContext + ".group");
                    if any(stack == groupName)
                        macd.catalog.ComponentCatalogLoader.fail(entryContext + ".group", ...
                            "Property group cycle: " + strjoin([stack, groupName], " -> ") + ".");
                    end
                    if ~isKey(groups, char(groupName))
                        macd.catalog.ComponentCatalogLoader.fail(entryContext + ".group", ...
                            "Unknown property group """ + groupName + """.");
                    end
                    group = groups(char(groupName));
                    expanded = macd.catalog.ComponentCatalogLoader.expandProperties(group.Entries, groups, ...
                        [stack, groupName], group.Context + ".entries");
                    properties = [properties; expanded(:)]; %#ok<AGROW>
                else
                    properties(end + 1) = macd.catalog.ComponentCatalogLoader.propertyDefinition( ...
                        entry, entryContext); %#ok<AGROW>
                end
            end
            paths = string({properties.Path});
            if numel(unique(paths)) ~= numel(paths)
                macd.catalog.ComponentCatalogLoader.fail(context, "Expanded property paths must be unique.");
            end
        end

        function definition = propertyDefinition(document, context)
            % propertyDefinition Convert one property document to a typed capability.
            arguments (Input)
                document struct
                context (1, 1) string
            end
            arguments (Output)
                definition (1, 1) macd.model.PropertyDefinition
            end

            % Validate the stable v1 fields before retaining optional metadata.
            allowed = ["path", "defaultValue", "hasDefault", "isEditable", "metadata"];
            macd.catalog.ComponentCatalogLoader.requireFields(document, "path", context);
            macd.catalog.ComponentCatalogLoader.rejectUnknownFields(document, allowed, context);
            path = macd.catalog.ComponentCatalogLoader.scalarString(document.path, context + ".path");
            hasDefault = isfield(document, "hasDefault") && document.hasDefault;
            if ~islogical(hasDefault) || ~isscalar(hasDefault)
                macd.catalog.ComponentCatalogLoader.fail(context + ".hasDefault", "Expected one logical value.");
            end
            if hasDefault && ~isfield(document, "defaultValue")
                macd.catalog.ComponentCatalogLoader.fail(context, ...
                    "hasDefault requires defaultValue.");
            end
            defaultValue = [];
            if isfield(document, "defaultValue")
                defaultValue = document.defaultValue;
            end
            isEditable = true;
            if isfield(document, "isEditable")
                isEditable = document.isEditable;
            end
            if ~islogical(isEditable) || ~isscalar(isEditable)
                macd.catalog.ComponentCatalogLoader.fail(context + ".isEditable", "Expected one logical value.");
            end
            metadata = struct();
            if isfield(document, "metadata")
                if ~isstruct(document.metadata) || ~isscalar(document.metadata)
                    macd.catalog.ComponentCatalogLoader.fail(context + ".metadata", "Expected one object.");
                end
                metadata = document.metadata;
                macd.catalog.ComponentCatalogLoader.rejectUnknownFields(metadata, ...
                    ["editor", "validator", "previewPolicy", "resetPolicy"], ...
                    context + ".metadata");
                macd.catalog.PropertyBehaviorRegistry.validateMetadata(metadata, context);
            end
            definition = macd.model.PropertyDefinition(path, defaultValue, hasDefault, ...
                isEditable, metadata);
        end

        function result = capabilities(document, context)
            % capabilities Normalize strict JSON capabilities for ComponentDefinition.fromPaths.
            arguments (Input)
                document struct
                context (1, 1) string
            end
            arguments (Output)
                result (1, 1) struct
            end

            % Convert lower-camel JSON fields to the existing typed capability names.
            if ~isstruct(document) || ~isscalar(document)
                macd.catalog.ComponentCatalogLoader.fail(context, "Expected one object.");
            end
            allowed = ["displayName", "category", "programmaticOnly", ...
                "requiresParentComponent", "supportedStyles", "defaultStyle", ...
                "declaredTypesByStyle", "overlayShape", "overlayShapesByStyle", ...
                "resizeConstraint", "resizeConstraintsByStyle", "metadata"];
            macd.catalog.ComponentCatalogLoader.requireFields(document, ["displayName", "category"], context);
            macd.catalog.ComponentCatalogLoader.rejectUnknownFields(document, allowed, context);
            result = struct("DisplayName", macd.catalog.ComponentCatalogLoader.scalarString( ...
                document.displayName, context + ".displayName"), ...
                "Category", macd.catalog.ComponentCatalogLoader.scalarString(document.category, ...
                context + ".category"));
            result.ProgrammaticOnly = macd.catalog.ComponentCatalogLoader.optionalLogical(document, ...
                "programmaticOnly", false, context);
            result.RequiresParentComponent = macd.catalog.ComponentCatalogLoader.optionalLogical(document, ...
                "requiresParentComponent", false, context);
            result.SupportedStyles = macd.catalog.ComponentCatalogLoader.optionalStringList(document, ...
                "supportedStyles", context);
            result.DefaultStyle = macd.catalog.ComponentCatalogLoader.optionalString(document, ...
                "defaultStyle", "", context);
            result.DeclaredTypesByStyle = macd.catalog.ComponentCatalogLoader.optionalStruct(document, ...
                "declaredTypesByStyle", context);
            result.OverlayShape = macd.catalog.ComponentCatalogLoader.optionalString(document, ...
                "overlayShape", "rectangle", context);
            result.OverlayShapesByStyle = macd.catalog.ComponentCatalogLoader.optionalStruct(document, ...
                "overlayShapesByStyle", context);
            result.ResizeConstraint = macd.catalog.ComponentCatalogLoader.optionalString(document, ...
                "resizeConstraint", "free", context);
            result.ResizeConstraintsByStyle = macd.catalog.ComponentCatalogLoader.optionalStruct(document, ...
                "resizeConstraintsByStyle", context);
            result = macd.catalog.ComponentCatalogLoader.appendMetadata(result, document, context);
        end

        function result = appendMetadata(result, document, context)
            % appendMetadata Convert the small strict extension metadata object.
            arguments (Input)
                result (1, 1) struct
                document (1, 1) struct
                context (1, 1) string
            end
            arguments (Output)
                result (1, 1) struct
            end

            % Preserve only the existing Phase 4.5 extension fields in schema v1.
            if ~isfield(document, "metadata")
                return
            end
            metadata = document.metadata;
            if ~isstruct(metadata) || ~isscalar(metadata)
                macd.catalog.ComponentCatalogLoader.fail(context + ".metadata", "Expected one object.");
            end
            macd.catalog.ComponentCatalogLoader.rejectUnknownFields(metadata, ...
                ["introduced", "numericProperties", "extensible"], ...
                context + ".metadata");
            if isfield(metadata, "introduced")
                result.Introduced = macd.catalog.ComponentCatalogLoader.scalarString(metadata.introduced, ...
                    context + ".metadata.introduced");
            end
            if isfield(metadata, "numericProperties")
                result.NumericProperties = macd.catalog.ComponentCatalogLoader.stringList( ...
                    metadata.numericProperties, context + ".metadata.numericProperties");
            end
            if isfield(metadata, "extensible")
                value = metadata.extensible;
                if ~islogical(value) || ~isscalar(value)
                    macd.catalog.ComponentCatalogLoader.fail(context + ".metadata.extensible", ...
                        "Expected one logical value.");
                end
                result.Extensible = value;
            end
        end

        function result = styleOverrides(document, styles, context)
            % styleOverrides Validate symbolic future property overrides without executing them.
            arguments (Input)
                document struct
                styles (1, :) string
                context (1, 1) string
            end
            arguments (Output)
                result (1, 1) struct
            end

            % Store only known style records for Phase 6.4 to consume later.
            if ~isstruct(document) || ~isscalar(document)
                macd.catalog.ComponentCatalogLoader.fail(context, "Expected one object.");
            end
            result = orderfields(document);
            names = string(fieldnames(result));
            for index = 1:numel(names)
                name = names(index);
                if ~any(styles == name)
                    macd.catalog.ComponentCatalogLoader.fail(context + "." + name, ...
                        "Override names a style not declared by capabilities.");
                end
                override = result.(char(name));
                if ~isstruct(override) || ~isscalar(override)
                    macd.catalog.ComponentCatalogLoader.fail(context + "." + name, "Expected one object.");
                end
                macd.catalog.ComponentCatalogLoader.rejectUnknownFields(override, ...
                    ["addProperties", "excludeProperties", "overrides"], ...
                    context + "." + name);
            end
        end

        function result = creationArguments(value, context)
            % creationArguments Normalize the empty or cell-backed v1 argument list.
            arguments (Input)
                value
                context (1, 1) string
            end
            arguments (Output)
                result cell
            end

            % Current R2024a catalog entries have no creation arguments; reject ambiguity.
            if isempty(value)
                result = {};
            elseif iscell(value)
                result = reshape(value, 1, []);
            else
                macd.catalog.ComponentCatalogLoader.fail(context, ...
                    "Expected an empty array or a JSON array of argument values.");
            end
        end

        function document = readDocument(root, relativePath)
            % readDocument Read one manifest-relative JSON object with safe path checks.
            arguments (Input)
                root (1, 1) string
                relativePath (1, 1) string
            end
            arguments (Output)
                document (1, 1) struct
            end

            % Reject traversal and absolute paths before file I/O.
            if strlength(relativePath) == 0 || isfile(relativePath) || ...
                    contains(relativePath, "..") || startsWith(relativePath, ["/", "\"])
                macd.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, ...
                    "Catalog paths must be nonempty manifest-relative paths.");
            end
            filePath = fullfile(root, relativePath);
            if ~isfile(filePath)
                macd.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, "Catalog file does not exist.");
            end
            try
                document = jsondecode(fileread(filePath));
            catch exception
                macd.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, ...
                    "Invalid JSON: " + string(exception.message));
            end
            if ~isstruct(document) || ~isscalar(document)
                macd.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, "Expected one JSON object.");
            end
        end

        function values = objectList(value, context)
            % objectList Normalize JSON arrays of objects to a cell array.
            arguments (Input)
                value
                context (1, 1) string
            end
            arguments (Output)
                values (1, :) cell
            end

            % Keep heterogeneous JSON objects separate because MATLAB structs cannot concatenate them.
            if iscell(value)
                if ~all(cellfun(@(item) isstruct(item) && isscalar(item), value))
                    macd.catalog.ComponentCatalogLoader.fail(context, "Expected an array of objects.");
                end
                values = reshape(value, 1, []);
            elseif isstruct(value)
                values = num2cell(reshape(value, 1, []));
            else
                macd.catalog.ComponentCatalogLoader.fail(context, "Expected an array of objects.");
            end
        end

        function values = stringList(value, context)
            % stringList Normalize a JSON string array to a row string array.
            arguments (Input)
                value
                context (1, 1) string
            end
            arguments (Output)
                values (1, :) string
            end

            % Accept the jsondecode cell representation while rejecting mixed values.
            if isempty(value)
                values = strings(1, 0);
            elseif iscell(value) && all(cellfun(@(item) ischar(item) || ...
                    (isstring(item) && isscalar(item)), value))
                values = reshape(string(value), 1, []);
            elseif ischar(value) || (isstring(value) && isscalar(value))
                values = string(value);
            else
                macd.catalog.ComponentCatalogLoader.fail(context, "Expected a JSON string array.");
            end
        end

        function value = scalarString(value, context)
            % scalarString Validate one scalar text value.
            arguments (Input)
                value
                context (1, 1) string
            end
            arguments (Output)
                value (1, 1) string
            end

            % Keep JSON text conversion local to the catalog boundary.
            if ~(ischar(value) || (isstring(value) && isscalar(value)))
                macd.catalog.ComponentCatalogLoader.fail(context, "Expected one JSON string.");
            end
            value = string(value);
            if strlength(value) == 0
                macd.catalog.ComponentCatalogLoader.fail(context, "Text must not be empty.");
            end
        end

        function value = optionalString(document, fieldName, defaultValue, context)
            % optionalString Return one optional nonempty scalar text capability.
            arguments (Input)
                document (1, 1) struct
                fieldName (1, 1) string
                defaultValue (1, 1) string
                context (1, 1) string
            end
            arguments (Output)
                value (1, 1) string
            end

            if isfield(document, char(fieldName))
                value = macd.catalog.ComponentCatalogLoader.scalarString( ...
                    document.(char(fieldName)), context + "." + fieldName);
            else
                value = defaultValue;
            end
        end

        function value = optionalLogical(document, fieldName, defaultValue, context)
            % optionalLogical Return one optional scalar logical capability.
            arguments (Input)
                document (1, 1) struct
                fieldName (1, 1) string
                defaultValue (1, 1) logical
                context (1, 1) string
            end
            arguments (Output)
                value (1, 1) logical
            end

            value = defaultValue;
            if isfield(document, char(fieldName))
                value = document.(char(fieldName));
                if ~islogical(value) || ~isscalar(value)
                    macd.catalog.ComponentCatalogLoader.fail(context + "." + fieldName, ...
                        "Expected one logical value.");
                end
            end
        end

        function value = optionalStringList(document, fieldName, context)
            % optionalStringList Return one optional JSON string array capability.
            arguments (Input)
                document (1, 1) struct
                fieldName (1, 1) string
                context (1, 1) string
            end
            arguments (Output)
                value (1, :) string
            end

            value = strings(1, 0);
            if isfield(document, char(fieldName))
                value = macd.catalog.ComponentCatalogLoader.stringList( ...
                    document.(char(fieldName)), context + "." + fieldName);
            end
        end

        function value = optionalStruct(document, fieldName, context)
            % optionalStruct Return one optional scalar JSON object capability.
            arguments (Input)
                document (1, 1) struct
                fieldName (1, 1) string
                context (1, 1) string
            end
            arguments (Output)
                value (1, 1) struct
            end

            value = struct();
            if isfield(document, char(fieldName))
                value = document.(char(fieldName));
                if ~isstruct(value) || ~isscalar(value)
                    macd.catalog.ComponentCatalogLoader.fail(context + "." + fieldName, ...
                        "Expected one object.");
                end
                value = orderfields(value);
            end
        end

        function requireFields(document, required, context)
            % requireFields Reject a JSON object that omits required fields.
            arguments (Input)
                document (1, 1) struct
                required (1, :) string
                context (1, 1) string
            end

            for fieldName = required
                if ~isfield(document, char(fieldName))
                    macd.catalog.ComponentCatalogLoader.fail(context, ...
                        "Missing required field """ + fieldName + """.");
                end
            end
        end

        function rejectUnknownFields(document, allowed, context)
            % rejectUnknownFields Reject undeclared keys to keep schema evolution explicit.
            arguments (Input)
                document (1, 1) struct
                allowed (1, :) string
                context (1, 1) string
            end

            names = fieldnames(document);
            for index = 1:numel(names)
                fieldName = string(names{index});
                if any(allowed == fieldName)
                    continue
                end
                macd.catalog.ComponentCatalogLoader.fail(context + "." + fieldName, ...
                    "Unknown field """ + fieldName + """.");
            end
        end

        function fail(context, message)
            % fail Throw one catalog error with a file and logical JSON-path context.
            arguments (Input)
                context (1, 1) string
                message (1, 1) string
            end

            error("macd:ComponentCatalogLoader:InvalidCatalog", "%s: %s", context, message);
        end
    end
end

%{
MatlabAppClassDesigner - Strict JSON loader for the programmatic UI component catalog.
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
