classdef AppSourceParser
    % AppSourceParser Parse a conservative handle-based source subset without running it.
    %   This static parser reads handle-based inheritance, component declarations,
    %   registry-supported factory calls, parent links, and direct property
    %   assignments into a shared DocumentModel. Unsupported expressions remain
    %   source-backed and are reported rather than evaluated or discarded.
    %
    %   Example:
    %       registry = yamada.model.ComponentRegistry.createDefault();
    %       document = yamada.source.AppSourceParser.parseFile( ...
    %           "ExampleApp.m", registry);

    %#ok<*AGROW> Parsed source findings are intentionally accumulated in source order.

    methods (Static)
        function [document, diagnostics] = parseFile(filePath, registry)
            % parseFile Read UTF-8 handle-based source and parse it without execution.
            arguments (Input)
                filePath (1, 1) string {mustBeFile}
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                diagnostics yamada.model.Diagnostic
            end

            % Read and validate UTF-8 bytes without executing input source.
            [bytes, readDiagnostic] = yamada.source.AppSourceParser.readBytes(filePath);
            hasBom = numel(bytes) >= 3 && ...
                isequal(bytes(1:3), uint8([239 187 191]));
            if hasBom
                bytes = bytes(4:end);
            end
            isValidUtf8 = yamada.source.AppSourceParser.isValidUtf8(bytes);
            source = string(native2unicode(bytes, "UTF-8"));

            % Block editing when decoding would irreversibly replace input bytes.
            if ~isValidUtf8
                document = yamada.model.DocumentModel("ParsedApp");
                document.FilePath = filePath;
                document.OriginalText = source;
                document.Encoding = "UTF-8";
                document.LineEnding = yamada.source.AppSourceParser.lineEnding(source);
                diagnostics = yamada.source.AppSourceParser.diagnostic( ...
                    "invalid-utf8", "error", ...
                    "Input source is not valid UTF-8 and cannot be edited safely.", ...
                    "", yamada.model.SourceSpan.empty);
                document.Diagnostics = diagnostics;
                return
            end

            % Parse decoded text and append file-format diagnostics afterwards.
            [document, diagnostics] = yamada.source.AppSourceParser.parseText( ...
                source, registry, filePath, strings(1, 0), string(matlabRelease().Release));
            if ~isempty(readDiagnostic)
                diagnostics(end + 1) = readDiagnostic;
            end
            if hasBom
                diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                    "utf8-bom", "warning", ...
                    "Input source has a UTF-8 BOM; it is retained only in diagnostics.", ...
                    "", yamada.model.SourceSpan.empty);
            end
            document.Diagnostics = diagnostics;
        end

        function [document, diagnostics] = parseText(source, registry, filePath, propertyNames, runningRelease)
            % parseText Parse handle-based source text into the shared document model.
            %   Whole-source parsing is expensive. Avoid calls outside file loading and
            %   saving; editor changes should use maintained indexes and local updates.
            %   Property names may bound semantic validation of an internally proven candidate.
            %   A running release enables source availability diagnostics on file load.
            arguments (Input)
                source string
                registry (1, 1) yamada.model.ComponentRegistry
                filePath string = ""
                propertyNames (1, :) string = strings(1, 0)
                runningRelease (1, 1) string = ""
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                diagnostics yamada.model.Diagnostic
            end

            % Every whole-source parse uses one central, exception-safe UI notification.
            display = yamada.source.SourceParseProgress.find(registry);
            if ~isempty(display) && display.Parent.Visible == "on" && isempty(display.Dialog)
                dialog = uiprogressdlg(display.Parent, "Title", "Loading", ...
                    "Message", "Loading source...", "Indeterminate", "on", "Cancelable", "off");
                progressCleanup = onCleanup(@() display.finish(dialog));
                display.start(dialog);
                drawnow nocallbacks
            end

            % Split source lexically before applying limited structural recognition.
            source = join(reshape(source, 1, []), "");
            statements = yamada.source.MatlabLexicalScanner.splitStatements(source);
            [className, isHandle] = yamada.source.AppSourceParser.findHandleClass( ...
                statements);
            if strlength(className) == 0
                className = "ParsedApp";
            end
            document = yamada.model.DocumentModel(className);
            document.FilePath = filePath;
            document.OriginalText = source;
            document.Encoding = "UTF-8";
            document.LineEnding = yamada.source.AppSourceParser.lineEnding(source);
            document.Metadata.SourceSnapshotId = string(java.util.UUID.randomUUID());
            document.Metadata.SourceSnapshotText = source;
            diagnostics = yamada.model.Diagnostic.empty;
            if ~isHandle
                diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                    "not-handle-class", "error", ...
                    "Source does not declare a class derived from handle.", ...
                    "", yamada.model.SourceSpan.empty);
                document.Diagnostics = diagnostics;
                return
            end

            % Collect declared component types before constructing model records.
            declarations = yamada.source.AppSourceParser.propertyDeclarations(statements);
            availability = [];
            sourceRegistry = registry;
            variantIds = registry.listVariantIds();
            unavailableFactories = strings(1, 0);
            if strlength(registry.CatalogRoot) > 0 || strlength(runningRelease) > 0
                catalogRoot = registry.CatalogRoot;
                if catalogRoot == "", catalogRoot = yamada.catalog.ComponentCatalogLoader.defaultCatalogRoot(); end
                catalogFolder = fileparts(catalogRoot);
                indexPath = fullfile(catalogFolder, "availability.json");
                if isfile(indexPath)
                    availability = jsondecode(fileread(indexPath));
                    unavailable = availability.variants(~ismember(string({availability.variants.id}), variantIds));
                    unavailableFactories = string({unavailable.factory});
                end
            end
            creationOffsets = [];
            for index = 1:numel(statements)
                creation = yamada.source.AppSourceParser.creationMatch(statements(index).Text);
                if isempty(creation), continue, end
                if sourceRegistry == registry && any(unavailableFactories == creation.Factory)
                    sourceRegistry = yamada.catalog.ComponentCatalogLoader.load( ...
                        fullfile(catalogFolder, string(availability.surfaceRelease)));
                end
                if registry.contains(creation.Factory) || sourceRegistry.contains(creation.Factory)
                    creationOffsets(end + 1) = statements(index).Span.StartOffset;
                end
            end
            [initializationOrder, initializationDiagnostics, initializationCertain, initializationLayout, initializationReturns] = ...
                yamada.source.CallbackSourceAnalyzer.initializationStatements(statements, creationOffsets);
            analysis = yamada.source.SourceAnalysis.fromParsed(source, statements, initializationLayout, creationOffsets, ...
                struct("Order", initializationOrder, "Diagnostics", initializationDiagnostics, ...
                "Certain", initializationCertain, "Returns", initializationReturns));
            document.rememberSourceAnalysis(analysis, registry);
            document.Metadata.InitializationContext = struct("Order", initializationOrder, ...
                "Certain", initializationCertain, "Returns", initializationReturns, "Layout", initializationLayout);
            diagnostics = [diagnostics(:)' initializationDiagnostics(:)'];
            unresolved = initializationDiagnostics(string({initializationDiagnostics.Code}) == "unresolved-initialization-call");
            document.Metadata.HasUnresolvedInitialization = false;
            creationOrder = unique(initializationOrder, 'stable');
            creationOrder = [creationOrder setdiff(1:numel(statements), creationOrder, 'stable')];
            % Each component has its own number of settings, so each entry is one cell value.
            creationSettings = dictionary(string([]), {});
            definitions = dictionary(string([]), yamada.model.ComponentDefinition.empty);

            % Recover reachable creations first so parent discovery follows initialization calls.
            for index = creationOrder
                statement = statements(index);
                creation = yamada.source.AppSourceParser.creationMatch(statement.Text);
                if isempty(creation)
                    continue
                end
                if ~registry.contains(creation.Factory) && ~sourceRegistry.contains(creation.Factory)
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "unsupported-factory", "warning", ...
                        "Component factory is not registered and was retained as source.", ...
                        creation.Name, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        yamada.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "unsupported-factory");
                    continue
                end

                % Recover an optional parent and safe name/value factory arguments.
                catalog = registry;
                if sourceRegistry.contains(creation.Factory) && any(unavailableFactories == creation.Factory)
                    catalog = sourceRegistry;
                end
                definition = catalog.get(creation.Factory);
                [parentName, creationArguments, settings, skippedProperties, isSupported] = ...
                    yamada.source.PropertySettingSyntax.factory(statement, definition, document.Metadata.SourceSnapshotId);
                if isSupported
                    concrete = catalog.get(creation.Factory, creationArguments);
                    usingSourceSurface = catalog ~= registry;
                    usingRuntimeVariant = any(variantIds == concrete.Id);
                    if usingRuntimeVariant
                        concrete = registry.getById(concrete.Id);
                    end
                    if concrete.Id ~= definition.Id || (usingSourceSurface && usingRuntimeVariant)
                        % A positional style selects the property surface for subsequent named arguments.
                        [parentName, creationArguments, settings, skippedProperties, isSupported] = ...
                            yamada.source.PropertySettingSyntax.factory(statement, concrete, document.Metadata.SourceSnapshotId);
                    end
                end
                if ~isSupported
                    if ismember(index, initializationOrder), document.Metadata.HasUnresolvedInitialization = true; end
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "nonliteral-creation-argument", "warning", ...
                        "Component creation has an unsupported argument and was retained as source.", ...
                        creation.Name, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        yamada.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "nonliteral-creation-argument");
                    continue
                end
                definition = concrete;
                for settingIndex = 1:numel(settings)
                    settings(settingIndex) = registry.protectSourceSetting(definition.Id, settings(settingIndex));
                    if settings(settingIndex).IsReleaseUnavailable && ~any(skippedProperties == settings(settingIndex).Path)
                        skippedProperties(end + 1) = settings(settingIndex).Path;
                    end
                end

                % Resolve declaration metadata and parent identity before mutation.
                declaredType = definition.DeclaredType;
                declarationSpan = yamada.model.SourceSpan.empty;
                if isKey(declarations, creation.Name)
                    declaration = declarations(creation.Name);
                    declaredType = declaration.DeclaredType;
                    declarationSpan = declaration.Span;
                else
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "missing-component-declaration", "warning", ...
                        "Component creation has no matching property declaration.", ...
                        creation.Name, statement.Span);
                end
                parentId = "";
                unavailableRelease = "";
                if ~any(variantIds == definition.Id)
                    entry = unavailable(string({unavailable.id}) == definition.Id);
                    if ~isempty(entry) && isfield(entry.releases, "since")
                        unavailableRelease = string(entry.releases.since);
                    end
                end
                if strlength(parentName) > 0
                    parent = document.getComponentByName(parentName);
                    if isempty(parent)
                        if ismember(index, initializationOrder), document.Metadata.HasUnresolvedInitialization = true; end
                        diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                            "missing-parent", "warning", ...
                            "Component parent is not available from supported prior source.", ...
                            creation.Name, statement.Span);
                        document.UnknownRegions(end + 1) = ...
                            yamada.model.UnknownSourceRegion( ...
                            statement.Text, statement.Span, "missing-parent");
                        continue
                    end
                    parentId = parent.Id;
                    if unavailableRelease == "" && parent.isReleaseUnavailable()
                        unavailableRelease = parent.Metadata.UnavailableRelease;
                    end
                end

                if creation.Factory == "colorbar" && ...
                        (parentId == "" || ~yamada.model.SubtreePlacementPlanner.accepts(document,parent,definition))
                    document.Metadata.HasUnresolvedInitialization = true;
                    diagnostics(end+1) = yamada.source.AppSourceParser.diagnostic( ...
                        "unresolved-colorbar-target","warning","ColorBar has no unique supported axes target.", ...
                        creation.Name,statement.Span);
                    document.UnknownRegions(end+1) = yamada.model.UnknownSourceRegion( ...
                        statement.Text,statement.Span,"unresolved-colorbar-target");
                    continue
                end

                % Create an editable record only after all ownership is understood.
                component = yamada.model.ComponentRecord( ...
                    "parsed-" + creation.Name, creation.Name, creation.Factory, ...
                    declaredType, "parsed");
                component.CreationArguments = creationArguments;
                if unavailableRelease ~= ""
                    component.IsEditable = false;
                    component.Metadata.UnavailableRelease = unavailableRelease;
                    component.Metadata.SourceDisplayName = definition.DisplayName;
                    component.Metadata.SourceVariantId = definition.Id;
                    component.Metadata.SourceCatalogRelease = string(availability.surfaceRelease);
                    component.Metadata.SourceAllowedParents = definition.AllowedParentFactories;
                    callbacks = arrayfun(@(property) isfield(property.ValueSchema, "kind") && ...
                        string(property.ValueSchema.kind) == "callback", definition.Properties);
                    component.Metadata.SourceCallbackPaths = string({definition.Properties(callbacks).Path});
                end
                creationSettings{component.Id} = settings;
                definitions(component.Id) = definition;
                component.SourceSpans = struct( ...
                    "Declaration", declarationSpan, "Creation", statement.Span);
                try
                    document.addComponent(component, parentId);
                    for propertyIndex = 1:numel(skippedProperties)
                        if registry.isUnavailableSourceProperty(definition.Id, skippedProperties(propertyIndex)), continue, end
                        diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                            "source-creation-property", "warning", ...
                            "Creation property was retained as source and omitted from Safe Preview.", ...
                            component.Id, statement.Span);
                    end
                catch exception
                    if ismember(index, initializationOrder), document.Metadata.HasUnresolvedInitialization = true; end
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "invalid-component-creation", "warning", exception.message, ...
                        creation.Name, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        yamada.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "invalid-component-creation");
                end
            end

            % Recover initial writes in execution order, rather than file declaration order.
            created = strings(1, 0);
            currentAxes = "";
            blockedCallNames = string({initializationLayout.Methods.Name});
            unresolvedOffsets = arrayfun(@(item) item.SourceSpan.StartOffset, unresolved);
            reviewedAxesOffsets = [];
            document.Metadata.HasAxesSettingCalls = false;
            document.Metadata.HasImplicitAxesCalls = false;
            sequence = 0;
            for visit = 1:numel(initializationOrder)
                index = initializationOrder(visit);
                % Runtime callback writes never determine editable initial values or source spans.
                statement = statements(index);
                creation = yamada.source.AppSourceParser.creationMatch(statement.Text);
                if ~isempty(creation)
                    component = document.getComponentByName(creation.Name);
                    if ~isempty(component)
                        sequence = sequence + 1;
                        component.Metadata.InitializationCreationSequence = sequence;
                        component.Metadata.InitializationCreationCertain = initializationCertain(visit) && ...
                            nnz(initializationOrder == index) == 1;
                        created(end + 1) = component.Id;
                        if any(component.Factory == ["axes","uiaxes","polaraxes","geoaxes"])
                            currentAxes = "";
                            if component.Metadata.InitializationCreationCertain, currentAxes = component.Name; end
                        elseif component.Factory == "uifigure"
                            currentAxes = "";
                        end
                        for setting = creationSettings{component.Id}
                            sequence = sequence + 1;
                            record = setting.toStruct();
                            record.Location.Sequence = sequence;
                            record.Location.IsCertain = setting.IsCertain && initializationCertain(visit) && ...
                                nnz(initializationOrder == index) == 1;
                            record.Location.IsEditable = record.Location.IsEditable && component.IsEditable;
                            captured = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                            component.recordSetting(yamada.source.AppSourceParser.scopedSetting(captured, initializationLayout, index));
                        end
                    end
                end
                assignment = yamada.source.AppSourceParser.assignmentMatch(statement.Text);
                if ~isempty(assignment) && (assignment.Path == "CurrentAxes" || ...
                        any(unresolvedOffsets == statement.Span.StartOffset))
                    % An unmodeled selection or call invalidates the implicit target.
                    currentAxes = "";
                end
                if isempty(assignment)
                    % Capture reviewed call effects without executing source or granting write ownership.
                    if contains(statement.Text,"(")
                        [name, target, tokens, valueSpans, forms] = yamada.source.PropertySettingSyntax.axesCall(statement, registry.CatalogRoot);
                        if name == "axes" && ~any(blockedCallNames == name) && ...
                                strlength(target) > 0 && isempty(tokens)
                            selected = document.getComponentByName(target);
                            currentAxes = "";
                            if ~isempty(selected) && any(created == selected.Id) && ...
                                    any(selected.Factory == ["axes","uiaxes","polaraxes","geoaxes"]) && ...
                                    initializationCertain(visit) && nnz(initializationOrder == index) == 1
                                currentAxes = target;
                                reviewedAxesOffsets(end + 1) = statement.Span.StartOffset;
                            end
                            continue
                        end
                        implicit = strlength(target) == 0;
                        if implicit && ~isempty(tokens)
                            document.Metadata.HasImplicitAxesCalls = true;
                            target = currentAxes;
                        end
                        if implicit && ~isempty(tokens) && ...
                                (strlength(target) == 0 || ~initializationCertain(visit))
                            diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                                "unresolved-axes-target", "warning", ...
                                "No unique axes target can be inferred for this setting.", "", statement.Span);
                        end
                        targetComponent = document.getComponentByName(target);
                        if ~isempty(tokens) && ~isempty(targetComponent) && any(created == targetComponent.Id) && ...
                                ~any(blockedCallNames == name) && initializationCertain(visit) && nnz(initializationOrder == index) == 1
                            [paths, values, argumentsUsed, owned, elements] = yamada.catalog.AxesSettingFunctionCatalog.match( ...
                                forms, targetComponent.Factory, tokens, implicit);
                            if ~isempty(paths)
                                if implicit
                                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                                        "implicit-axes-target", "warning", ...
                                        "Axes setting uses an implicit target inferred as " + target + ".", ...
                                        targetComponent.Id, statement.Span);
                                end
                                document.Metadata.HasAxesSettingCalls = true;
                                % Explicit targets own their replaceable value tokens; implied effects own none.
                                [ownedSpans, editable] = yamada.source.AxesSettingPlacement.ownership( ...
                                    targetComponent.Factory, paths, owned, argumentsUsed, tokens, valueSpans, elements);
                                editable = editable & ~implicit;
                                for effect = 1:numel(paths)
                                    sequence = sequence + 1;
                                    location = struct("Method", "functionCall", "Syntax", "call", ...
                                        "SourceSpan", statement.Span, "ValueSpan", ownedSpans{effect}, ...
                                        "SourceSnapshotId", document.Metadata.SourceSnapshotId, ...
                                        "Sequence", sequence, "IsEditable", editable(effect));
                                    setting = yamada.model.PropertySetting(paths(effect), values{effect}, location);
                                    targetComponent.recordSetting(yamada.source.AppSourceParser.scopedSetting(setting, initializationLayout, index));
                                end
                                reviewedAxesOffsets(end + 1) = statement.Span.StartOffset;
                                continue
                            end
                        end
                    end
                    if any(unresolvedOffsets == statement.Span.StartOffset)
                        currentAxes = "";
                    end
                    continue
                end
                component = document.getComponentByName(assignment.ComponentName);
                if isempty(component)
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "unknown-assignment-component", "warning", ...
                        "Property assignment has no supported component record.", ...
                        assignment.ComponentName, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        yamada.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "unknown-assignment-component");
                    continue
                end

                % Preserve initialization writes that execute before supported creation.
                if ~any(created == component.Id)
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "assignment-before-creation", "warning", ...
                        "Property assignment precedes supported component creation and was retained as source.", ...
                        component.Id, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        yamada.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "assignment-before-creation");
                    continue
                end

                % Preserve assignments outside the direct-parent surface as read-only source.
                parentFactory = "";
                if strlength(component.ParentId) > 0
                    parent = document.getComponent(component.ParentId);
                    if ~isempty(parent), parentFactory = parent.Factory; end
                end
                variant = definitions(component.Id);
                effectiveProperties = yamada.model.PropertyDefinition.empty;
                if ~component.isReleaseUnavailable()
                    effectiveProperties = registry.getEffectiveProperties(component.Factory, parentFactory, ...
                        component.CreationArguments);
                end
                sequence = sequence + 1;
                setting = yamada.source.PropertySettingSyntax.assignment(statement, ...
                    document.Metadata.SourceSnapshotId, sequence, initializationCertain(visit));
                setting = registry.protectSourceSetting(variant.Id, setting);
                setting = yamada.source.AppSourceParser.scopedSetting(setting, initializationLayout, index);
                if component.isReleaseUnavailable()
                    record = setting.toStruct();
                    record.Location.IsEditable = false;
                    component.recordSetting(yamada.model.PropertySetting(record.Path, record.Value, record.Location));
                    continue
                end
                if setting.IsReleaseUnavailable && any(string({effectiveProperties.Path}) == assignment.Path)
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "source-release-value", "warning", ...
                        "This property's value is unavailable in the loaded MATLAB catalog and was retained as source.", ...
                        component.Id, statement.Span);
                end
                if ~any(string({effectiveProperties.Path}) == assignment.Path)
                    record = setting.toStruct();
                    record.Location.IsEditable = false;
                    component.recordSetting(yamada.model.PropertySetting(record.Path, record.Value, record.Location));
                    if ~setting.IsReleaseUnavailable && ~yamada.source.AppSourceParser.isNotRenderedFigureTool(component.Factory)
                        diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                            "context-inapplicable-property", "warning", ...
                            "Property assignment is preserved read-only outside its direct-parent context.", ...
                            component.Id, statement.Span);
                    end
                    continue
                end
                % Preserve every occurrence; conditional writes remain uncertain projections.
                component.recordSetting(setting);
                if ~setting.IsCertain
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "conflicting-property-assignment", "warning", ...
                        "Initialization ownership is conditional or repeated; the setting remains read-only.", ...
                        component.Id, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        yamada.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "conflicting-property-assignment");
                end
                % Known deferred registrations retain source ownership without generic expression warnings.
                infrastructure = setting.ValueKind == "expression" && setting.IsCertain && ...
                    component.Factory == "uifigure" && assignment.Path == "CloseRequestFcn" && ...
                    yamada.source.CallbackSourceEdits.isDefaultClose(setting.SourceExpression);
                property = effectiveProperties(string({effectiveProperties.Path}) == assignment.Path);
                schema = property.ValueSchema;
                callbackBinding = setting.ValueKind == "expression" && setting.IsCertain && ...
                    isfield(schema, "kind") && string(schema.kind) == "callback" && ...
                    strlength(yamada.source.CallbackSourceAnalyzer.bindingHandler(setting.SourceExpression)) > 0;
                if setting.ValueKind == "expression" && ~infrastructure && ~callbackBinding
                    diagnostics(end + 1) = yamada.source.AppSourceParser.diagnostic( ...
                        "source-expression", "warning", ...
                        "Property expression was retained as read-only source text.", ...
                        component.Id, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        yamada.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "source-expression");
                end
            end

            % Reviewed calls have a finite setting contract; preserve diagnostics for all other calls.
            reviewed = arrayfun(@(item) item.Code == "unresolved-initialization-call" && ...
                any(reviewedAxesOffsets == item.SourceSpan.StartOffset), diagnostics);
            diagnostics(reviewed) = [];
            document.Metadata.HasUnresolvedInitialization = document.Metadata.HasUnresolvedInitialization || any( ...
                ~ismember(unresolvedOffsets, reviewedAxesOffsets));
            yamada.model.SourceEffectSummary.refresh(document, registry);

            % Keep the Open-time range warning available to later model validation.
            if ~isempty(availability) && strlength(runningRelease) > 0
                releaseDiagnostic = yamada.source.AppSourceParser.releaseDiagnostic( ...
                    statements, initializationOrder, sourceRegistry, registry, availability, runningRelease);
                if ~isempty(releaseDiagnostic), document.Metadata.SourceReleaseDiagnostic = releaseDiagnostic; end
            end
            validationDiagnostics = yamada.validation.ModelValidator.validate( ...
                document, registry, propertyNames);
            range = string({validationDiagnostics.Code}) == "source-release-range";
            diagnostics = [validationDiagnostics(range) diagnostics(:)' validationDiagnostics(~range)];
            document.Diagnostics = diagnostics;
            document.markSaved();
            document.finishParsedSource(registry, validationDiagnostics, isempty(propertyNames));
        end
    end

    methods (Static, Access = private)
        function diagnostic = releaseDiagnostic(statements, order, sourceRegistry, registry, availability, runningRelease)
            % releaseDiagnostic Intersect catalog availability of recognizable initialization syntax.
            arguments (Input)
                statements yamada.source.SourceStatement
                order double
                sourceRegistry (1, 1) yamada.model.ComponentRegistry
                registry (1, 1) yamada.model.ComponentRegistry
                availability (1, 1) struct
                runningRelease (1, 1) string
            end
            arguments (Output)
                diagnostic yamada.model.Diagnostic
            end

            % Recover source variant identities and explicit paths even if the runtime cannot use them.
            variants = dictionary(string([]), string([]));
            usedVariants = strings(1, 0);
            usedProperties = strings(1, 0);
            for index = reshape(unique(order, "stable"), 1, [])
                statement = statements(index);
                creation = yamada.source.AppSourceParser.creationMatch(statement.Text);
                if ~isempty(creation)
                    catalog = sourceRegistry;
                    if ~catalog.contains(creation.Factory), catalog = registry; end
                    if ~catalog.contains(creation.Factory), continue, end
                    definition = catalog.get(creation.Factory);
                    [~, args, settings, ~, supported] = ...
                        yamada.source.PropertySettingSyntax.factory(statement, definition, "");
                    if supported
                        definition = catalog.get(creation.Factory, args);
                    elseif ~isempty(definition.SupportedStyles)
                        continue
                    end
                    variants(creation.Name) = definition.Id;
                    usedVariants(end + 1) = definition.Id;
                    usedProperties = [usedProperties definition.Id + "." + string({settings.Path})];
                    continue
                end
                assignment = yamada.source.AppSourceParser.assignmentMatch(statement.Text);
                if ~isempty(assignment) && isKey(variants, assignment.ComponentName)
                    usedProperties(end + 1) = variants(assignment.ComponentName) + "." + assignment.Path;
                end
            end

            % Derive inclusive lower and exclusive upper bounds from matched entries.
            minimum = "";
            before = "";
            for entry = reshape(availability.variants, 1, [])
                if any(usedVariants == string(entry.id))
                    [minimum, before] = yamada.source.AppSourceParser.intersectReleases(minimum, before, entry.releases);
                end
            end
            for entry = reshape(availability.properties, 1, [])
                if any(usedProperties == string(entry.variantId) + "." + string(entry.path))
                    [minimum, before] = yamada.source.AppSourceParser.intersectReleases(minimum, before, entry.releases);
                end
            end

            % Keep compatible and unbounded releases quiet. Conflicting evidence gets its own warning.
            diagnostic = yamada.model.Diagnostic.empty(1, 0);
            if minimum ~= "" && before ~= "" && minimum >= before
                message = "The component and property usage has no common MATLAB release in the catalog.";
            elseif (minimum ~= "" && runningRelease < minimum) || (before ~= "" && runningRelease >= before)
                lower = "no known minimum";
                upper = "no known maximum";
                if minimum ~= "", lower = minimum; end
                if before ~= ""
                    releases = sort(string({availability.releases.release}));
                    earlier = releases(releases < before);
                    upper = "earlier than " + before;
                    if ~isempty(earlier), upper = earlier(end); end
                end
                message = "Running MATLAB " + runningRelease + ...
                    " is outside the range indicated by this app's components and properties (" + lower + ...
                    " through " + upper + ").";
            else
                return
            end
            diagnostic = yamada.source.AppSourceParser.diagnostic("source-release-range", "warning", ...
                message, "", yamada.model.SourceSpan.empty);
        end

        function [minimum, before] = intersectReleases(minimum, before, bounds)
            % intersectReleases Narrow accumulated bounds using one availability record.
            arguments (Input)
                minimum (1, 1) string
                before (1, 1) string
                bounds (1, 1) struct
            end
            arguments (Output)
                minimum (1, 1) string
                before (1, 1) string
            end

            if isfield(bounds, "since") && string(bounds.since) > minimum
                minimum = string(bounds.since);
            end
            if isfield(bounds, "before") && (before == "" || string(bounds.before) < before)
                before = string(bounds.before);
            end
        end

        function setting = scopedSetting(setting, layout, index)
            % scopedSetting Attach a proven original initializer method to one occurrence.
            arguments (Input)
                setting (1, 1) yamada.model.PropertySetting
                layout (1, 1) struct
                index (1, 1) double
            end
            arguments (Output)
                setting (1, 1) yamada.model.PropertySetting
            end
            owner = layout.Owner(index);
            span = yamada.model.SourceSpan.empty;
            match = find(string({layout.Methods.Name}) == owner);
            if isscalar(match), span = layout.Methods(match).Span; end
            setting = setting.withScope(owner, span);
        end

        function result = isNotRenderedFigureTool(factory)
            % isNotRenderedFigureTool Identify retained Figure Tools outside Safe Preview scope.
            arguments (Input)
                factory (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = any(factory == ["uicontextmenu", "uimenu", "uitoolbar", ...
                "uipushtool", "uitoggletool"]);
        end

        function [bytes, diagnostic] = readBytes(filePath)
            % readBytes Read a file in binary mode without source execution.
            arguments (Input)
                filePath string
            end
            arguments (Output)
                bytes uint8
                diagnostic yamada.model.Diagnostic
            end

            % Return a structured error only when the input file cannot be read.
            bytes = uint8.empty;
            diagnostic = yamada.model.Diagnostic.empty;
            [fileId, message] = fopen(filePath, "rb");
            if fileId < 0
                diagnostic = yamada.source.AppSourceParser.diagnostic( ...
                    "read-failed", "error", string(message), "", ...
                    yamada.model.SourceSpan.empty);
                return
            end
            cleanup = onCleanup(@() fclose(fileId));
            bytes = fread(fileId, Inf, "*uint8")';
            clear cleanup
        end

        function result = isValidUtf8(bytes)
            % isValidUtf8 Return true when bytes round-trip through UTF-8 unchanged.
            arguments (Input)
                bytes uint8
            end
            arguments (Output)
                result (1, 1) logical
            end

            % Reject input that decoding would replace with a different byte sequence.
            decoded = native2unicode(bytes, "UTF-8");
            encoded = unicode2native(decoded, "UTF-8");
            result = isequal(bytes, encoded);
        end

        function [className, isHandle] = findHandleClass(statements)
            % findHandleClass Locate a supported handle-based class declaration.
            arguments (Input)
                statements yamada.source.SourceStatement
            end
            arguments (Output)
                className string
                isHandle logical
            end

            % Match only one declaration form and leave all others unsupported.
            className = "";
            isHandle = false;
            pattern = '^classdef\s+(?<name>[A-Za-z]\w*)\s*<\s*handle\s*$';
            for index = 1:numel(statements)
                tokens = regexp(char(statements(index).Text), pattern, "names", "once");
                if ~isempty(tokens)
                    className = string(tokens.name);
                    isHandle = true;
                    return
                end
            end
        end

        function declarations = propertyDeclarations(statements)
            % propertyDeclarations Collect declared types from property blocks.
            arguments (Input)
                statements yamada.source.SourceStatement
            end
            arguments (Output)
                declarations dictionary
            end

            % Track only direct property block lines, never function-local values.
            declarations = dictionary(string([]), struct("DeclaredType", {}, "Span", {}));
            inProperties = false;
            pattern = '^(?<name>[A-Za-z]\w*)\s+(?<type>[A-Za-z]\w*(?:\.[A-Za-z]\w*)*)\s*$';
            for index = 1:numel(statements)
                statement = statements(index);
                text = statement.Text;
                if startsWith(text, "properties")
                    inProperties = true;
                    continue
                end
                if inProperties && text == "end"
                    inProperties = false;
                    continue
                end
                if ~inProperties
                    continue
                end
                tokens = regexp(char(text), pattern, "names", "once");
                if isempty(tokens)
                    continue
                end
                declarations(string(tokens.name)) = struct( ...
                    "DeclaredType", string(tokens.type), "Span", statement.Span);
            end
        end

        function creation = creationMatch(text)
            % creationMatch Match one direct app component factory assignment.
            arguments (Input)
                text string
            end
            arguments (Output)
                creation
            end

            % Require a complete direct assignment to avoid partial source claims.
            creation = [];
            pattern = ['^app\.(?<name>[A-Za-z]\w*)\s*=\s*' ...
                '(?<factory>[A-Za-z]\w*)\s*\((?<arguments>[\s\S]*)\)$'];
            tokens = regexp(char(text), pattern, "names", "once");
            if ~isempty(tokens)
                creation = struct( ...
                    "Name", string(tokens.name), ...
                    "Factory", string(tokens.factory), ...
                    "Arguments", string(tokens.arguments));
            end
        end

        function assignment = assignmentMatch(text)
            % assignmentMatch Match one direct app component property assignment.
            arguments (Input)
                text string
            end
            arguments (Output)
                assignment
            end

            % Restrict matches to direct paths so callbacks and arbitrary code stay opaque.
            assignment = [];
            pattern = ['^app\.(?<component>[A-Za-z]\w*)\.' ...
                '(?<path>[A-Za-z]\w*(?:\.[A-Za-z]\w*)*)\s*=\s*' ...
                '(?<value>[\s\S]+)$'];
            tokens = regexp(char(text), pattern, "names", "once");
            if ~isempty(tokens)
                assignment = struct( ...
                    "ComponentName", string(tokens.component), ...
                    "Path", string(tokens.path), ...
                    "ValueText", string(strtrim(tokens.value)));
            end
        end

        function result = lineEnding(source)
            % lineEnding Identify the source line-ending convention without rewrite.
            arguments (Input)
                source string
            end
            arguments (Output)
                result string
            end

            % Record the observed convention for later no-edit round-trip work.
            if contains(source, sprintf("\r\n"))
                result = "CRLF";
            elseif contains(source, newline)
                result = "LF";
            else
                result = "None";
            end
        end

        function result = diagnostic(code, severity, message, componentId, span)
            % diagnostic Create one parser diagnostic with optional source context.
            arguments (Input)
                code string
                severity string
                message string
                componentId string
                span yamada.model.SourceSpan
            end
            arguments (Output)
                result (1, 1) yamada.model.Diagnostic
            end

            result = yamada.model.Diagnostic( ...
                code, severity, message, componentId, span);
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
