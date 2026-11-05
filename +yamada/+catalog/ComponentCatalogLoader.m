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
                catalogRoot (1, 1) string = yamada.catalog.ComponentCatalogLoader.defaultCatalogRoot()
            end
            arguments (Output)
                registry (1, 1) yamada.model.ComponentRegistry
            end

            % Read all source data before creating the return registry.
            manifest = yamada.catalog.ComponentCatalogLoader.readDocument(catalogRoot, "catalog.json");
            yamada.catalog.ComponentCatalogLoader.requireFields(manifest, ["schemaVersion", ...
                "matlabRelease", "propertyGroupFiles", "componentFiles"], ...
                catalogRoot + "/catalog.json");
            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(manifest, ["schemaVersion", ...
                "matlabRelease", "propertyGroupFiles", "componentFiles", "parentContextRules", ...
                "sourceGroupingSha256", "orderProfileFiles", "inspectorRowFiles"], ...
                catalogRoot + "/catalog.json");
            if manifest.schemaVersion == 2
                registry = yamada.catalog.ComponentCatalogLoader.loadVersion2(catalogRoot, manifest);
                return
            end
            if manifest.schemaVersion ~= 1 || string(manifest.matlabRelease) ~= "R2024a"
                yamada.catalog.ComponentCatalogLoader.fail(catalogRoot + "/catalog.json", ...
                    "schemaVersion must be 1 and matlabRelease must be R2024a.");
            end
            groups = yamada.catalog.ComponentCatalogLoader.readGroups(catalogRoot, ...
                yamada.catalog.ComponentCatalogLoader.stringList(manifest.propertyGroupFiles, ...
                catalogRoot + "/catalog.json.propertyGroupFiles"));
            componentFiles = yamada.catalog.ComponentCatalogLoader.stringList(manifest.componentFiles, ...
                catalogRoot + "/catalog.json.componentFiles");

            % Register only after every component definition has validated successfully.
            definitions = yamada.model.ComponentDefinition.empty;
            factories = strings(1, 0);
            for index = 1:numel(componentFiles)
                relativePath = componentFiles(index);
                component = yamada.catalog.ComponentCatalogLoader.readDocument(catalogRoot, relativePath);
                context = catalogRoot + "/" + relativePath;
                definition = yamada.catalog.ComponentCatalogLoader.componentDefinition(component, groups, context);
                if any(factories == definition.Factory)
                    yamada.catalog.ComponentCatalogLoader.fail(context + ".factory", ...
                        "Duplicate factory """ + definition.Factory + """.");
                end
                factories(end + 1) = definition.Factory; %#ok<AGROW>
                definitions(end + 1) = definition; %#ok<AGROW>
            end
            registry = yamada.model.ComponentRegistry();
            if isfield(manifest, "parentContextRules")
                registry.setParentContextRules(yamada.catalog.ComponentCatalogLoader.parentContextRules( ...
                    manifest.parentContextRules, catalogRoot + "/catalog.json.parentContextRules"));
            end
            for index = 1:numel(definitions)
                registry.register(definitions(index));
            end
            yamada.catalog.ComponentCatalogLoader.validateApplicationContexts(registry);
        end

        function root = defaultCatalogRoot()
            % defaultCatalogRoot Return the packaged standard catalog location.
            arguments (Output)
                root (1, 1) string
            end

            % Resolve from this package file so the current folder is irrelevant.
            sourcePath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(sourcePath)));
            root = string(fullfile(projectRoot, "resources", "component-catalog", "R2024a"));
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
                registry (1, 1) yamada.model.ComponentRegistry
            end

            if string(manifest.matlabRelease) ~= "R2024a"
                yamada.catalog.ComponentCatalogLoader.fail(root + "/catalog.json", ...
                    "schemaVersion 2 requires matlabRelease R2024a.");
            end
            groups = yamada.catalog.ComponentCatalogLoader.readVersion2Groups(root, ...
                yamada.catalog.ComponentCatalogLoader.stringList(manifest.propertyGroupFiles, ...
                root + "/catalog.json.propertyGroupFiles"));
            if ~isfield(manifest, "orderProfileFiles")
                yamada.catalog.ComponentCatalogLoader.fail(root + "/catalog.json", ...
                    "schemaVersion 2 requires orderProfileFiles.");
            end
            profiles = yamada.catalog.ComponentCatalogLoader.readOrderProfiles(root, ...
                yamada.catalog.ComponentCatalogLoader.stringList(manifest.orderProfileFiles, ...
                root + "/catalog.json.orderProfileFiles"));
            inspectorRows = yamada.model.InspectorRowDefinition.empty;
            if isfield(manifest, "inspectorRowFiles")
                inspectorRows = yamada.catalog.ComponentCatalogLoader.readInspectorRows(root, ...
                    yamada.catalog.ComponentCatalogLoader.stringList(manifest.inspectorRowFiles, ...
                    root + "/catalog.json.inspectorRowFiles"));
            end
            files = yamada.catalog.ComponentCatalogLoader.stringList(manifest.componentFiles, ...
                root + "/catalog.json.componentFiles");
            registry = yamada.model.ComponentRegistry();
            if isfield(manifest, "parentContextRules")
                registry.setParentContextRules(yamada.catalog.ComponentCatalogLoader.parentContextRules( ...
                    manifest.parentContextRules, root + "/catalog.json.parentContextRules"));
            end
            variantIds = strings(1, 0);
            for index = 1:numel(files)
                relativePath = files(index);
                document = yamada.catalog.ComponentCatalogLoader.readDocument(root, relativePath);
                context = root + "/" + relativePath;
                definition = yamada.catalog.ComponentCatalogLoader.componentDefinitionVersion2( ...
                    document, groups, profiles, context);
                if any(variantIds == definition.Id)
                    yamada.catalog.ComponentCatalogLoader.fail(context + ".id", ...
                        "Duplicate concrete component variant ID \"" + definition.Id + "\".");
                end
                variantIds(end + 1) = definition.Id; %#ok<AGROW>
                registry.register(definition);
            end
            yamada.catalog.ComponentCatalogLoader.validateInspectorRowComponentIds( ...
                inspectorRows, variantIds, root + "/catalog.json.inspectorRowFiles");
            registry.setInspectorRowDefinitions(inspectorRows);
            yamada.catalog.ComponentCatalogLoader.validateApplicationContexts(registry);
        end

        function validateApplicationContexts(registry)
            % validateApplicationContexts Reject dependencies invalidated by a permitted parent.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry
            end

            % Resolve every audited concrete variant through its direct-parent rules.
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                parents = definition.AllowedParentFactories;
                if definition.IsRoot || isempty(parents), parents = ""; end
                for parent = parents
                    registry.getEffectiveProperties(definition.Factory, parent, definition.CreationArguments);
                end
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
                document = yamada.catalog.ComponentCatalogLoader.readDocument(root, relativePath);
                context = root + "/" + relativePath;
                yamada.catalog.ComponentCatalogLoader.requireFields(document, ...
                    ["artifactVersion", "matlabRelease", "groups"], context);
                yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(document, ...
                    ["artifactVersion", "matlabRelease", "inputSha256", "groups"], context);
                if document.artifactVersion ~= 1 || string(document.matlabRelease) ~= "R2024a"
                    yamada.catalog.ComponentCatalogLoader.fail(context, ...
                        "Expected R2024a property-group artifactVersion 1.");
                end
                groupList = yamada.catalog.ComponentCatalogLoader.objectList(document.groups, context + ".groups");
                for groupIndex = 1:numel(groupList)
                    value = groupList{groupIndex};
                    yamada.catalog.ComponentCatalogLoader.requireFields(value, ...
                        ["id", "kind", "categoryId", "entries"], context + ".groups");
                    yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(value, ...
                        ["id", "kind", "categoryId", "entries"], context + ".groups");
                    id = yamada.catalog.ComponentCatalogLoader.scalarString(value.id, context + ".groups.id");
                    if isKey(groups, char(id))
                        yamada.catalog.ComponentCatalogLoader.fail(context + ".groups.id", ...
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
                document = yamada.catalog.ComponentCatalogLoader.readDocument(root, files(fileIndex));
                context = root + "/" + files(fileIndex);
                yamada.catalog.ComponentCatalogLoader.requireFields(document, ...
                    ["artifactVersion", "matlabRelease", "profiles"], context);
                profileList = yamada.catalog.ComponentCatalogLoader.objectList(document.profiles, context + ".profiles");
                for profileIndex = 1:numel(profileList)
                    value = profileList{profileIndex};
                    id = yamada.catalog.ComponentCatalogLoader.scalarString(value.id, context + ".profiles.id");
                    if isKey(profiles, char(id))
                        yamada.catalog.ComponentCatalogLoader.fail(context + ".profiles.id", ...
                            "Duplicate order profile \"" + id + "\".");
                    end
                    profiles(char(id)) = yamada.catalog.ComponentCatalogLoader.stringList( ...
                        value.categoryOrder, context + ".profiles.categoryOrder");
                end
            end
        end

        function definitions = readInspectorRows(root, files)
            % readInspectorRows Load strict presentation-only composite row templates.
            arguments (Input)
                root (1, 1) string
                files (1, :) string
            end
            arguments (Output)
                definitions yamada.model.InspectorRowDefinition
            end

            definitions = yamada.model.InspectorRowDefinition.empty;
            for fileIndex = 1:numel(files)
                relativePath = files(fileIndex);
                document = yamada.catalog.ComponentCatalogLoader.readDocument(root, relativePath);
                context = root + "/" + relativePath;
                yamada.catalog.ComponentCatalogLoader.requireFields(document, ...
                    ["artifactVersion", "matlabRelease", "rows"], context);
                yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(document, ...
                    ["artifactVersion", "matlabRelease", "rows"], context);
                if document.artifactVersion ~= 1 || string(document.matlabRelease) ~= "R2024a"
                    yamada.catalog.ComponentCatalogLoader.fail(context, ...
                        "Expected R2024a inspector-row artifactVersion 1.");
                end
                rows = yamada.catalog.ComponentCatalogLoader.objectList(document.rows, context + ".rows");
                for rowIndex = 1:numel(rows)
                    row = rows{rowIndex};
                    rowContext = context + ".rows[" + string(rowIndex) + "]";
                    yamada.catalog.ComponentCatalogLoader.requireFields(row, ...
                        ["id", "displayName", "editor", "members", "orderAnchor", "match"], rowContext);
                    yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(row, ...
                        ["id", "displayName", "editor", "members", "categoryId", "orderAnchor", "match"], rowContext);
                    id = yamada.catalog.ComponentCatalogLoader.scalarString(row.id, rowContext + ".id");
                    displayName = yamada.catalog.ComponentCatalogLoader.scalarString( ...
                        row.displayName, rowContext + ".displayName");
                    editor = yamada.catalog.ComponentCatalogLoader.scalarString(row.editor, rowContext + ".editor");
                    if ~any(editor == ["tableData", "columnSettings", "items", "fontStyle"])
                        yamada.catalog.ComponentCatalogLoader.fail(rowContext + ".editor", ...
                            "Unknown composite Inspector editor.");
                    end
                    members = yamada.catalog.ComponentCatalogLoader.objectList(row.members, rowContext + ".members");
                    if numel(members) < 2
                        yamada.catalog.ComponentCatalogLoader.fail(rowContext + ".members", ...
                            "A composite Inspector row requires at least two members.");
                    end
                    paths = strings(1, numel(members));
                    roles = strings(1, numel(members));
                    for memberIndex = 1:numel(members)
                        member = members{memberIndex};
                        memberContext = rowContext + ".members[" + string(memberIndex) + "]";
                        yamada.catalog.ComponentCatalogLoader.requireFields(member, ["path", "role"], memberContext);
                        yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(member, ["path", "role"], memberContext);
                        paths(memberIndex) = yamada.catalog.ComponentCatalogLoader.scalarString( ...
                            member.path, memberContext + ".path");
                        roles(memberIndex) = yamada.catalog.ComponentCatalogLoader.scalarString( ...
                            member.role, memberContext + ".role");
                    end
                    if numel(unique(paths)) ~= numel(paths) || numel(unique(roles)) ~= numel(roles)
                        yamada.catalog.ComponentCatalogLoader.fail(rowContext + ".members", ...
                            "Member paths and roles must each be unique.");
                    end
                    orderAnchor = yamada.catalog.ComponentCatalogLoader.scalarString( ...
                        row.orderAnchor, rowContext + ".orderAnchor");
                    if ~any(paths == orderAnchor)
                        yamada.catalog.ComponentCatalogLoader.fail(rowContext + ".orderAnchor", ...
                            "The order anchor must name one member path.");
                    end
                    categoryId = "";
                    if isfield(row, "categoryId")
                        if ~(ischar(row.categoryId) || (isstring(row.categoryId) && isscalar(row.categoryId)))
                            yamada.catalog.ComponentCatalogLoader.fail(rowContext + ".categoryId", ...
                                "Expected one JSON string.");
                        end
                        categoryId = string(row.categoryId);
                    end
                    match = row.match;
                    if ~isstruct(match) || ~isscalar(match)
                        yamada.catalog.ComponentCatalogLoader.fail(rowContext + ".match", "Expected one object.");
                    end
                    yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(match, ...
                        ["componentIds", "parentContextIds"], rowContext + ".match");
                    componentIds = yamada.catalog.ComponentCatalogLoader.optionalStringList( ...
                        match, "componentIds", rowContext + ".match");
                    parentContextIds = yamada.catalog.ComponentCatalogLoader.optionalStringList( ...
                        match, "parentContextIds", rowContext + ".match");
                    definitions(end + 1) = yamada.model.InspectorRowDefinition( ...
                        id, displayName, editor, paths, roles, categoryId, orderAnchor, ...
                        componentIds, parentContextIds); %#ok<AGROW>
                end
            end
            ids = string({definitions.Id});
            if numel(ids) ~= numel(unique(ids))
                yamada.catalog.ComponentCatalogLoader.fail(root + "/catalog.json.inspectorRowFiles", ...
                    "Composite Inspector row IDs must be unique.");
            end
        end

        function validateInspectorRowComponentIds(definitions, componentIds, context)
            % validateInspectorRowComponentIds Reject templates scoped to unknown concrete variants.
            arguments (Input)
                definitions yamada.model.InspectorRowDefinition
                componentIds (1, :) string
                context (1, 1) string
            end

            for index = 1:numel(definitions)
                unknown = definitions(index).ComponentIds(~ismember( ...
                    definitions(index).ComponentIds, componentIds));
                if ~isempty(unknown)
                    yamada.catalog.ComponentCatalogLoader.fail(context, ...
                        "Composite Inspector row " + definitions(index).Id + ...
                        " names unknown component variant " + unknown(1) + ".");
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
                definition (1, 1) yamada.model.ComponentDefinition
            end

            required = ["id", "factory", "declaredType", "allowedParentFactories", ...
                "isRoot", "creationArguments", "profileId", "profileDelta", "categories", "capabilities"];
            yamada.catalog.ComponentCatalogLoader.requireFields(document, required, context);
            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(document, required, context);
            id = yamada.catalog.ComponentCatalogLoader.scalarString(document.id, context + ".id");
            profileId = yamada.catalog.ComponentCatalogLoader.scalarString(document.profileId, context + ".profileId");
            if ~isKey(profiles, char(profileId))
                yamada.catalog.ComponentCatalogLoader.fail(context + ".profileId", "Unknown order profile.");
            end
            factory = yamada.catalog.ComponentCatalogLoader.scalarString(document.factory, context + ".factory");
            declaredType = yamada.catalog.ComponentCatalogLoader.scalarString(document.declaredType, context + ".declaredType");
            parents = yamada.catalog.ComponentCatalogLoader.stringList(document.allowedParentFactories, context + ".allowedParentFactories");
            if ~islogical(document.isRoot) || ~isscalar(document.isRoot)
                yamada.catalog.ComponentCatalogLoader.fail(context + ".isRoot", "Expected one logical value.");
            end
            properties = yamada.model.PropertyDefinition.empty(0, 1);
            categories = yamada.catalog.ComponentCatalogLoader.objectList(document.categories, context + ".categories");
            yamada.catalog.ComponentCatalogLoader.validateProfileDelta( ...
                profiles(char(profileId)), document.profileDelta, categories, context + ".profileDelta");
            for categoryIndex = 1:numel(categories)
                category = categories{categoryIndex};
                categoryContext = context + ".categories[" + string(categoryIndex) + "]";
                yamada.catalog.ComponentCatalogLoader.requireFields(category, ...
                    ["id", "displayName", "order", "entries"], categoryContext);
                yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(category, ...
                    ["id", "displayName", "order", "entries"], categoryContext);
                entries = yamada.catalog.ComponentCatalogLoader.objectList(category.entries, categoryContext + ".entries");
                for entryIndex = 1:numel(entries)
                    entry = entries{entryIndex};
                    entryContext = categoryContext + ".entries[" + string(entryIndex) + "]";
                    yamada.catalog.ComponentCatalogLoader.requireFields(entry, ...
                        ["path", "groupId", "runtimeSetAccess", "metadata"], entryContext);
                    yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(entry, ...
                        ["path", "groupId", "runtimeSetAccess", "metadata"], entryContext);
                    groupId = yamada.catalog.ComponentCatalogLoader.scalarString(entry.groupId, entryContext + ".groupId");
                    if ~isKey(groups, char(groupId))
                        yamada.catalog.ComponentCatalogLoader.fail(entryContext + ".groupId", ...
                            "Unknown property group \"" + groupId + "\".");
                    end
                    yamada.catalog.ComponentCatalogLoader.validateVersion2GroupEntry( ...
                        groups(char(groupId)), entry, entryContext);
                    isEditable = string(entry.runtimeSetAccess) == "public";
                    properties(end + 1) = yamada.catalog.ComponentCatalogLoader.propertyDefinition( ...
                        struct("path", entry.path, "isEditable", isEditable, "metadata", entry.metadata), ...
                        entryContext); %#ok<AGROW>
                end
            end
            paths = string({properties.Path});
            if numel(paths) ~= numel(unique(paths))
                yamada.catalog.ComponentCatalogLoader.fail(context + ".categories", ...
                    "Expanded category entries must have unique property paths.");
            end
            capabilities = yamada.catalog.ComponentCatalogLoader.capabilities(document.capabilities, context + ".capabilities");
            capabilities.id = id;
            capabilities.profileId = profileId;
            yamada.model.PropertyApplicationPolicy.orderDefinitions(properties, context);
            definition = yamada.model.ComponentDefinition.fromPaths(factory, declaredType, parents, ...
                document.isRoot, yamada.catalog.ComponentCatalogLoader.creationArguments( ...
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

            yamada.catalog.ComponentCatalogLoader.requireFields(delta, ...
                ["omittedCategoryIds", "insertions"], context);
            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(delta, ...
                ["omittedCategoryIds", "insertions"], context);
            omitted = yamada.catalog.ComponentCatalogLoader.stringList(delta.omittedCategoryIds, ...
                context + ".omittedCategoryIds");
            if numel(unique(omitted)) ~= numel(omitted) || any(~ismember(omitted, profileOrder))
                yamada.catalog.ComponentCatalogLoader.fail(context + ".omittedCategoryIds", ...
                    "Profile omissions must be unique profile category IDs.");
            end
            expectedCore = profileOrder(~ismember(profileOrder, omitted));
            actual = strings(1, numel(categories));
            for index = 1:numel(categories)
                actual(index) = yamada.catalog.ComponentCatalogLoader.scalarString( ...
                    categories{index}.id, context + ".categories.id");
            end
            if numel(unique(actual)) ~= numel(actual)
                yamada.catalog.ComponentCatalogLoader.fail(context, "Category IDs must be unique.");
            end
            if ~isequal(actual(ismember(actual, expectedCore)), expectedCore)
                yamada.catalog.ComponentCatalogLoader.fail(context, ...
                    "Profile categories must retain their declared relative order.");
            end
            if isempty(delta.insertions)
                insertions = cell(1, 0);
            else
                insertions = yamada.catalog.ComponentCatalogLoader.objectList(delta.insertions, context + ".insertions");
            end
            insertedIds = strings(1, numel(insertions));
            for index = 1:numel(insertions)
                insertion = insertions{index};
                yamada.catalog.ComponentCatalogLoader.requireFields(insertion, ...
                    ["categoryId", "documentedOrder", "afterCategoryId", "beforeCategoryId"], ...
                    context + ".insertions[" + string(index) + "]");
                insertedIds(index) = yamada.catalog.ComponentCatalogLoader.scalarString( ...
                    insertion.categoryId, context + ".insertions[" + string(index) + "].categoryId");
            end
            if numel(unique(insertedIds)) ~= numel(insertedIds) || ...
                    any(ismember(insertedIds, profileOrder)) || ...
                    ~isequal(sort(insertedIds), sort(actual(~ismember(actual, expectedCore))))
                yamada.catalog.ComponentCatalogLoader.fail(context + ".insertions", ...
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

            matches = yamada.catalog.ComponentCatalogLoader.objectList(group.entries, context + ".group.entries");
            count = 0;
            for index = 1:numel(matches)
                if string(matches{index}.path) == string(entry.path)
                    count = count + 1;
                end
            end
            if count ~= 1
                yamada.catalog.ComponentCatalogLoader.fail(context + ".path", ...
                    "Property path is not owned exactly once by its declared group.");
            end
            if ~isstruct(entry.metadata) || ~isscalar(entry.metadata)
                yamada.catalog.ComponentCatalogLoader.fail(context + ".metadata", "Expected one object.");
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
                document = yamada.catalog.ComponentCatalogLoader.readDocument(root, relativePath);
                context = root + "/" + relativePath;
                yamada.catalog.ComponentCatalogLoader.requireFields(document, ["name", "entries"], context);
                yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(document, ["name", "entries"], context);
                name = yamada.catalog.ComponentCatalogLoader.scalarString(document.name, context + ".name");
                if isKey(groups, char(name))
                    yamada.catalog.ComponentCatalogLoader.fail(context + ".name", ...
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
                definition (1, 1) yamada.model.ComponentDefinition
            end

            % Enforce the compact schema used by the generated R2024a catalog.
            required = ["factory", "declaredType", "allowedParentFactories", ...
                "isRoot", "creationArguments", "properties", "capabilities"];
            optional = "styleOverrides";
            yamada.catalog.ComponentCatalogLoader.requireFields(document, required, context);
            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(document, [required, optional], context);
            factory = yamada.catalog.ComponentCatalogLoader.scalarString(document.factory, context + ".factory");
            declaredType = yamada.catalog.ComponentCatalogLoader.scalarString(document.declaredType, ...
                context + ".declaredType");
            parents = yamada.catalog.ComponentCatalogLoader.stringList(document.allowedParentFactories, ...
                context + ".allowedParentFactories");
            if ~islogical(document.isRoot) || ~isscalar(document.isRoot)
                yamada.catalog.ComponentCatalogLoader.fail(context + ".isRoot", "Expected one logical value.");
            end
            creationArguments = yamada.catalog.ComponentCatalogLoader.creationArguments( ...
                document.creationArguments, context + ".creationArguments");
            properties = yamada.catalog.ComponentCatalogLoader.expandProperties(document.properties, groups, ...
                strings(1, 0), context + ".properties");
            capabilities = yamada.catalog.ComponentCatalogLoader.capabilities(document.capabilities, ...
                context + ".capabilities");
            if isfield(document, "styleOverrides")
                capabilities.StyleOverrides = yamada.catalog.ComponentCatalogLoader.styleOverrides( ...
                    document.styleOverrides, capabilities.SupportedStyles, ...
                    context + ".styleOverrides");
            end
            yamada.model.PropertyApplicationPolicy.orderDefinitions(properties, context);
            definition = yamada.model.ComponentDefinition.fromPaths(factory, declaredType, ...
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
                properties yamada.model.PropertyDefinition
            end

            % Append definitions in source order while rejecting duplicate property paths.
            properties = yamada.model.PropertyDefinition.empty(0, 1);
            entryList = yamada.catalog.ComponentCatalogLoader.objectList(entries, context);
            for index = 1:numel(entryList)
                entry = entryList{index};
                entryContext = context + "[" + string(index) + "]";
                hasGroup = isfield(entry, "group");
                hasPath = isfield(entry, "path");
                if hasGroup == hasPath
                    yamada.catalog.ComponentCatalogLoader.fail(entryContext, ...
                        "Each property entry must contain exactly one of group or path.");
                end
                if hasGroup
                    yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(entry, "group", entryContext);
                    groupName = yamada.catalog.ComponentCatalogLoader.scalarString(entry.group, ...
                        entryContext + ".group");
                    if any(stack == groupName)
                        yamada.catalog.ComponentCatalogLoader.fail(entryContext + ".group", ...
                            "Property group cycle: " + strjoin([stack, groupName], " -> ") + ".");
                    end
                    if ~isKey(groups, char(groupName))
                        yamada.catalog.ComponentCatalogLoader.fail(entryContext + ".group", ...
                            "Unknown property group """ + groupName + """.");
                    end
                    group = groups(char(groupName));
                    nextStack = strings(1, numel(stack) + 1);
                    nextStack(1:numel(stack)) = stack;
                    nextStack(end) = groupName;
                    expanded = yamada.catalog.ComponentCatalogLoader.expandProperties(group.Entries, groups, ...
                        nextStack, group.Context + ".entries");
                    properties = [properties; expanded(:)]; %#ok<AGROW>
                else
                    properties = [properties; yamada.catalog.ComponentCatalogLoader.propertyDefinition( ...
                        entry, entryContext)]; %#ok<AGROW>
                end
            end
            paths = string({properties.Path});
            if numel(unique(paths)) ~= numel(paths)
                yamada.catalog.ComponentCatalogLoader.fail(context, "Expanded property paths must be unique.");
            end
        end

        function definition = propertyDefinition(document, context)
            % propertyDefinition Convert one property document to a typed capability.
            arguments (Input)
                document struct
                context (1, 1) string
            end
            arguments (Output)
                definition (1, 1) yamada.model.PropertyDefinition
            end

            % Validate the stable v1 fields before retaining optional metadata.
            allowed = ["path", "defaultValue", "hasDefault", "isEditable", "metadata"];
            yamada.catalog.ComponentCatalogLoader.requireFields(document, "path", context);
            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(document, allowed, context);
            path = yamada.catalog.ComponentCatalogLoader.scalarString(document.path, context + ".path");
            hasDefault = isfield(document, "hasDefault") && document.hasDefault;
            if ~islogical(hasDefault) || ~isscalar(hasDefault)
                yamada.catalog.ComponentCatalogLoader.fail(context + ".hasDefault", "Expected one logical value.");
            end
            if hasDefault && ~isfield(document, "defaultValue")
                yamada.catalog.ComponentCatalogLoader.fail(context, ...
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
                yamada.catalog.ComponentCatalogLoader.fail(context + ".isEditable", "Expected one logical value.");
            end
            metadata = struct();
            if isfield(document, "metadata")
                if ~isstruct(document.metadata) || ~isscalar(document.metadata)
                    yamada.catalog.ComponentCatalogLoader.fail(context + ".metadata", "Expected one object.");
                end
                metadata = document.metadata;
                yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(metadata, ...
                    ["editor", "validator", "previewPolicy", "resetPolicy", ...
                    "displayName", "category", "order", "valueSchema", ...
                    "applicableStyles", "auditDisposition", "description", ...
                    "categoryId", "groupId", "application", "gridGeometryImpact", "absoluteGeometryImpact", "callbackSignature", "handlerSuffix"], ...
                    context + ".metadata");
                yamada.catalog.PropertyBehaviorRegistry.validateMetadata(metadata, context);
                if isfield(metadata, "callbackSignature")
                    if ~isfield(metadata, "valueSchema") || ~isfield(metadata.valueSchema, "kind") || string(metadata.valueSchema.kind) ~= "callback"
                        yamada.catalog.ComponentCatalogLoader.fail(context, "Callback signatures require a callback property.");
                    end
                    try
                        yamada.model.CallbackSignature(metadata.callbackSignature);
                    catch exception
                        yamada.catalog.ComponentCatalogLoader.fail(context + ".callbackSignature", string(exception.message));
                    end
                end
                if isfield(metadata, "application")
                    yamada.model.PropertyApplicationPolicy(metadata.application, context + ".metadata.application");
                end
                yamada.catalog.ComponentCatalogLoader.validatePropertyPresentationMetadata( ...
                    metadata, context + ".metadata");
            end
            definition = yamada.model.PropertyDefinition(path, defaultValue, hasDefault, ...
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
                yamada.catalog.ComponentCatalogLoader.scalarString(metadata.displayName, ...
                    context + ".displayName");
            end
            if isfield(metadata, "category")
                yamada.catalog.ComponentCatalogLoader.scalarString(metadata.category, ...
                    context + ".category");
            end
            if isfield(metadata, "order")
                order = metadata.order;
                if ~isnumeric(order) || ~isscalar(order) || ~isfinite(order)
                    yamada.catalog.ComponentCatalogLoader.fail(context + ".order", ...
                        "Expected one finite numeric value.");
                end
            end
            if isfield(metadata, "valueSchema")
                schema = metadata.valueSchema;
                if ~isstruct(schema) || ~isscalar(schema)
                    yamada.catalog.ComponentCatalogLoader.fail(context + ".valueSchema", ...
                        "Expected one object.");
                end
            end
            if isfield(metadata, "applicableStyles")
                yamada.catalog.ComponentCatalogLoader.stringList(metadata.applicableStyles, ...
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
                yamada.catalog.ComponentCatalogLoader.fail(context, "Expected one object.");
            end
            allowed = ["displayName", "category", "programmaticOnly", ...
                "requiresParentComponent", "supportedStyles", "defaultStyle", ...
                "declaredTypesByStyle", "overlayShape", "overlayShapesByStyle", ...
                "resizeConstraint", "resizeConstraintsByStyle", "defaultSize", "metadata"];
            yamada.catalog.ComponentCatalogLoader.requireFields(document, ["displayName", "category"], context);
            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(document, allowed, context);
            result = struct("DisplayName", yamada.catalog.ComponentCatalogLoader.scalarString( ...
                document.displayName, context + ".displayName"), ...
                "Category", yamada.catalog.ComponentCatalogLoader.scalarString(document.category, ...
                context + ".category"));
            result.ProgrammaticOnly = yamada.catalog.ComponentCatalogLoader.optionalLogical(document, ...
                "programmaticOnly", false, context);
            result.RequiresParentComponent = yamada.catalog.ComponentCatalogLoader.optionalLogical(document, ...
                "requiresParentComponent", false, context);
            result.SupportedStyles = yamada.catalog.ComponentCatalogLoader.optionalStringList(document, ...
                "supportedStyles", context);
            result.DefaultStyle = yamada.catalog.ComponentCatalogLoader.optionalString(document, ...
                "defaultStyle", "", context);
            result.DeclaredTypesByStyle = yamada.catalog.ComponentCatalogLoader.optionalStruct(document, ...
                "declaredTypesByStyle", context);
            result.OverlayShape = yamada.catalog.ComponentCatalogLoader.optionalString(document, ...
                "overlayShape", "rectangle", context);
            result.OverlayShapesByStyle = yamada.catalog.ComponentCatalogLoader.optionalStruct(document, ...
                "overlayShapesByStyle", context);
            result.ResizeConstraint = yamada.catalog.ComponentCatalogLoader.optionalString(document, ...
                "resizeConstraint", "free", context);
            result.ResizeConstraintsByStyle = yamada.catalog.ComponentCatalogLoader.optionalStruct(document, ...
                "resizeConstraintsByStyle", context);
            result.DefaultSize = yamada.catalog.ComponentCatalogLoader.optionalPositiveDoublePair(document, ...
                "defaultSize", [100 30], context);
            result = yamada.catalog.ComponentCatalogLoader.appendMetadata(result, document, context);
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

            % Preserve only the extension fields supported by schema version 1.
            if ~isfield(document, "metadata")
                return
            end
            metadata = document.metadata;
            if ~isstruct(metadata) || ~isscalar(metadata)
                yamada.catalog.ComponentCatalogLoader.fail(context + ".metadata", "Expected one object.");
            end
            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(metadata, ...
                ["introduced", "numericProperties", "extensible"], ...
                context + ".metadata");
            if isfield(metadata, "introduced")
                result.Introduced = yamada.catalog.ComponentCatalogLoader.scalarString(metadata.introduced, ...
                    context + ".metadata.introduced");
            end
            if isfield(metadata, "numericProperties")
                result.NumericProperties = yamada.catalog.ComponentCatalogLoader.stringList( ...
                    metadata.numericProperties, context + ".metadata.numericProperties");
            end
            if isfield(metadata, "extensible")
                value = metadata.extensible;
                if ~islogical(value) || ~isscalar(value)
                    yamada.catalog.ComponentCatalogLoader.fail(context + ".metadata.extensible", ...
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

            % Store only known style records for typed definition construction.
            if ~isstruct(document) || ~isscalar(document)
                yamada.catalog.ComponentCatalogLoader.fail(context, "Expected one object.");
            end
            result = orderfields(document);
            names = string(fieldnames(result));
            for index = 1:numel(names)
                name = names(index);
                if ~any(styles == name)
                    yamada.catalog.ComponentCatalogLoader.fail(context + "." + name, ...
                        "Override names a style not declared by capabilities.");
                end
                override = result.(char(name));
                if ~isstruct(override) || ~isscalar(override)
                    yamada.catalog.ComponentCatalogLoader.fail(context + "." + name, "Expected one object.");
                end
                yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(override, ...
                    ["addProperties", "excludeProperties", "overrides"], ...
                    context + "." + name);
            end
        end

        function rules = parentContextRules(value, context)
            % parentContextRules Validate allowlisted direct-parent context rules.
            entries = yamada.catalog.ComponentCatalogLoader.objectList(value, context);
            rules = yamada.model.ParentContextRule.empty;
            for index = 1:numel(entries)
                entry = entries{index};
                entryContext = context + "[" + string(index) + "]";
                yamada.catalog.ComponentCatalogLoader.requireFields(entry, ["parentFactories", "kind"], entryContext);
                yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(entry, ["parentFactories", "kind", "geometryImpacts"], entryContext);
                parents = yamada.catalog.ComponentCatalogLoader.stringList(entry.parentFactories, entryContext + ".parentFactories");
                kind = yamada.catalog.ComponentCatalogLoader.scalarString(entry.kind, entryContext + ".kind");
                try
                    rule = yamada.model.ParentContextRule.fromKind(parents, kind);
                    if isfield(entry, "geometryImpacts")
                        impacts = cell(1, 0);
                        if ~isequal(entry.geometryImpacts, [])
                            impacts = yamada.catalog.ComponentCatalogLoader.objectList(entry.geometryImpacts, entryContext + ".geometryImpacts");
                        end
                        properties = rule.AddedProperties;
                        paths = strings(1, numel(impacts));
                        for impactIndex = 1:numel(impacts)
                            impact = impacts{impactIndex};
                            yamada.catalog.ComponentCatalogLoader.requireFields(impact, ...
                                ["path", "gridGeometryImpact", "absoluteGeometryImpact"], entryContext);
                            yamada.catalog.ComponentCatalogLoader.rejectUnknownFields(impact, ...
                                ["path", "gridGeometryImpact", "absoluteGeometryImpact"], entryContext);
                            paths(impactIndex) = yamada.catalog.ComponentCatalogLoader.scalarString(impact.path, entryContext);
                            propertyIndex = find(string({properties.Path}) == paths(impactIndex), 1);
                            if isempty(propertyIndex), error("Unknown contributed geometry path."); end
                            metadata = properties(propertyIndex).Metadata;
                            metadata.gridGeometryImpact = impact.gridGeometryImpact;
                            metadata.absoluteGeometryImpact = impact.absoluteGeometryImpact;
                            yamada.catalog.PropertyBehaviorRegistry.validateMetadata(metadata, entryContext);
                            property = properties(propertyIndex);
                            properties(propertyIndex) = yamada.model.PropertyDefinition(property.Path, ...
                                property.DefaultValue, property.HasDefault, property.IsEditable, metadata);
                        end
                        if numel(unique(paths)) ~= numel(paths) || numel(paths) ~= numel(properties)
                            error("Geometry impacts must cover each contributed property exactly once.");
                        end
                        rule = yamada.model.ParentContextRule(parents, properties, rule.SuppressedPaths);
                    end
                    rules(end + 1) = rule; %#ok<AGROW>
                catch exception
                    yamada.catalog.ComponentCatalogLoader.fail(entryContext + ".kind", string(exception.message));
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
                yamada.catalog.ComponentCatalogLoader.fail(context, ...
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
                yamada.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, ...
                    "Catalog paths must be nonempty manifest-relative paths.");
            end
            filePath = fullfile(root, relativePath);
            if ~isfile(filePath)
                yamada.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, "Catalog file does not exist.");
            end
            try
                document = jsondecode(fileread(filePath));
            catch exception
                yamada.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, ...
                    "Invalid JSON: " + string(exception.message));
            end
            if ~isstruct(document) || ~isscalar(document)
                yamada.catalog.ComponentCatalogLoader.fail(root + "/" + relativePath, "Expected one JSON object.");
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
                    yamada.catalog.ComponentCatalogLoader.fail(context, "Expected an array of objects.");
                end
                values = reshape(value, 1, []);
            elseif isstruct(value)
                values = num2cell(reshape(value, 1, []));
            else
                yamada.catalog.ComponentCatalogLoader.fail(context, "Expected an array of objects.");
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
                yamada.catalog.ComponentCatalogLoader.fail(context, "Expected a JSON string array.");
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
                yamada.catalog.ComponentCatalogLoader.fail(context, "Expected one JSON string.");
            end
            value = string(value);
            if strlength(value) == 0
                yamada.catalog.ComponentCatalogLoader.fail(context, "Text must not be empty.");
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
                value = yamada.catalog.ComponentCatalogLoader.scalarString( ...
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
                    yamada.catalog.ComponentCatalogLoader.fail(context + "." + fieldName, ...
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
                value = yamada.catalog.ComponentCatalogLoader.stringList( ...
                    document.(char(fieldName)), context + "." + fieldName);
            end
        end

        function value = optionalPositiveDoublePair(document, fieldName, defaultValue, context)
            % optionalPositiveDoublePair Return one optional finite positive size pair.
            arguments (Input)
                document (1, 1) struct
                fieldName (1, 1) string
                defaultValue (1, 2) double
                context (1, 1) string
            end
            arguments (Output)
                value (1, 2) double
            end

            value = defaultValue;
            if ~isfield(document, char(fieldName))
                return
            end
            value = document.(char(fieldName));
            if ~isnumeric(value) || numel(value) ~= 2 || ...
                    any(~isfinite(value), "all") || any(value <= 0, "all")
                yamada.catalog.ComponentCatalogLoader.fail(context + "." + fieldName, ...
                    "Expected two finite positive numeric values.");
            end
            value = reshape(double(value), 1, 2);
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
                    yamada.catalog.ComponentCatalogLoader.fail(context + "." + fieldName, ...
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
                    yamada.catalog.ComponentCatalogLoader.fail(context, ...
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
                yamada.catalog.ComponentCatalogLoader.fail(context + "." + fieldName, ...
                    "Unknown field """ + fieldName + """.");
            end
        end

        function fail(context, message)
            % fail Throw one catalog error with a file and logical JSON-path context.
            arguments (Input)
                context (1, 1) string
                message (1, 1) string
            end

            error("yamada:ComponentCatalogLoader:InvalidCatalog", "%s: %s", context, message);
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
