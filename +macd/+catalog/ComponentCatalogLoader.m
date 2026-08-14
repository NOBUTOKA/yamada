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
                "matlabRelease", "propertyGroupFiles", "componentFiles", "parentContextRules", ...
                "sourceGroupingSha256", "orderProfileFiles"], ...
                catalogRoot + "/catalog.json");
            if manifest.schemaVersion == 2
                registry = macd.catalog.ComponentCatalogLoader.loadVersion2(catalogRoot, manifest);
                return
            end
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
            if isfield(manifest, "parentContextRules")
                registry.setParentContextRules(macd.catalog.ComponentCatalogLoader.parentContextRules( ...
                    manifest.parentContextRules, catalogRoot + "/catalog.json.parentContextRules"));
            end
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
            root = string(fullfile(projectRoot, "resources", "component-catalog", "v2"));
        end
    end

    methods (Static, Access = private)
        function registry = loadVersion2(root, manifest)
            % loadVersion2 Load concrete variants composed from audited group data.
            arguments (Input)
                root (1, 1) string
                manifest (1, 1) struct
            end
            arguments (Output)
                registry (1, 1) macd.model.ComponentRegistry
            end

            if string(manifest.matlabRelease) ~= "R2024a"
                macd.catalog.ComponentCatalogLoader.fail(root + "/catalog.json", ...
                    "schemaVersion 2 requires matlabRelease R2024a.");
            end
            groups = macd.catalog.ComponentCatalogLoader.readVersion2Groups(root, ...
                macd.catalog.ComponentCatalogLoader.stringList(manifest.propertyGroupFiles, ...
                root + "/catalog.json.propertyGroupFiles"));
            if ~isfield(manifest, "orderProfileFiles")
                macd.catalog.ComponentCatalogLoader.fail(root + "/catalog.json", ...
                    "schemaVersion 2 requires orderProfileFiles.");
            end
            profiles = macd.catalog.ComponentCatalogLoader.readOrderProfiles(root, ...
                macd.catalog.ComponentCatalogLoader.stringList(manifest.orderProfileFiles, ...
                root + "/catalog.json.orderProfileFiles"));
            files = macd.catalog.ComponentCatalogLoader.stringList(manifest.componentFiles, ...
                root + "/catalog.json.componentFiles");
            registry = macd.model.ComponentRegistry();
            if isfield(manifest, "parentContextRules")
                registry.setParentContextRules(macd.catalog.ComponentCatalogLoader.parentContextRules( ...
                    manifest.parentContextRules, root + "/catalog.json.parentContextRules"));
            end
            variantIds = strings(1, 0);
            for index = 1:numel(files)
                relativePath = files(index);
                document = macd.catalog.ComponentCatalogLoader.readDocument(root, relativePath);
                context = root + "/" + relativePath;
                definition = macd.catalog.ComponentCatalogLoader.componentDefinitionVersion2( ...
                    document, groups, profiles, context);
                if any(variantIds == definition.Id)
                    macd.catalog.ComponentCatalogLoader.fail(context + ".id", ...
                        "Duplicate concrete component variant ID \"" + definition.Id + "\".");
                end
                variantIds(end + 1) = definition.Id; %#ok<AGROW>
                registry.register(definition);
            end
        end

        function groups = readVersion2Groups(root, files)
            % readVersion2Groups Load the stable reusable property-group map.
            arguments (Input)
                root (1, 1) string
                files (1, :) string
            end
            arguments (Output)
                groups containers.Map
            end

            groups = containers.Map("KeyType", "char", "ValueType", "any");
            for fileIndex = 1:numel(files)
                relativePath = files(fileIndex);
                document = macd.catalog.ComponentCatalogLoader.readDocument(root, relativePath);
                context = root + "/" + relativePath;
                macd.catalog.ComponentCatalogLoader.requireFields(document, ...
                    ["artifactVersion", "matlabRelease", "groups"], context);
                macd.catalog.ComponentCatalogLoader.rejectUnknownFields(document, ...
                    ["artifactVersion", "matlabRelease", "inputSha256", "groups"], context);
                if document.artifactVersion ~= 1 || string(document.matlabRelease) ~= "R2024a"
                    macd.catalog.ComponentCatalogLoader.fail(context, ...
                        "Expected R2024a property-group artifactVersion 1.");
                end
                groupList = macd.catalog.ComponentCatalogLoader.objectList(document.groups, context + ".groups");
                for groupIndex = 1:numel(groupList)
                    value = groupList{groupIndex};
                    macd.catalog.ComponentCatalogLoader.requireFields(value, ...
                        ["id", "kind", "categoryId", "entries"], context + ".groups");
                    macd.catalog.ComponentCatalogLoader.rejectUnknownFields(value, ...
                        ["id", "kind", "categoryId", "entries"], context + ".groups");
                    id = macd.catalog.ComponentCatalogLoader.scalarString(value.id, context + ".groups.id");
                    if isKey(groups, char(id))
                        macd.catalog.ComponentCatalogLoader.fail(context + ".groups.id", ...
                            "Duplicate property group \"" + id + "\".");
                    end
                    groups(char(id)) = value;
                end
            end
        end

        function profiles = readOrderProfiles(root, files)
            % readOrderProfiles Load the reviewed reusable category-order profiles.
            arguments (Input)
                root (1, 1) string
                files (1, :) string
            end
            arguments (Output)
                profiles containers.Map
            end

            profiles = containers.Map("KeyType", "char", "ValueType", "any");
            for fileIndex = 1:numel(files)
                document = macd.catalog.ComponentCatalogLoader.readDocument(root, files(fileIndex));
                context = root + "/" + files(fileIndex);
                macd.catalog.ComponentCatalogLoader.requireFields(document, ...
                    ["artifactVersion", "matlabRelease", "profiles"], context);
                profileList = macd.catalog.ComponentCatalogLoader.objectList(document.profiles, context + ".profiles");
                for profileIndex = 1:numel(profileList)
                    value = profileList{profileIndex};
                    id = macd.catalog.ComponentCatalogLoader.scalarString(value.id, context + ".profiles.id");
                    if isKey(profiles, char(id))
                        macd.catalog.ComponentCatalogLoader.fail(context + ".profiles.id", ...
                            "Duplicate order profile \"" + id + "\".");
                    end
                    profiles(char(id)) = macd.catalog.ComponentCatalogLoader.stringList( ...
                        value.categoryOrder, context + ".profiles.categoryOrder");
                end
            end
        end

        function definition = componentDefinitionVersion2(document, groups, profiles, context)
            % componentDefinitionVersion2 Compose one concrete variant in category order.
            arguments (Input)
                document (1, 1) struct
                groups containers.Map
                profiles containers.Map
                context (1, 1) string
            end
            arguments (Output)
                definition (1, 1) macd.model.ComponentDefinition
            end

            required = ["id", "factory", "declaredType", "allowedParentFactories", ...
                "isRoot", "creationArguments", "profileId", "profileDelta", "categories", "capabilities"];
            macd.catalog.ComponentCatalogLoader.requireFields(document, required, context);
            macd.catalog.ComponentCatalogLoader.rejectUnknownFields(document, required, context);
            id = macd.catalog.ComponentCatalogLoader.scalarString(document.id, context + ".id");
            profileId = macd.catalog.ComponentCatalogLoader.scalarString(document.profileId, context + ".profileId");
            if ~isKey(profiles, char(profileId))
                macd.catalog.ComponentCatalogLoader.fail(context + ".profileId", "Unknown order profile.");
            end
            factory = macd.catalog.ComponentCatalogLoader.scalarString(document.factory, context + ".factory");
            declaredType = macd.catalog.ComponentCatalogLoader.scalarString(document.declaredType, context + ".declaredType");
            parents = macd.catalog.ComponentCatalogLoader.stringList(document.allowedParentFactories, context + ".allowedParentFactories");
            if ~islogical(document.isRoot) || ~isscalar(document.isRoot)
                macd.catalog.ComponentCatalogLoader.fail(context + ".isRoot", "Expected one logical value.");
            end
            properties = macd.model.PropertyDefinition.empty(0, 1);
            categories = macd.catalog.ComponentCatalogLoader.objectList(document.categories, context + ".categories");
            macd.catalog.ComponentCatalogLoader.validateProfileDelta( ...
                profiles(char(profileId)), document.profileDelta, categories, context + ".profileDelta");
            for categoryIndex = 1:numel(categories)
                category = categories{categoryIndex};
                categoryContext = context + ".categories[" + string(categoryIndex) + "]";
                macd.catalog.ComponentCatalogLoader.requireFields(category, ...
                    ["id", "displayName", "order", "entries"], categoryContext);
                macd.catalog.ComponentCatalogLoader.rejectUnknownFields(category, ...
                    ["id", "displayName", "order", "entries"], categoryContext);
                entries = macd.catalog.ComponentCatalogLoader.objectList(category.entries, categoryContext + ".entries");
                for entryIndex = 1:numel(entries)
                    entry = entries{entryIndex};
                    entryContext = categoryContext + ".entries[" + string(entryIndex) + "]";
                    macd.catalog.ComponentCatalogLoader.requireFields(entry, ...
                        ["path", "groupId", "runtimeSetAccess", "metadata"], entryContext);
                    macd.catalog.ComponentCatalogLoader.rejectUnknownFields(entry, ...
                        ["path", "groupId", "runtimeSetAccess", "metadata"], entryContext);
                    groupId = macd.catalog.ComponentCatalogLoader.scalarString(entry.groupId, entryContext + ".groupId");
                    if ~isKey(groups, char(groupId))
                        macd.catalog.ComponentCatalogLoader.fail(entryContext + ".groupId", ...
                            "Unknown property group \"" + groupId + "\".");
                    end
                    macd.catalog.ComponentCatalogLoader.validateVersion2GroupEntry( ...
                        groups(char(groupId)), entry, entryContext);
                    isEditable = string(entry.runtimeSetAccess) == "public";
                    properties(end + 1) = macd.catalog.ComponentCatalogLoader.propertyDefinition( ...
                        struct("path", entry.path, "isEditable", isEditable, "metadata", entry.metadata), ...
                        entryContext); %#ok<AGROW>
                end
            end
            paths = string({properties.Path});
            if numel(paths) ~= numel(unique(paths))
                macd.catalog.ComponentCatalogLoader.fail(context + ".categories", ...
                    "Expanded category entries must have unique property paths.");
            end
            capabilities = macd.catalog.ComponentCatalogLoader.capabilities(document.capabilities, context + ".capabilities");
            capabilities.id = id;
            capabilities.profileId = profileId;
            definition = macd.model.ComponentDefinition.fromPaths(factory, declaredType, parents, ...
                document.isRoot, macd.catalog.ComponentCatalogLoader.creationArguments( ...
                document.creationArguments, context + ".creationArguments"), properties, capabilities);
        end

        function validateProfileDelta(profileOrder, delta, categories, context)
            % validateProfileDelta Ensure profile omissions and insertions explain category order.
            arguments (Input)
                profileOrder (1, :) string
                delta (1, 1) struct
                categories cell
                context (1, 1) string
            end

            macd.catalog.ComponentCatalogLoader.requireFields(delta, ...
                ["omittedCategoryIds", "insertions"], context);
            macd.catalog.ComponentCatalogLoader.rejectUnknownFields(delta, ...
                ["omittedCategoryIds", "insertions"], context);
            omitted = macd.catalog.ComponentCatalogLoader.stringList(delta.omittedCategoryIds, ...
                context + ".omittedCategoryIds");
            if numel(unique(omitted)) ~= numel(omitted) || any(~ismember(omitted, profileOrder))
                macd.catalog.ComponentCatalogLoader.fail(context + ".omittedCategoryIds", ...
                    "Profile omissions must be unique profile category IDs.");
            end
            expectedCore = profileOrder(~ismember(profileOrder, omitted));
            actual = strings(1, numel(categories));
            for index = 1:numel(categories)
                actual(index) = macd.catalog.ComponentCatalogLoader.scalarString( ...
                    categories{index}.id, context + ".categories.id");
            end
            if numel(unique(actual)) ~= numel(actual)
                macd.catalog.ComponentCatalogLoader.fail(context, "Category IDs must be unique.");
            end
            if ~isequal(actual(ismember(actual, expectedCore)), expectedCore)
                macd.catalog.ComponentCatalogLoader.fail(context, ...
                    "Profile categories must retain their declared relative order.");
            end
            if isempty(delta.insertions)
                insertions = cell(1, 0);
            else
                insertions = macd.catalog.ComponentCatalogLoader.objectList(delta.insertions, context + ".insertions");
            end
            insertedIds = strings(1, numel(insertions));
            for index = 1:numel(insertions)
                insertion = insertions{index};
                macd.catalog.ComponentCatalogLoader.requireFields(insertion, ...
                    ["categoryId", "documentedOrder", "afterCategoryId", "beforeCategoryId"], ...
                    context + ".insertions[" + string(index) + "]");
                insertedIds(index) = macd.catalog.ComponentCatalogLoader.scalarString( ...
                    insertion.categoryId, context + ".insertions[" + string(index) + "].categoryId");
            end
            if numel(unique(insertedIds)) ~= numel(insertedIds) || ...
                    any(ismember(insertedIds, profileOrder)) || ...
                    ~isequal(sort(insertedIds), sort(actual(~ismember(actual, expectedCore))))
                macd.catalog.ComponentCatalogLoader.fail(context + ".insertions", ...
                    "Profile insertions must own every and only non-profile category.");
            end
        end

        function validateVersion2GroupEntry(group, entry, context)
            % validateVersion2GroupEntry Reject category entries that drift from group ownership.
            arguments (Input)
                group (1, 1) struct
                entry (1, 1) struct
                context (1, 1) string
            end

            matches = macd.catalog.ComponentCatalogLoader.objectList(group.entries, context + ".group.entries");
            count = 0;
            for index = 1:numel(matches)
                if string(matches{index}.path) == string(entry.path)
                    count = count + 1;
                end
            end
            if count ~= 1
                macd.catalog.ComponentCatalogLoader.fail(context + ".path", ...
                    "Property path is not owned exactly once by its declared group.");
            end
            if ~isstruct(entry.metadata) || ~isscalar(entry.metadata)
                macd.catalog.ComponentCatalogLoader.fail(context + ".metadata", "Expected one object.");
            end
        end

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
                group = struct();
                group.Entries = document.entries;
                group.Context = context;
                groups(char(name)) = group;
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
            properties = macd.model.PropertyDefinition.empty(0, 1);
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
                    nextStack = strings(1, numel(stack) + 1);
                    nextStack(1:numel(stack)) = stack;
                    nextStack(end) = groupName;
                    expanded = macd.catalog.ComponentCatalogLoader.expandProperties(group.Entries, groups, ...
                        nextStack, group.Context + ".entries");
                    properties = [properties; expanded(:)]; %#ok<AGROW>
                else
                    properties = [properties; macd.catalog.ComponentCatalogLoader.propertyDefinition( ...
                        entry, entryContext)]; %#ok<AGROW>
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
                    ["editor", "validator", "previewPolicy", "resetPolicy", ...
                    "displayName", "category", "order", "valueSchema", ...
                    "applicableStyles", "auditDisposition", "description", ...
                    "categoryId", "groupId"], ...
                    context + ".metadata");
                macd.catalog.PropertyBehaviorRegistry.validateMetadata(metadata, context);
                macd.catalog.ComponentCatalogLoader.validatePropertyPresentationMetadata( ...
                    metadata, context + ".metadata");
            end
            definition = macd.model.PropertyDefinition(path, defaultValue, hasDefault, ...
                isEditable, metadata);
        end

        function validatePropertyPresentationMetadata(metadata, context)
            % validatePropertyPresentationMetadata Validate non-behavior inspector metadata.
            arguments (Input)
                metadata (1, 1) struct
                context (1, 1) string
            end

            % Validate value shapes before the immutable definition projects them.
            if isfield(metadata, "displayName")
                macd.catalog.ComponentCatalogLoader.scalarString(metadata.displayName, ...
                    context + ".displayName");
            end
            if isfield(metadata, "category")
                macd.catalog.ComponentCatalogLoader.scalarString(metadata.category, ...
                    context + ".category");
            end
            if isfield(metadata, "order")
                order = metadata.order;
                if ~isnumeric(order) || ~isscalar(order) || ~isfinite(order)
                    macd.catalog.ComponentCatalogLoader.fail(context + ".order", ...
                        "Expected one finite numeric value.");
                end
            end
            if isfield(metadata, "valueSchema")
                schema = metadata.valueSchema;
                if ~isstruct(schema) || ~isscalar(schema)
                    macd.catalog.ComponentCatalogLoader.fail(context + ".valueSchema", ...
                        "Expected one object.");
                end
            end
            if isfield(metadata, "applicableStyles")
                macd.catalog.ComponentCatalogLoader.stringList(metadata.applicableStyles, ...
                    context + ".applicableStyles");
            end
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

        function rules = parentContextRules(value, context)
            % parentContextRules Validate allowlisted direct-parent context rules.
            entries = macd.catalog.ComponentCatalogLoader.objectList(value, context);
            rules = macd.model.ParentContextRule.empty;
            for index = 1:numel(entries)
                entry = entries{index};
                entryContext = context + "[" + string(index) + "]";
                macd.catalog.ComponentCatalogLoader.requireFields(entry, ["parentFactories", "kind"], entryContext);
                macd.catalog.ComponentCatalogLoader.rejectUnknownFields(entry, ["parentFactories", "kind"], entryContext);
                parents = macd.catalog.ComponentCatalogLoader.stringList(entry.parentFactories, entryContext + ".parentFactories");
                kind = macd.catalog.ComponentCatalogLoader.scalarString(entry.kind, entryContext + ".kind");
                try
                    rules(end + 1) = macd.model.ParentContextRule.fromKind(parents, kind); %#ok<AGROW>
                catch exception
                    macd.catalog.ComponentCatalogLoader.fail(entryContext + ".kind", string(exception.message));
                end
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

            % Retain JSON literal constructor arguments without evaluating them.
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
Copyright (C) 2026 Nobuto Kaitoh

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
