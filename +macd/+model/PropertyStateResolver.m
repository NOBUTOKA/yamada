classdef PropertyStateResolver
    % PropertyStateResolver Resolve audited setter effects without executing source.
    %   The resolver replays certain explicit writes, overlays replacement
    %   requests at their original occurrences, and applies pending settings in
    %   canonical order. Unsupported effects stay unknown. Constructor Value
    %   validation is grouped; mode and unit arguments retain their own order.

    methods (Static)
        function [states, diagnostics] = resolve(component, definitions, document, registry)
            % resolve Return independent explicit/requested/effective states and proven errors.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                definitions macd.model.PropertyDefinition
                document macd.model.DocumentModel = macd.model.DocumentModel.empty
                registry macd.model.ComponentRegistry = macd.model.ComponentRegistry.empty
            end
            arguments (Output)
                states macd.model.PropertyState
                diagnostics macd.model.Diagnostic
            end
            context = macd.model.EvaluationContext.empty;
            if ~isempty(document) && ~isempty(registry)
                owned = document.getComponent(component.Id);
                if ~isempty(owned) && owned == component
                    context = document.evaluationContext(registry);
                    evaluationScope = context.readScope(); %#ok<NASGU>
                    [cached, found] = context.lookup("states:" + component.Id);
                    if found && isequaln(cached.Definitions, definitions)
                        states = cached.States;
                        diagnostics = cached.Diagnostics;
                        return
                    end
                end
            end
            [states, diagnostics] = macd.model.PropertyStateResolver.evaluate(component, definitions, document, registry);
            if ~isempty(context)
                context.remember("states:" + component.Id, struct("Definitions", definitions, ...
                    "States", states, "Diagnostics", diagnostics));
            end
        end
    end

    methods (Static, Access = private)
        function [states, diagnostics] = evaluate(component, definitions, document, registry)
            % evaluate Resolve one uncached input using the established finite policies.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                definitions macd.model.PropertyDefinition
                document macd.model.DocumentModel = macd.model.DocumentModel.empty
                registry macd.model.ComponentRegistry = macd.model.ComponentRegistry.empty
            end
            arguments (Output)
                states macd.model.PropertyState
                diagnostics macd.model.Diagnostic
            end

            % Defaults are audited seeds, never new PropertyEntry objects.
            states = macd.model.PropertyState.empty;
            diagnostics = macd.model.Diagnostic.empty;
            for definition = reshape(definitions, 1, [])
                entry = component.getProperty(definition.Path);
                settings = component.getSettings(definition.Path);
                last = macd.model.PropertySetting.empty;
                if ~isempty(settings), last = settings(end); end
                states(end + 1) = macd.model.PropertyState(definition, entry, last); %#ok<AGROW>
            end

            % Unknown initialization calls are user-owned; explicit native execution effects remain bounded.
            if ~isempty(document) && macd.model.PropertyStateResolver.hasUnresolvedExecution(document)
                for index = 1:numel(states)
                    states(index) = states(index).withEffective([], false, "unresolved-call", ...
                        "An initialization call, source-triggered callback, hierarchy setter, external HTML effect, or unrecognized setter requires application execution.", "initialization-call");
                    states(index) = states(index).withReadOnly(states(index).Reason);
                end
                return
            end

            % Conditional or unvisited factories cannot prove that their object exists.
            if ~isempty(document) && strlength(document.CurrentText) > 0 && macd.model.SourceOwnership.hasSource(component) && ...
                    (~isfield(component.Metadata, "InitializationCreationCertain") || ...
                    ~component.Metadata.InitializationCreationCertain)
                for index = 1:numel(states)
                    states(index) = states(index).withEffective([], false, "creation:" + component.Id, ...
                        "Component creation is conditional, repeated, or outside the proven initialization trace.", "source-creation");
                    states(index) = states(index).withReadOnly(states(index).Reason);
                end
                return
            end

            % Source additions use the same actual placement as generation and Preview.
            combined = false;
            if ~isempty(document) && ~isempty(registry)
                combined = (macd.model.GridLayoutStatePolicy.requiresCombinedPlan(component, document, registry) || ...
                    macd.model.ButtonSelectionPolicy.requiresCombinedPlan(component, document) || ...
                    macd.model.AncestorGeometryPolicy.requiresCombinedPlan(component, document)) && ...
                    ~(isfield(document.Metadata, "ResolvingCombinedPropertySource") && ...
                    document.Metadata.ResolvingCombinedPropertySource);
            end
            if ~isempty(document) && ~isempty(registry) && ...
                    (combined || macd.source.PropertySourcePlan.needsPlan(document, component))
                try
                    context = document.evaluationContext(registry);
                    [resolved, effectIds, found] = context.configurationStates("combined", component, definitions, document);
                    if ~found
                        if combined
                            plan = macd.source.PropertySourcePlan.combined(document, component, registry);
                        else
                            plan = macd.source.PropertySourcePlan.plan(document, component, registry);
                        end
                        resolved = macd.model.PropertyStateResolver.resolve(plan.Component, definitions, plan.Document, registry);
                        effectIds = strings(size(resolved));
                        for index = 1:numel(resolved)
                            effectIds(index) = macd.model.PropertyStateResolver.originalEffectId(component, plan.Component, ...
                                resolved(index).EffectKey, document, plan.Document);
                        end
                    end
                    incomplete = ~combined && macd.model.GridLayoutStatePolicy.requiresCombinedPlan(component, document, registry);
                    for index = 1:numel(states)
                        effective = resolved(index);
                        if incomplete && any(effective.Path == ["RowHeight", "ColumnWidth", "Layout.Row", "Layout.Column"])
                            states(index) = states(index).withEffective([], false, "", ...
                                "Grid placement requires a combined emitted candidate for pending changes.", "grid-layout");
                            continue
                        end
                        id = effectIds(index);
                        states(index) = states(index).withEffective(effective.EffectiveValue, effective.IsKnown, ...
                            id, effective.Reason, effective.ReasonCode);
                        if ~effective.IsEditable && strlength(effective.ReadOnlyReason) > 0
                            states(index) = states(index).withReadOnly(effective.ReadOnlyReason);
                        end
                    end
                catch exception
                    diagnostics(end + 1) = macd.model.Diagnostic("unsafe-property-insertion", "error", ...
                        string(exception.message), component.Id, component.SourceSpans.Creation);
                    for index = 1:numel(states)
                        states(index) = states(index).withEffective([], false, "unresolved-placement", string(exception.message), "placement");
                    end
                end
                return
            end

            % Keep source execution order, treating each constructor as one group.
            settings = component.Settings(string({component.Settings.Method}) ~= "generated");
            [~, order] = sort([settings.Sequence]);
            settings = settings(order);
            cursor = 1;
            while cursor <= numel(settings)
                groupEnd = cursor;
                if settings(cursor).Method == "nameValue"
                    while groupEnd < numel(settings) && settings(groupEnd + 1).Method == "nameValue" && ...
                            settings(groupEnd + 1).StatementId == settings(cursor).StatementId
                        groupEnd = groupEnd + 1;
                    end
                end
                group = settings(cursor:groupEnd);
                if settings(cursor).Method == "nameValue" && defersConstructorValue(definitions)
                    % MATLAB validates domain-backed constructor Value against the group.
                    group = [group(string({group.Path}) ~= "Value"), group(string({group.Path}) == "Value")];
                end
                for setting = group
                    entry = component.getProperty(setting.Path);
                    if isempty(entry), continue, end
                    value = setting.LiteralValue;
                    known = setting.ValueKind == "literal" && setting.IsCertain;
                    if known && isfield(entry.Metadata, "SourceSettingId") && ...
                            string(entry.Metadata.SourceSettingId) == string(setting.Id) && entry.ValueKind == "literal"
                        value = entry.LiteralValue;
                    end
                    [states, message] = macd.model.PropertyStateResolver.apply( ...
                        states, definitions, setting.Path, value, known, setting.Id, setting.Method == "nameValue");
                    if strlength(message) > 0
                        diagnostics(end + 1) = macd.model.Diagnostic("invalid-property-sequence", "error", ...
                            setting.Path + ": " + message, component.Id, setting.SourceSpan); %#ok<AGROW>
                    end
                end
                if settings(cursor).Method == "nameValue"
                    widthPaths = string({definitions(arrayfun(@(item) item.Application.EffectPolicy == "axisWidth", definitions)).Path});
                    if any(ismember(string({group.Path}), widthPaths))
                        states = macd.model.PropertyStateResolver.constructorWidths(states, group);
                    end
                end
                cursor = groupEnd + 1;
            end

            % New settings have no source span yet; legacy entries also use this path.
            entries = component.Properties;
            if ~isempty(settings), entries = entries(arrayfun(@(entry) isempty(entry.SourceSpan), entries)); end
            if ~isempty(entries), entries = macd.model.PropertyApplicationPlanner.order(entries, definitions); end
            for entry = entries
                id = "pending:" + component.Id + ":" + entry.Path;
                if isfield(entry.Metadata, "PendingSettingId"), id = string(entry.Metadata.PendingSettingId); end
                [states, message] = macd.model.PropertyStateResolver.apply(states, definitions, ...
                    entry.Path, entry.LiteralValue, entry.ValueKind == "literal" && entry.IsEditable, id);
                if strlength(message) > 0
                    diagnostics(end + 1) = macd.model.Diagnostic("invalid-property-sequence", "error", ...
                        entry.Path + ": " + message, component.Id); %#ok<AGROW>
                end
            end
            if ~isempty(document) && ~isempty(registry)
                states = macd.model.GridLayoutStatePolicy.resolve(states, component, document, registry);
                [states, selectionDiagnostics] = macd.model.ButtonSelectionPolicy.resolve(states, component, document, registry);
                diagnostics = [diagnostics selectionDiagnostics];
                states = macd.model.AncestorGeometryPolicy.resolve(states, component, document);
            else
                for index = 1:numel(definitions)
                    if definitions(index).Application.EffectPolicy ~= "buttonSelection", continue, end
                    states(index) = states(index).withEffective([], false, "", ...
                        "Button selection requires the owning document and sibling creation order.", "button-selection");
                end
            end
            states = macd.model.PropertyStateResolver.retainUnreviewedEffects(states, definitions, component, registry);
        end

    end

    methods (Static)
        function result = hasUnresolvedExecution(document)
            % hasUnresolvedExecution Identify explicit execution effects outside modeled component settings.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = any(cellfun(@(field) isfield(document.Metadata, field) && ...
                document.Metadata.(field), {"HasUnresolvedLifecycleEffects", ...
                "HasUnresolvedExecutableEffects", "HasUnrecognizedSetter"}));
        end

        function id = unresolvedEffectId(members, paths, registry)
            % unresolvedEffectId Find unsupported or uncertain coupled writes without adding history.
            arguments (Input)
                members macd.model.ComponentRecord
                paths string
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                id (1, 1) string
            end
            id = "";
            for member = reshape(members, 1, [])
                definition = registry.get(member.Factory, member.CreationArguments);
                names = macd.model.PropertyStateResolver.namedPaths(member, registry);
                for property = reshape(definition.Properties, 1, [])
                    policy = property.Application;
                    settings = member.getSettings(property.Path);
                    uncertain = policy.EffectStatus == "unknown" && ...
                        any(arrayfun(@(item) item.ValueKind ~= "literal" || ~item.IsCertain, settings));
                    if (policy.EffectStatus ~= "unsupported" && ~uncertain) || ...
                            (~isempty(policy.AffectedPaths) && ~any(ismember([property.Path policy.AffectedPaths], paths)))
                        continue
                    end
                    if ~isempty(settings)
                        id = settings(end).Id;
                        return
                    elseif any(names == property.Path)
                        id = "creation:" + member.Id;
                        return
                    end
                end
            end
        end

        function transaction = transaction(states)
            % transaction Copy only resolved effective values into a validator snapshot.
            arguments (Input)
                states macd.model.PropertyState
            end
            arguments (Output)
                transaction (1, 1) macd.model.PropertyTransaction
            end
            values = cell(1, numel(states));
            for index = 1:numel(states), values{index} = states(index).EffectiveValue; end
            transaction = macd.model.PropertyTransaction(string({states.Path}), values, [states.IsKnown]);
        end

        function result = matchesRequested(state, value)
            % matchesRequested Compare a resolved result with a literal edit request.
            arguments (Input)
                state (1, 1) macd.model.PropertyState
                value
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = state.IsKnown && macd.model.PropertyStateResolver.equivalent(state.EffectiveValue, value);
            if state.IsKnown && state.Path == "Position" && ...
                    macd.model.PositionGeometry.valid(state.EffectiveValue) && macd.model.PositionGeometry.valid(value)
                first = reshape(double(state.EffectiveValue), 1, 4);
                second = reshape(double(value), 1, 4);
                result = all(abs(first - second) <= 16 * eps(max(1, max(abs(first), abs(second)))));
            end
            if state.IsKnown && state.EffectPolicy == "buttonSelection" && ...
                    (isnumeric(value) || islogical(value)) && isreal(value) && isscalar(value) && any(value == [0 1])
                result = isequaln(double(state.EffectiveValue), double(value));
            end
            if state.IsKnown && state.EffectPolicy == "gridTracks"
                result = macd.model.GridLayoutStatePolicy.equivalent(state.EffectiveValue, value);
            end
        end

        function result = valuesEquivalent(first, second)
            % valuesEquivalent Compare literal values using native scalar-text equivalence.
            arguments (Input)
                first
                second
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = macd.model.PropertyStateResolver.equivalent(first, second);
        end
    end

    methods (Static)
        function id = originalEffectId(original, candidate, candidateId, document, candidateDocument)
            % originalEffectId Map candidate-only offsets back to immutable original or pending identities.
            arguments (Input)
                original (1, 1) macd.model.ComponentRecord
                candidate (1, 1) macd.model.ComponentRecord
                candidateId (1, 1) string
                document (1, 1) macd.model.DocumentModel
                candidateDocument (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                id (1, 1) string
            end
            id = "";
            if startsWith(candidateId, "creation:")
                created = candidateDocument.getComponent(extractAfter(candidateId, "creation:"));
                if ~isempty(created)
                    for member = document.Components
                        if document.sourceComponentName(member.Id) == created.Name || member.Name == created.Name
                            id = "creation:" + member.Id;
                            return
                        end
                    end
                end
            end
            effect = candidate.Settings(string({candidate.Settings.Id}) == candidateId);
            if isempty(effect)
                % A direct child may determine its parent grid's effective track getter.
                for member = candidateDocument.Components
                    match = member.Settings(string({member.Settings.Id}) == candidateId);
                    if isempty(match), continue, end
                    for before = document.Components
                        if document.sourceComponentName(before.Id) == member.Name || before.Name == member.Name
                            id = macd.model.PropertyStateResolver.originalEffectId(before, member, ...
                                candidateId, document, candidateDocument);
                            return
                        end
                    end
                end
                return
            end
            path = effect(end).Path;
            before = original.getSettings(path);
            after = candidate.getSettings(path);
            ordinal = find(string({after.Id}) == candidateId, 1, 'last');
            if ~isempty(before) && ~isempty(ordinal)
                id = before(min(ordinal, numel(before))).Id;
            elseif isempty(before)
                id = "pending:" + original.Id + ":" + path;
            end
        end
    end

    methods (Static, Access = private)
        function names = namedPaths(component, registry)
            % namedPaths Read legacy constructor names without inventing source occurrences.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                registry macd.model.ComponentRegistry
            end
            arguments (Output)
                names (1, :) string
            end
            names = strings(1, 0);
            if macd.model.SourceOwnership.hasSource(component) || isempty(registry), return, end
            definition = registry.get(component.Factory, component.CreationArguments);
            first = macd.model.PropertyApplicationPlanner.nameValueStart(definition, component.CreationArguments);
            for index = first:2:numel(component.CreationArguments) - 1
                value = component.CreationArguments{index};
                if (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))
                    names(end + 1) = string(value); %#ok<AGROW>
                end
            end
        end

        function states = retainUnreviewedEffects(states, definitions, component, registry)
            % retainUnreviewedEffects Retain unsupported and source-uncertain upstream effects.
            arguments (Input)
                states macd.model.PropertyState
                definitions macd.model.PropertyDefinition
                component (1, 1) macd.model.ComponentRecord
                registry macd.model.ComponentRegistry
            end
            arguments (Output)
                states macd.model.PropertyState
            end
            names = macd.model.PropertyStateResolver.namedPaths(component, registry);
            paths = string({states.Path});
            for definition = reshape(definitions, 1, [])
                policy = definition.Application;
                settings = component.getSettings(definition.Path);
                uncertain = policy.EffectStatus == "unknown" && ...
                    any(arrayfun(@(item) item.ValueKind ~= "literal" || ~item.IsCertain, settings));
                if policy.EffectStatus ~= "unsupported" && ~uncertain, continue, end
                raw = any(names == definition.Path);
                if isempty(settings) && ~raw, continue, end
                id = "creation:" + component.Id;
                sequence = 0;
                if ~isempty(settings), id = settings(end).Id; sequence = max([settings.Sequence]); end
                affected = policy.AffectedPaths;
                if isempty(affected), affected = paths; end
                for index = find(ismember(paths, [definition.Path affected]))
                    % A later confirmed independent write can restore its own stored input.
                    restores = component.Settings(string({component.Settings.Id}) == states(index).EffectKey & ...
                        string({component.Settings.Path}) == states(index).Path);
                    if states(index).IsKnown && definitions(index).Application.EffectStatus == "independent" && ...
                            ~isempty(restores) && restores(end).Sequence > sequence
                        continue
                    end
                    states(index) = states(index).withEffective([], false, id, policy.EffectReason, "unreviewed-effect");
                    states(index) = states(index).withReadOnly(policy.EffectReason);
                end
            end
        end

        function [states, message] = apply(states, definitions, path, value, known, id, constructor)
            % apply Resolve one supported write and its allowlisted sibling effects.
            arguments (Input)
                states macd.model.PropertyState
                definitions macd.model.PropertyDefinition
                path (1, 1) string
                value
                known (1, 1) logical
                id (1, 1) string
                constructor (1, 1) logical = false
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            paths = string({states.Path});
            index = find(paths == path, 1);
            if isempty(index), return, end
            previous = states;
            policy = definitions(index).Application;
            if policy.EffectStatus == "unsupported" || (policy.EffectStatus == "unknown" && ~known)
                affected = policy.AffectedPaths;
                if isempty(affected), affected = paths; end
                affected = unique([path affected]);
                for target = affected
                    states = setUnknown(states, target, id, policy.EffectReason, "unreviewed-effect");
                end
                return
            end
            % Unreviewed literal setters retain their input without asserting audited independence.
            states(index) = states(index).withEffective(value, known, id, "The source value or its execution is uncertain.", "source");
            if known, states(index) = states(index).withEffective(value, true, id); end
            if policy.EffectPolicy == "buttonSelection" && path == "Value" && known && ...
                    (~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ~isreal(value) || ~any(value == [0 1]))
                message = "Button Value must be zero or one.";
                states = setUnknown(states, path, id, message, "constraint");
                return
            end
            % Read-only getter writes are cleaned by the existing generation policy.
            if macd.model.PositionAliasPolicy.applies(definitions(index))
                if ~definitions(index).IsEditable
                    states(index) = previous(index);
                    return
                end
                [states, message] = macd.model.PositionAliasPolicy.apply(states, definitions, path, id);
            end
            if any(policy.EffectPolicy == ["positionInput", "sliderPosition", "squarePosition", "switchPosition", "semicircularPosition", "linearPosition"])
                for alias = ["InnerPosition", "OuterPosition"]
                    states = setUnknown(states, alias, id, "This getter depends on native decoration or container layout.", "native-geometry");
                end
                if known && (~isnumeric(value) || ~isreal(value) || numel(value) ~= 4 || ...
                        any(~isfinite(value), "all") || any(value(3:4) < 0))
                    message = "Position requires four finite real values and nonnegative dimensions.";
                    states = setUnknown(states, path, id, message, "constraint");
                elseif known
                    value = reshape(double(value), 1, 4);
                    [orientation, orientationKnown] = stateValue(states, "Orientation");
                    if ~orientationKnown, orientation = ""; end
                    spec = macd.model.PositionGeometry.constraint(policy.EffectPolicy, string(orientation), orientationKnown);
                    if ~spec.Known
                        states = setUnknown(states, path, id, "Position requires a known Orientation.", "native-geometry");
                        return
                    end
                    value = macd.model.PositionGeometry.normalize(value, spec);
                    states = setEffective(states, path, value, id);
                end
            end
            valueIndex = find(paths == "Value", 1);
            family = "none";
            if ~isempty(valueIndex), family = definitions(valueIndex).Application.EffectPolicy; end

            % Each family implements only reviewed semantics, never arbitrary setters.
            if family == "boundedValue" && any(path == ["Value", "Limits"])
                [states, message] = macd.model.PropertyStateResolver.bounded(states, definitions(valueIndex), path, id);
            elseif family == "numericValue" && any(path == ["Value", "Limits", ...
                    "LowerLimitInclusive", "UpperLimitInclusive", "RoundFractionalValues", "AllowEmpty"])
                [states, message] = macd.model.PropertyStateResolver.numeric(states, path, id);
            elseif family == "itemSelection" && any(path == ["Value", "Items", "ItemsData", "Editable", "Multiselect"])
                [states, message] = macd.model.PropertyStateResolver.items(states, previous, path, id);
            elseif family == "textValue" && any(path == ["Value", "CharacterLimits"])
                [states, message] = macd.model.PropertyStateResolver.text(states, path, id);
            end

            % Width followers hold manual values or derive them through known auto modes.
            if definitions(index).Application.EffectPolicy == "axisWidth"
                [states, message] = macd.model.PropertyStateResolver.widths(states, path, known, id, constructor);
            end

            % Audited value setters force manual mode; auto values remain runtime-derived.
            modePolicies = ["tickMode", "valueMode"];
            if any(definitions(index).Application.EffectPolicy == [modePolicies, "modeFlag"])
                target = find(paths == path + "Mode", 1);
                if ~isempty(target)
                    reason = "";
                    if ~known, reason = "An uncertain value setter may change this mode."; end
                    states(target) = states(target).withEffective("manual", known, id, reason);
                end
            elseif endsWith(path, "Mode")
                base = extractBefore(path, strlength(path) - 3);
                target = find(paths == base, 1);
                if ~isempty(target) && any(definitions(target).Application.EffectPolicy == modePolicies)
                    if ~known
                        states(target) = states(target).withEffective([], false, id, ...
                            "An uncertain mode may compute this value at runtime.", "uncertain-mode");
                    elseif ((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && string(value) == "auto"
                        states(target) = states(target).withEffective([], false, id, ...
                            "Automatic mode computes this value at runtime.", "automatic");
                    end
                end
            end

            if path == "Orientation"
                position = find(paths == "Position", 1);
                if ~isempty(position) && any(definitions(position).Application.EffectPolicy == ...
                        ["switchPosition", "semicircularPosition", "linearPosition", "sliderPosition"])
                    familyPolicy = definitions(position).Application.EffectPolicy;
                    [oldOrientation, oldKnown] = stateValue(previous, "Orientation");
                    if ~oldKnown, oldOrientation = ""; end
                    newOrientation = "";
                    if known && ((isstring(value) && isscalar(value)) || (ischar(value) && isrow(value)))
                        newOrientation = string(value);
                    end
                    beforeSpec = macd.model.PositionGeometry.constraint(familyPolicy, string(oldOrientation), oldKnown);
                    afterSpec = macd.model.PositionGeometry.constraint(familyPolicy, newOrientation, known);
                    if familyPolicy == "linearPosition"
                        beforeSpec.Known = oldKnown && any(string(oldOrientation) == ["horizontal", "vertical"]);
                        afterSpec.Known = known && any(newOrientation == ["horizontal", "vertical"]);
                    end
                    if states(position).IsKnown && beforeSpec.Known && afterSpec.Known
                        rectangle = states(position).EffectiveValue;
                        changed = ~isequaln(beforeSpec.Ratio, afterSpec.Ratio) || ...
                            beforeSpec.FixedIndex ~= afterSpec.FixedIndex || ...
                            (familyPolicy == "linearPosition" && string(oldOrientation) ~= newOrientation);
                        if changed, rectangle(3:4) = rectangle([4 3]); end
                        states = setEffective(states, "Position", rectangle, id);
                    else
                        states = setUnknown(states, "Position", id, "Orientation requires known prior geometry.", "native-geometry");
                    end
                    for alias = ["InnerPosition", "OuterPosition"]
                        states = setUnknown(states, alias, id, "This getter depends on native decoration or container layout.", "native-geometry");
                    end
                end
            end
            % Infinite endpoints request native data-dependent axis-limit calculation.
            if definitions(index).Application.EffectPolicy == "valueMode" && ...
                    endsWith(path, "Lim") && known && isnumeric(value) && any(~isfinite(value), "all")
                states(index) = states(index).withEffective([], false, id, ...
                    "Automatic limit endpoints depend on native axes data and layout.", "automatic-limits");
            end

            % Unit conversion depends on native parent geometry and display metrics.
            if any(path == ["Units", "FontUnits"])
                targetPaths = ["Position", "InnerPosition", "OuterPosition"];
                if path == "FontUnits", targetPaths = "FontSize"; end
                same = known && previous(index).IsKnown && ...
                    macd.model.PropertyStateResolver.equivalent(value, previous(index).EffectiveValue);
                if ~same
                    for targetPath = targetPaths
                        states = setUnknown(states, targetPath, id, ...
                            path + " requires native unit conversion.", "unit-conversion");
                    end
                end
            end
        end

        function [states, message] = widths(states, path, known, id, constructor)
            % widths Resolve reviewed LineWidth and grid-width followers without changing explicit inputs.
            arguments (Input)
                states macd.model.PropertyState
                path (1, 1) string
                known (1, 1) logical
                id (1, 1) string
                constructor (1, 1) logical
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            values = ["LineWidth", "GridLineWidth", "MinorGridLineWidth"];
            if any(path == values) && known
                [value, ~] = stateValue(states, path);
                if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value) || value <= 0
                    message = "Line widths must be positive finite numeric scalars.";
                    states = setUnknown(states, path, id, message, "constraint");
                    return
                end
            end
            if any(path == values(2:3))
                mode = path + "Mode";
                if known
                    states = setEffective(states, mode, "manual", id);
                else
                    states = setUnknown(states, mode, id, "An uncertain width setter may select manual mode.", "source");
                end
            end

            % A manual hold is an effective dependency even when it freezes an audited default.
            if any(path == ["GridLineWidthMode", "MinorGridLineWidthMode"]) && known
                [mode, ~] = stateValue(states, path);
                if ((ischar(mode) && isrow(mode)) || (isstring(mode) && isscalar(mode))) && string(mode) == "manual"
                    receiver = extractBefore(path, strlength(path) - 3);
                    [held, heldKnown] = stateValue(states, receiver);
                    if heldKnown, states = setEffective(states, receiver, held, id); end
                end
            end
            if constructor, return, end

            % A manual receiver holds its current getter value, including prior implicit values.
            if any(path == ["LineWidth", "GridLineWidth", "GridLineWidthMode"])
                propagated = path == "GridLineWidth";
                if path ~= "GridLineWidth"
                    [states, propagated] = followWidth(states, "LineWidth", "GridLineWidth", id);
                end
                if propagated, states = followWidth(states, "GridLineWidth", "MinorGridLineWidth", id); end
            elseif path == "MinorGridLineWidthMode"
                states = followWidth(states, "GridLineWidth", "MinorGridLineWidth", id);
            end
        end

        function states = constructorWidths(states, group)
            % constructorWidths Finalize native constructor followers after all explicit values and mode flags.
            arguments (Input)
                states macd.model.PropertyState
                group macd.model.PropertySetting
            end
            arguments (Output)
                states macd.model.PropertyState
            end
            paths = string({states.Path});
            pairs = ["LineWidth" "GridLineWidth"; "GridLineWidth" "MinorGridLineWidth"];
            for index = 1:size(pairs, 1)
                upstream = pairs(index, 1);
                receiver = pairs(index, 2);
                mode = states(paths == receiver + "Mode");
                parent = states(paths == upstream);
                if isempty(mode) || isempty(parent), continue, end
                id = mode.EffectKey;
                if mode.IsKnown
                    candidates = [mode.EffectKey, parent.EffectKey];
                    id = "";
                    for setting = group
                        if any(candidates == string(setting.Id)), id = setting.Id; end
                    end
                end
                states = followWidth(states, upstream, receiver, id);
            end
        end

        function [states, message] = bounded(states, definition, path, id)
            % bounded Validate scalar or range values and apply inclusive clamping.
            arguments (Input)
                states macd.model.PropertyState
                definition (1, 1) macd.model.PropertyDefinition
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [limits, limitsKnown] = stateValue(states, "Limits");
            [value, valueKnown] = stateValue(states, "Value");
            if ~limitsKnown
                states = setUnknown(states, "Value", id, "Limits is not known.", "constraint");
                return
            end
            if ~isnumeric(limits) || numel(limits) ~= 2 || any(~isfinite(limits)) || limits(1) >= limits(2)
                message = "Limits must contain two finite increasing bounds.";
            elseif valueKnown
                wrongSize = (definition.Editor == "number" && ~isscalar(value)) || ...
                    (isfield(definition.ValueSchema, "fixedLength") && numel(value) ~= definition.ValueSchema.fixedLength);
                if ~isnumeric(value) || isempty(value) || any(~isfinite(value)) || wrongSize
                    message = "Value must contain finite numbers.";
                elseif path == "Value" && any(value < limits(1) | value > limits(2))
                    message = "Value is outside Limits at this source occurrence.";
                elseif path == "Limits"
                    states = setEffective(states, "Value", min(max(value, limits(1)), limits(2)), id);
                end
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function [states, message] = numeric(states, path, id)
            % numeric Resolve numeric bounds, rounding, and conditional empty values.
            arguments (Input)
                states macd.model.PropertyState
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [limits, limitsKnown] = stateValue(states, "Limits");
            [value, valueKnown] = stateValue(states, "Value");
            [lower, lowerKnown] = stateSwitch(states, "LowerLimitInclusive");
            [upper, upperKnown] = stateSwitch(states, "UpperLimitInclusive");
            [rounding, roundingKnown] = stateSwitch(states, "RoundFractionalValues");
            [allowEmpty, emptyKnown] = stateSwitch(states, "AllowEmpty");
            if ~all([limitsKnown lowerKnown upperKnown roundingKnown emptyKnown])
                states = setUnknown(states, "Value", id, "A numeric value constraint is not known.", "constraint");
                return
            end
            if ~isnumeric(limits) || numel(limits) ~= 2 || any(isnan(limits)) || ...
                    limits(1) > limits(2) || (limits(1) == limits(2) && (~lower || ~upper))
                message = "The numeric constraints leave no allowed range.";
            elseif valueKnown
                if isempty(value)
                    if allowEmpty, return, end
                    if path == "Value"
                        message = "An empty Value requires AllowEmpty on.";
                    else
                        value = 0;
                    end
                elseif ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
                    message = "Value must be one finite number or an allowed empty array.";
                end
                if strlength(message) == 0
                    if rounding
                        minimum = ceil(limits(1));
                        maximum = floor(limits(2));
                        if ~lower && minimum == limits(1), minimum = minimum + 1; end
                        if ~upper && maximum == limits(2), maximum = maximum - 1; end
                        if minimum > maximum
                            message = "The configured limits contain no allowed integer.";
                        else
                            states = setEffective(states, "Value", min(max(round(value), minimum), maximum), id);
                        end
                    else
                        below = value < limits(1) || (~lower && value == limits(1));
                        above = value > limits(2) || (~upper && value == limits(2));
                        if path == "Value" && (below || above)
                            message = "Value is outside the allowed bounds at this source occurrence.";
                        elseif (below && ~lower) || (above && ~upper)
                            states = setUnknown(states, "Value", id, "Native adjustment to an exclusive bound is not yet resolved.", "adjustment");
                        else
                            states = setEffective(states, "Value", min(max(value, limits(1)), limits(2)), id);
                        end
                    end
                end
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function [states, message] = text(states, path, id)
            % text Enforce nonempty text length and model limit-induced clearing.
            arguments (Input)
                states macd.model.PropertyState
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [limits, limitsKnown] = stateValue(states, "CharacterLimits");
            [value, valueKnown] = stateValue(states, "Value");
            if ~limitsKnown
                states = setUnknown(states, "Value", id, "CharacterLimits is not known.", "constraint");
                return
            end
            if ~isnumeric(limits) || numel(limits) ~= 2 || ~isfinite(limits(1)) || limits(1) < 0 || ...
                    any(isnan(limits)) || limits(1) > limits(2) || any(limits ~= floor(limits))
                message = "CharacterLimits must contain increasing nonnegative integer bounds.";
            elseif valueKnown
                if ~((ischar(value) && (isrow(value) || isempty(value))) || (isstring(value) && isscalar(value)))
                    message = "Value must be scalar text.";
                else
                    count = strlength(string(value));
                    if count > 0 && (count < limits(1) || count > limits(2))
                        if path == "Value"
                            message = "The text length is outside CharacterLimits.";
                        else
                            states = setEffective(states, "Value", '', id);
                        end
                    end
                end
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function [states, message] = items(states, previous, path, id)
            % items Resolve reviewed item-domain selection and index-preserving data changes.
            arguments (Input)
                states macd.model.PropertyState
                previous macd.model.PropertyState
                path (1, 1) string
                id (1, 1) string
            end
            arguments (Output)
                states macd.model.PropertyState
                message (1, 1) string
            end
            message = "";
            [items, itemsKnown] = stateValue(states, "Items");
            [data, dataKnown] = stateValue(states, "ItemsData");
            [value, valueKnown] = stateValue(states, "Value");
            if ~itemsKnown || ~dataKnown
                states = setUnknown(states, "Value", id, "Items or ItemsData is not known.", "constraint");
                return
            end
            labels = selectionCells(items);
            candidates = labels;
            if ~isempty(data), candidates = selectionCells(data); end
            candidates = candidates(1:min(numel(labels), numel(candidates)));
            [multi, multiKnown] = stateSwitch(states, "Multiselect");
            if ~any(string({states.Path}) == "Multiselect"), multiKnown = true; end
            [editable, editableKnown] = stateSwitch(states, "Editable");
            if ~any(string({states.Path}) == "Editable"), editableKnown = true; end
            if ~multiKnown || ~editableKnown
                states = setUnknown(states, "Value", id, "The selection mode is not known.", "constraint");
                return
            end
            if ~valueKnown, return, end
            selected = selectionCells(value);
            if path == "ItemsData"
                [oldData, oldDataKnown] = stateValue(previous, "ItemsData");
                [oldValue, oldValueKnown] = stateValue(previous, "Value");
                if oldDataKnown && oldValueKnown && (isempty(oldData) ~= isempty(data))
                    oldCandidates = labels;
                    if ~isempty(oldData), oldCandidates = selectionCells(oldData); end
                    selected = cell(1, 0);
                    for item = selectionCells(oldValue)
                        match = find(cellfun(@(candidate) macd.model.PropertyStateResolver.equivalent(candidate, item{1}), oldCandidates), 1);
                        if ~isempty(match) && match <= numel(candidates), selected{end + 1} = candidates{match}; end %#ok<AGROW>
                    end
                end
            end
            represented = cellfun(@(item) any(cellfun(@(candidate) ...
                macd.model.PropertyStateResolver.equivalent(candidate, item), candidates)), selected);
            freeText = editable && ((ischar(value) && (isrow(value) || isempty(value))) || ...
                (isstring(value) && isscalar(value)));
            if path == "Value"
                if (~multi && numel(selected) ~= 1 && ~isempty(selected)) || ...
                        (~all(represented) && ~freeText) || (isempty(selected) && ~any(string({states.Path}) == "Multiselect"))
                    message = "Value is not represented by the current item domain or selection mode.";
                end
            else
                selected = selected(represented);
                if isempty(selected) && ~isempty(candidates), selected = candidates(1); end
                if ~multi && numel(selected) > 1, selected = selected(1); end
                if isempty(selected)
                    value = {};
                elseif multi
                    if ~isempty(data) && isnumeric(data), value = [selected{:}]; else, value = selected; end
                else
                    value = selected{1};
                end
                states = setEffective(states, "Value", value, id);
            end
            if strlength(message) > 0, states = setUnknown(states, "Value", id, message); end
        end

        function result = equivalent(first, second)
            % equivalent Compare native scalar text independently of char/string spelling.
            arguments (Input)
                first
                second
            end
            arguments (Output)
                result (1, 1) logical
            end
            text = @(value) (ischar(value) && (isrow(value) || isempty(value))) || ...
                (isstring(value) && isscalar(value));
            result = isequaln(first, second);
            if text(first) && text(second), result = isequaln(string(first), string(second)); end
        end
    end
end

function result = defersConstructorValue(definitions)
% defersConstructorValue Identify constructor values with group-validated domains.
arguments (Input)
    definitions macd.model.PropertyDefinition
end
arguments (Output)
    result (1, 1) logical
end
index = find(string({definitions.Path}) == "Value", 1);
result = ~isempty(index) && (any(definitions(index).Application.EffectPolicy == ...
    ["boundedValue", "numericValue", "itemSelection", "textValue"]) || definitions(index).Editor == "dateTime");
end

function [value, known] = stateValue(states, path)
% stateValue Read an independently resolved value without falling back to a source literal.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
end
arguments (Output)
    value
    known (1, 1) logical
end
index = find(string({states.Path}) == path, 1);
known = ~isempty(index) && states(index).IsKnown;
value = [];
if known, value = states(index).EffectiveValue; end
end

function [states, applied] = followWidth(states, upstream, receiver, id)
% followWidth Copy a known upstream width only when the receiver's mode is automatic.
arguments (Input)
    states macd.model.PropertyState
    upstream (1, 1) string
    receiver (1, 1) string
    id (1, 1) string
end
arguments (Output)
    states macd.model.PropertyState
    applied (1, 1) logical
end
applied = true;
[mode, known] = stateValue(states, receiver + "Mode");
if ~known || ~((ischar(mode) && isrow(mode)) || (isstring(mode) && isscalar(mode)))
    states = setUnknown(states, receiver, id, "An uncertain mode may change this width.", "uncertain-mode");
elseif string(mode) == "auto"
    [value, valueKnown] = stateValue(states, upstream);
    if valueKnown
        states = setEffective(states, receiver, value, id);
    else
        states = setUnknown(states, receiver, id, upstream + " is not known.", "width-follower");
    end
elseif string(mode) ~= "manual"
    states = setUnknown(states, receiver, id, "The width mode is not supported.", "uncertain-mode");
else
    applied = false;
end
end

function [value, known] = stateSwitch(states, path)
% stateSwitch Read a known scalar documented on/off state.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
end
arguments (Output)
    value (1, 1) logical
    known (1, 1) logical
end
[raw, known] = stateValue(states, path);
value = false;
if known
    if (islogical(raw) || isnumeric(raw)) && isscalar(raw)
        value = logical(raw);
    elseif (ischar(raw) && isrow(raw)) || (isstring(raw) && isscalar(raw))
        value = string(raw) == "on";
        known = any(string(raw) == ["on", "off"]);
    else
        known = false;
    end
end
end

function states = setEffective(states, path, value, id)
% setEffective Replace only the effective projection of one derived sibling.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
    value
    id (1, 1) string
end
arguments (Output)
    states macd.model.PropertyState
end
index = find(string({states.Path}) == path, 1);
if ~isempty(index), states(index) = states(index).withEffective(value, true, id); end
end

function states = setUnknown(states, path, id, reason, code)
% setUnknown Retain a reason instead of inventing an effective value.
arguments (Input)
    states macd.model.PropertyState
    path (1, 1) string
    id (1, 1) string
    reason (1, 1) string
    code (1, 1) string = "effect"
end
arguments (Output)
    states macd.model.PropertyState
end
index = find(string({states.Path}) == path, 1);
if ~isempty(index), states(index) = states(index).withEffective([], false, id, reason, code); end
end

function values = selectionCells(value)
% selectionCells Split item domains without evaluating or changing scalar text values.
arguments (Input)
    value
end
arguments (Output)
    values cell
end
if iscell(value)
    values = reshape(value, 1, []);
elseif ischar(value)
    values = {value};
else
    values = num2cell(reshape(value, 1, []));
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
