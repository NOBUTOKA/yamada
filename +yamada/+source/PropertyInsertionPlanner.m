classdef PropertyInsertionPlanner
    % PropertyInsertionPlanner Place new settings inside proven initialization intervals.
    %   The planner keeps existing settings fixed, preserves factory tokens, and
    %   validates owned candidate text without executing it. Opaque statements
    %   bound an interval rather than becoming an excuse to append at EOF.

    methods (Static)
        function result = needsPlan(document, component)
            % needsPlan Identify source additions owned by this planner rather than relocation.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = yamada.model.SourceOwnership.hasSource(component) && ...
                any(arrayfun(@(entry) isempty(entry.SourceSpan) && ...
                entry.ValueKind == "literal" && ~isfield(entry.Metadata, "SubtreeReferenceId"), component.Properties)) && ...
                isscalar(document.CurrentText) && strlength(document.CurrentText) > 0;
            if ~result, return, end
            for pending = document.PendingEdits
                edit = pending{1};
                if isstruct(edit) && isfield(edit, "Kind") && edit.Kind == "reparent-subtree" && ...
                        any(string({edit.OriginalRecords.Id}) == component.Id)
                    result = false;
                    return
                end
            end
        end

        function plan = plan(document, component, registry)
            % plan Return insertions and an independently reparsed candidate component.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                plan (1, 1) struct
            end
            if ~yamada.source.PropertyInsertionPlanner.needsPlan(document, component)
                plan = yamada.source.PropertySourcePlan.combined(document, component, registry);
                return
            end
            context = document.evaluationContext(registry);
            scope = context.readScope(); %#ok<NASGU>
            [plan, found] = yamada.source.PropertyInsertionPlanner.sharedBatch(document, component, registry, context);
            if found, return, end
            key = "insertion:" + component.Id;
            [data, found] = context.lookup(key);
            if found
                [plan, found] = context.configuration(key, document.sourceComponentName(component.Id));
                if found
                    plan.Edits = data.Edits;
                    plan.Placements = data.Placements;
                    return
                end
            end
            plan = yamada.source.PropertyInsertionPlanner.evaluate(document, component, registry);
            if ~isempty(plan.Document)
                context.rememberConfiguration(key, plan.Document);
                context.remember(key, rmfield(plan, ["Document", "Component"]));
            end
        end
    end

    methods (Static, Access = ?yamada.model.SourceLiteralTransaction)
        function plan = tentative(document, component, registry)
            % tentative Prepare owned insertion edits for mandatory transaction-level local validation.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                plan (1, 1) struct
            end
            plan = yamada.source.PropertyInsertionPlanner.evaluate(document, component, registry, true);
        end
    end

    methods (Static, Access = ?yamada.source.RoundTripGenerator)
        function edits = generationEdits(document, component, registry)
            % generationEdits Read validated insertion values without materializing public document copies.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                edits struct
            end
            context = document.evaluationContext(registry);
            scope = context.readScope(); %#ok<NASGU>
            % Only successful placement proofs publish these value-only records.
            [plans, found] = context.lookup("insertion-batch");
            if found
                match = find(string({plans.ComponentId}) == component.Id, 1);
                if ~isempty(match)
                    edits = plans(match).Edits;
                    return
                end
            end
            [data, found] = context.lookup("insertion:" + component.Id);
            if found
                edits = data.Edits;
                return
            end
            % Unproven owners retain the public planner's search, validation and diagnostics.
            plan = yamada.source.PropertyInsertionPlanner.plan(document, component, registry);
            edits = plan.Edits;
        end
    end

    methods (Static, Access = private)
        function [plan, found] = sharedBatch(document, component, registry, context)
            % sharedBatch Retain one private candidate while returning independently owned public plans.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
                context (1, 1) yamada.model.EvaluationContext
            end
            arguments (Output)
                plan (1, 1) struct
                found (1, 1) logical
            end
            plan = struct();
            found = false;
            key = "insertion-batch";
            [plans, cached] = context.lookup(key);
            if cached
                match = find(string({plans.ComponentId}) == component.Id, 1);
                if ~isempty(match)
                    [plan, found] = context.configuration(key, document.sourceComponentName(component.Id));
                    if found
                        plan.Edits = plans(match).Edits;
                        plan.Placements = plans(match).Placements;
                        return
                    end
                end
            end
            [~, attempted] = context.lookup(key + ":attempted");
            if attempted, return, end
            context.remember(key + ":attempted", true);
            % Failed aggregation retains the established per-owner search and diagnostics.
            try
                [plans, parsed] = yamada.source.PropertyInsertionPlanner.batch(document, registry);
            catch
                return
            end
            if isempty(parsed), return, end
            context.rememberConfiguration(key, parsed);
            context.remember(key, plans);
            match = find(string({plans.ComponentId}) == component.Id, 1);
            if isempty(match), return, end
            configured = parsed.getComponentByName(document.sourceComponentName(component.Id));
            plan = struct("Document", parsed, "Component", configured, ...
                "Edits", plans(match).Edits, "Placements", plans(match).Placements);
            found = ~isempty(configured);
        end

        function [plans, parsed] = batch(document, registry)
            % batch Combine owned insertions and validate pending literals against one indexed candidate.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                plans struct
                parsed yamada.model.DocumentModel
            end
            plans = struct("ComponentId", {}, "Edits", {}, "Placements", {});
            parsed = yamada.model.DocumentModel.empty;
            % Relocation, deletion, callback, and rename edits retain their established proof paths.
            origins = string({document.Components.Origin});
            if ~isempty(document.PendingEdits) || ~isempty(document.CallbackEdits) || ...
                    ~isempty(document.RenameEdits) || any(~ismember(origins, ["parsed", "generated"]))
                return
            end
            owners = document.Components(arrayfun(@(record) ...
                yamada.source.PropertyInsertionPlanner.needsPlan(document, record), document.Components));
            if numel(owners) < 2, return, end
            edits = yamada.source.PropertyInsertionPlanner.replacements(document);
            for owner = reshape(owners, 1, [])
                tentative = yamada.source.PropertyInsertionPlanner.evaluate(document, owner, registry, true);
                plans(end + 1) = struct("ComponentId", owner.Id, ...
                    "Edits", tentative.Edits, "Placements", tentative.Placements); %#ok<AGROW>
                edits = [edits tentative.Edits]; %#ok<AGROW>
            end
            completeSource = any(origins == "generated");
            if completeSource
                % Include generated components before checking placement and all final values once.
                detached = document.structuralCandidate();
                detached.Metadata.ResolvingCombinedPropertySource = true;
                [source, diagnostics, edits] = yamada.source.RoundTripGenerator(registry).generatePreparedInsertions(detached, plans);
                if strlength(source) == 0 || yamada.validation.ModelValidator.hasErrors(diagnostics), return, end
                source = document.CurrentText;
            else
                source = document.CurrentText;
            end
            [accepted, candidate] = yamada.source.PropertyInsertionPlanner.candidate( ...
                source, edits, document.sourceComponentName(owners(1).Id), ...
                yamada.model.PropertyEntry.empty, registry, false, document);
            if ~accepted, return, end
            % Final values of other unsaved requests must survive the same intermediate-state checks.
            for original = reshape(document.Components, 1, [])
                requested = yamada.source.PropertyInsertionPlanner.batchRequests(original);
                if isempty(requested), continue, end
                configured = candidate.getComponentByName(document.sourceComponentName(original.Id));
                if isempty(configured), return, end
                states = candidate.getEffectivePropertyStates(registry, configured.Id);
                for entry = reshape(requested, 1, [])
                    match = find(arrayfun(@(state) state.Definition.Path == entry.Path, states), 1);
                    if isempty(match) || ~yamada.model.PropertyStateResolver.matchesRequested( ...
                            states(match).Resolution, entry.LiteralValue)
                        return
                    end
                end
            end
            parsed = candidate;
            if completeSource
                % This proof includes every actual generated statement, rather than a partial owner view.
                context = document.evaluationContext(registry);
                context.rememberConfiguration("combined", parsed);
                context.remember("complete-insertion-source", candidate.CurrentText);
            end
        end

        function entries = batchRequests(component)
            % batchRequests Include new literals and changed source-owned values in the shared proof.
            arguments (Input)
                component (1, 1) yamada.model.ComponentRecord
            end
            arguments (Output)
                entries yamada.model.PropertyEntry
            end
            entries = yamada.model.PropertyEntry.empty;
            for entry = reshape(component.Properties, 1, [])
                if entry.ValueKind ~= "literal" || isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                if isempty(entry.SourceSpan)
                    entries(end + 1) = entry; %#ok<AGROW>
                elseif isfield(entry.Metadata, "SourceSettingId")
                    settings = component.getSettings(entry.Path);
                    original = settings(string({settings.Id}) == string(entry.Metadata.SourceSettingId));
                    if ~isempty(original) && ~isequaln(original(end).LiteralValue, entry.LiteralValue)
                        entries(end + 1) = entry; %#ok<AGROW>
                    end
                end
            end
        end

        function plan = evaluate(document, component, registry, deferValidation)
            % evaluate Prepare owned syntax while optionally deferring candidate checks to a batch.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
                deferValidation (1, 1) logical = false
            end
            arguments (Output)
                plan (1, 1) struct
            end
            plan = struct("Edits", struct("Start", {}, "End", {}, "Text", {}), ...
                "Placements", struct("Path", {}, "Method", {}, "Offset", {}, "OwnerMethod", {}), ...
                "Document", yamada.model.DocumentModel.empty, "Component", yamada.model.ComponentRecord.empty);
            entries = component.Properties([component.Properties.Origin] == "generated");
            entries = entries(arrayfun(@(entry) isempty(entry.SourceSpan) && entry.ValueKind == "literal" && ...
                ~isfield(entry.Metadata, "SubtreeReferenceId"), entries));
            if isempty(entries), return, end
            source = document.CurrentText;
            if isfield(document.Metadata, "SourceSnapshotText") && document.Metadata.SourceSnapshotText ~= source
                error("yamada:PropertyInsertionPlanner:UnsafePlacement", "The source baseline changed without reparsing.");
            end
            if ~component.IsEditable || isempty(component.SourceSpans.Creation) || ~component.SourceSpans.Creation.isKnown()
                error("yamada:PropertyInsertionPlanner:UnsafePlacement", "New settings require a proven component creation.");
            end
            parent = document.getComponent(component.ParentId);
            parentFactory = "";
            if ~isempty(parent), parentFactory = parent.Factory; end
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
            entries = entries(ismember(string({entries.Path}), string({definitions([definitions.IsEditable]).Path})));
            if isempty(entries), return, end
            entries = yamada.model.PropertyApplicationPlanner.order(entries, definitions);
            sourceSettings = component.Settings(string({component.Settings.Method}) ~= "generated");
            if any(ismember(string({entries.Path}), string({sourceSettings.Path})))
                error("yamada:PropertyInsertionPlanner:UnsafePlacement", "A new setting would duplicate an existing source occurrence.");
            end

            % Acquire the same constructor-reachable trace used by the parser.
            analysis = document.sourceAnalysis();
            statements = analysis.Statements;
            creation = find(arrayfun(@(statement) statement.Span.StartOffset == ...
                component.SourceSpans.Creation.StartOffset, statements));
            if ~isscalar(creation)
                error("yamada:PropertyInsertionPlanner:UnsafePlacement", "The factory statement is not uniquely owned.");
            end
            parsed = document.Components(arrayfun(@yamada.model.SourceOwnership.hasSource, document.Components));
            offsets = arrayfun(@(record) record.SourceSpans.Creation.StartOffset, parsed);
            initialization = analysis.initialization(offsets);
            order = initialization.Order;
            certain = initialization.Certain;
            layout = analysis.Layout;
            returns = initialization.Returns;
            created = find(order == creation);
            if ~isscalar(created) || ~certain(created) || ~layout.Valid
                error("yamada:PropertyInsertionPlanner:UnsafePlacement", "The factory is conditional, repeated, or outside a proven initializer.");
            end
            [selectionSettings, selectionCreations] = yamada.model.ButtonSelectionPolicy.insertionSurface(component, document);
            [anchors, boundary] = yamada.source.PropertyInsertionPlanner.anchors(statements, order, certain, returns, layout, created, ...
                [sourceSettings selectionSettings], selectionCreations, analysis.Facts);
            paths = string({definitions.Path});
            if any(~ismember(string({entries.Path}), paths))
                error("yamada:PropertyInsertionPlanner:UnsafePlacement", "A new property is not supported in this parent context.");
            end
            reaches = yamada.source.PropertyInsertionPlanner.dependencies(definitions);
            base = yamada.source.PropertyInsertionPlanner.replacements(document);
            constructor = sourceSettings(string({sourceSettings.Method}) == "nameValue");
            nvOnly = ~isempty(constructor) && numel(constructor) == numel(sourceSettings) && ...
                all([constructor.IsCertain]) && isscalar(unique(string({constructor.Syntax}))) && ...
                ~any(string({constructor.Path}) == "CreateFcn");
            nv = false(1, numel(entries));
            for index = 1:numel(entries)
                definition = definitions(paths == entries(index).Path);
                nv(index) = nvOnly && ~isempty(definition) && definition.IsEditable && ...
                    definition.AuditDisposition == "editable" && ...
                    ~contains(entries(index).Path, ".");
            end
            for index = 1:numel(entries)
                dependencies = reaches(:, paths == entries(index).Path);
                for earlier = 1:index - 1
                    if dependencies(paths == entries(earlier).Path) && ~nv(earlier), nv(index) = false; end
                end
            end
            name = document.sourceComponentName(component.Id);
            requested = yamada.model.PropertyEntry.empty;
            for index = 1:numel(entries)
                entry = entries(index);
                requested(end + 1) = entry; %#ok<AGROW>
                accepted = false;
                failure = "No safe interval is available before an initialization boundary.";
                prerequisites = paths(reaches(:, paths == entry.Path));
                protectors = yamada.source.PropertyInsertionPlanner.protectedWidths( ...
                    component, definitions(paths == entry.Path), entry.Path);
                for placement = plan.Placements
                    if any(prerequisites == placement.Path) && placement.Method == "assignment", nv(index) = false; end
                end

                % Prefer the existing constructor style only for verified arguments.
                if nv(index)
                    lower = 0;
                    prerequisites = paths(reaches(:, paths == entry.Path));
                    for argument = 1:numel(constructor)
                        if any(prerequisites == constructor(argument).Path) || ...
                                any([protectors.Id] == constructor(argument).Id), lower = argument; end
                    end
                    for slot = lower:numel(constructor)
                        before = yamada.model.PropertySetting.empty;
                        if slot < numel(constructor), before = constructor(slot + 1); end
                        edit = yamada.source.FactoryCallEditor.insert(source, statements(creation), entry, constructor(1), before);
                        earlier = plan.Placements(ismember(string({plan.Placements.Path}), prerequisites));
                        if any([earlier.Offset] > edit.End), continue, end
                        [accepted, candidate, found, failure] = yamada.source.PropertyInsertionPlanner.candidate( ...
                            source, [base plan.Edits edit], name, requested, registry, deferValidation, document);
                        if accepted
                            plan.Edits(end + 1) = edit;
                            plan.Placements(end + 1) = struct("Path", entry.Path, "Method", "nameValue", ...
                                "Offset", edit.End, "OwnerMethod", layout.Owner(creation));
                            plan.Document = candidate;
                            plan.Component = found;
                            break
                        end
                    end
                end
                if accepted, continue, end
                nv(index) = false;

                % Dependencies set the earliest visit; native-valid later slots remain candidates.
                prerequisites = paths(reaches(:, paths == entry.Path));
                lower = created;
                for setting = sourceSettings
                    if any(prerequisites == setting.Path) || any([protectors.Id] == setting.Id)
                        visits = find(arrayfun(@(statement) statement.Span.StartOffset, statements(order)) == ...
                            setting.SourceSpan.StartOffset);
                        if ~isempty(visits), lower = max(lower, max(visits)); end
                    end
                end
                for placement = plan.Placements
                    if any(prerequisites == placement.Path) && placement.Method == "assignment"
                        match = find([anchors.Offset] == placement.Offset, 1);
                        if ~isempty(match), lower = max(lower, anchors(match).Visit); end
                    end
                end
                upper = boundary(find(boundary > lower, 1));
                if isempty(upper), upper = inf; end
                for anchor = anchors
                    if anchor.Visit < lower || anchor.Visit >= upper, continue, end
                    text = yamada.source.PropertyInsertionPlanner.assignment(source, document, name, entry, anchor);
                    edit = struct("Start", anchor.Offset + 1, "End", anchor.Offset, "Text", text);
                    [accepted, candidate, found, failure] = yamada.source.PropertyInsertionPlanner.candidate( ...
                        source, [base plan.Edits edit], name, requested, registry, deferValidation, document);
                    if accepted
                        plan.Edits(end + 1) = edit;
                        plan.Placements(end + 1) = struct("Path", entry.Path, "Method", "assignment", ...
                            "Offset", anchor.Offset, "OwnerMethod", anchor.OwnerMethod);
                        plan.Document = candidate;
                        plan.Component = found;
                        break
                    end
                end
                if ~accepted
                    error("yamada:PropertyInsertionPlanner:UnsafePlacement", ...
                        "Cannot add %s without moving existing settings or crossing an initialization boundary: %s", entry.Path, failure);
                end
            end
            plan.Edits = yamada.source.CallbackSourceEdits.combineInsertions(plan.Edits);
        end
    end

    methods (Static, Access = private)
        function reaches = dependencies(definitions)
            % dependencies Project transitive canonical prerequisites independently of Inspector order.
            arguments (Input)
                definitions yamada.model.PropertyDefinition
            end
            arguments (Output)
                reaches logical
            end
            yamada.model.PropertyApplicationPolicy.orderDefinitions(definitions);
            paths = string({definitions.Path});
            count = numel(paths);
            reaches = false(count, count);
            for index = 1:count, reaches(ismember(paths, definitions(index).Application.ApplyAfter), index) = true; end
            for index = 1:count, reaches = reaches | (reaches(:, index) & reaches(index, :)); end
        end

        function settings = protectedWidths(component, definition, path)
            % protectedWidths Retain existing manual hold points before newly inserted upstream width writes.
            arguments (Input)
                component (1, 1) yamada.model.ComponentRecord
                definition (1, 1) yamada.model.PropertyDefinition
                path (1, 1) string
            end
            arguments (Output)
                settings yamada.model.PropertySetting
            end
            settings = yamada.model.PropertySetting.empty;
            if definition.Application.EffectPolicy ~= "axisWidth", return, end
            modes = strings(1, 0);
            if path == "LineWidth", modes = ["GridLineWidthMode", "MinorGridLineWidthMode"]; end
            if path == "GridLineWidth", modes = "MinorGridLineWidthMode"; end
            for setting = component.Settings
                if ~any(modes == setting.Path) || setting.Method == "generated" || ...
                        ~setting.IsCertain || setting.ValueKind ~= "literal", continue, end
                value = setting.LiteralValue;
                entry = component.getProperty(setting.Path);
                if ~isempty(entry) && entry.ValueKind == "literal" && isfield(entry.Metadata, "SourceSettingId") && ...
                        string(entry.Metadata.SourceSettingId) == string(setting.Id)
                    value = entry.LiteralValue;
                end
                if ((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && string(value) == "manual"
                    settings(end + 1) = setting; %#ok<AGROW>
                end
            end
        end

        function [anchors, boundary] = anchors(statements, order, certain, returns, layout, created, settings, selectionCreations, facts)
            % anchors Retain opaque boundaries while collecting certain component-owned insertion slots.
            arguments (Input)
                statements yamada.source.SourceStatement
                order double
                certain logical
                returns double
                layout (1, 1) struct
                created (1, 1) double
                settings yamada.model.PropertySetting
                selectionCreations double
                facts (1, 1) struct
            end
            arguments (Output)
                anchors (1, :) struct
                boundary (1, :) double
            end
            anchors = struct("Offset", {}, "Visit", {}, "OwnerMethod", {}, "Indent", {}, "Owned", {});
            boundary = zeros(1, 0);
            for visit = created:numel(order)
                index = order(visit);
                statement = statements(index);
                structural = facts.Structural(index);
                call = returns(visit) > visit;
                owned = settings(arrayfun(@(setting) ~isempty(setting.SourceSpan) && ...
                    setting.SourceSpan.StartOffset == statement.Span.StartOffset, settings));
                simpleReference = arrayfun(@(item) item.Path == "SelectedObject" && ...
                    ~isempty(regexp(char(strtrim(item.SourceExpression)), '^app\.[A-Za-z]\w*$', 'once')), owned);
                write = ~isempty(owned) && all([owned.IsCertain]) && ...
                    all(string({owned.ValueKind}) == "literal" | simpleReference);
                write = write || any(selectionCreations == statement.Span.StartOffset);
                if visit > created && ~structural && ~call && ~write
                    safe = facts.SafeLocal(index);
                    if ~safe
                        boundary(end + 1) = visit; %#ok<AGROW>
                        continue
                    end
                end
                if ~structural && certain(visit) && nnz(order == index) == 1 && layout.StraightLine(index)
                    offset = facts.AnchorOffset(index);
                    indent = facts.Indent(index);
                    anchors(end + 1) = struct("Offset", offset, "Visit", returns(visit), ...
                        "OwnerMethod", layout.Owner(index), "Indent", indent, ...
                        "Owned", visit == created || ~isempty(owned)); %#ok<AGROW>
                end
            end
            % Prefer the end of this component's settings before trying other proven slots.
            preferred = anchors([anchors.Owned]);
            [~, sorted] = sort([preferred.Visit], "descend");
            anchors = [preferred(sorted) anchors(~[anchors.Owned])];
        end

        function text = assignment(~, document, name, entry, anchor)
            % assignment Emit one literal statement after a source-preserving trailing-trivia anchor.
            arguments (Input)
                ~
                document (1, 1) yamada.model.DocumentModel
                name (1, 1) string
                entry (1, 1) yamada.model.PropertyEntry
                anchor (1, 1) struct
            end
            arguments (Output)
                text (1, 1) string
            end
            ending = string(newline);
            if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
            text = ending + anchor.Indent + "app." + name + "." + entry.Path + " = " + ...
                yamada.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
        end

        function edits = replacements(document)
            % replacements Overlay existing value-token requests without touching unrelated source.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                edits struct
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            for component = document.Components
                for entry = component.Properties
                    if entry.ValueKind ~= "literal" || ~isfield(entry.Metadata, "SourceSettingId"), continue, end
                    settings = component.getSettings(entry.Path);
                    original = settings(string({settings.Id}) == string(entry.Metadata.SourceSettingId));
                    if isempty(original) || isequaln(original(end).LiteralValue, entry.LiteralValue), continue, end
                    span = original(end).ValueSpan;
                    if ~isempty(span) && span.isKnown()
                        edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, ...
                            "Text", yamada.source.LiteralEncoder.encode(entry.LiteralValue)); %#ok<AGROW>
                    end
                end
            end
            if ~isempty(edits)
                [~, uniqueEdits] = unique([[edits.Start]' [edits.End]'], 'rows', 'stable');
                edits = edits(uniqueEdits);
            end
        end

        function [accepted, document, component, reason] = candidate(source, edits, name, requested, registry, deferValidation, baseline)
            % candidate Project owned edits and check intermediate and requested final states.
            arguments (Input)
                source (1, 1) string
                edits struct
                name (1, 1) string
                requested yamada.model.PropertyEntry
                registry (1, 1) yamada.model.ComponentRegistry
                deferValidation (1, 1) logical = false
                baseline yamada.model.DocumentModel = yamada.model.DocumentModel.empty
            end
            arguments (Output)
                accepted (1, 1) logical
                document yamada.model.DocumentModel
                component yamada.model.ComponentRecord
                reason (1, 1) string
            end
            accepted = false;
            document = yamada.model.DocumentModel.empty;
            component = yamada.model.ComponentRecord.empty;
            reason = "";
            % Tentative first slots are accepted only after the complete batch is validated.
            if deferValidation, accepted = true; return, end
            edits = yamada.source.CallbackSourceEdits.combineInsertions(edits);
            [~, order] = sort([edits.Start], 'descend');
            for index = order
                edit = edits(index);
                source = extractBefore(source, edit.Start) + edit.Text + extractAfter(source, edit.End);
            end
            assert(~isempty(baseline), "yamada:PropertyInsertionPlanner:MissingBaseline", "Editor candidates require loaded source ownership.");
            try
                [document, ~] = baseline.editedSourceCandidate(source, edits, registry);
            catch exception
                reason = string(exception.message); return
            end
            diagnostics = document.Diagnostics;
            reason = strjoin(string({diagnostics(string({diagnostics.Severity}) == "error").Message}), newline);
            if yamada.validation.ModelValidator.hasErrors(diagnostics), return, end
            component = document.getComponentByName(name);
            if isempty(component), reason = "The original component was not retained."; return, end
            states = document.getEffectivePropertyStates(registry, component.Id);
            for entry = requested
                match = find(arrayfun(@(state) state.Definition.Path == entry.Path, states), 1);
                if isempty(match) || ~yamada.model.PropertyStateResolver.matchesRequested(states(match).Resolution, entry.LiteralValue)
                    reason = "The requested " + entry.Path + " does not survive initialization.";
                    return
                end
            end
            accepted = true;
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
