classdef AxesInspectorEdits
    % AxesInspectorEdits Plan source-preserving axes text and format edits.
    %   Each patch carries typed occurrence changes for indexed publication and history.

    methods (Static)
        function [batch, requested, forward, inverse, paths] = plan(document, component, path, value, action, registry, effective)
            % plan Build a reversible patch against one exact source snapshot.
            %   effective(modePath) returns the effective value of a Mode and whether it is known.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                path (1,1) string
                value
                action (1,1) string {mustBeMember(action,["set","override","share"])}
                registry (1,1) yamada.model.ComponentRegistry = ""
                effective = []
            end
            arguments (Output)
                batch (1,1) yamada.source.SourcePatchBatch
                requested
                forward (1,1) struct
                inverse (1,1) struct
                paths (1,:) string
            end

            if path == "GeographicLimits" && component.Factory == "geoaxes" && action == "set"
                [batch, requested, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.geographicLimits(document,component,value,registry);
                return
            end
            if path == "AxisStyle" && any(component.Factory == ["axes","uiaxes"]) && action == "set"
                [batch, requested, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.axisStyle(document,component,value,registry);
                return
            end
            if path == "AxisVis3d" && any(component.Factory == ["axes","uiaxes"]) && action == "set"
                [batch, requested, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.axisVis3d(document,component,value,registry);
                return
            end
            assert(any(yamada.model.AxesInspectorProperties.paths(component.Factory) == path), ...
                "yamada:AxesInspectorEdits:Path", "This setting is unavailable for the selected axes.");
            settings = component.getSettings(path);
            original = yamada.model.PropertySetting.empty;
            if ~isempty(settings), original = settings(end); end
            [shared, canShare, titleValue] = yamada.model.AxesInspectorProperties.subtitleLink(component,path);
            source = document.CurrentText;
            analysis = document.sourceAnalysis();
            forward = struct("Changes",struct("SettingId",{},"Value",{}), ...
                "Placements",struct("Statement",{},"Setting",{},"Offset",{}),"RemovedIds",zeros(1,0));
            inverse = forward;
            paths = path;
            if action == "share"
                assert(canShare && ~shared, "yamada:AxesInspectorEdits:Share", ...
                    "This Subtitle override has no proven Title setting to restore.");
                span = original.SourceSpan;
                edit = struct("Start",span.StartOffset,"End",span.EndOffset,"Text","");
                edits = yamada.source.SourceFormatting.cleanDeletions(source,edit);
                requested = titleValue;
                forward.RemovedIds = original.Id;
                index = analysis.statementIndices(span);
                assert(isscalar(index));
                inverse.Placements = struct("Statement",analysis.Statements(index), ...
                    "Setting",original,"Offset",edits(1).Start-1);
            else
                if action == "override"
                    assert(shared, "yamada:AxesInspectorEdits:Share", "This setting is already independent.");
                    value = titleValue;
                else
                    assert(~shared, "yamada:AxesInspectorEdits:Share", "Unlink this setting before editing it.");
                end
                requested = yamada.source.AxesInspectorEdits.checkedValue(path,value,original);
                encoded = yamada.source.LiteralEncoder.encode(requested);
                % A format only shapes automatic tick labels, so editing it under manual labels
                % adds a call such as xtickformat that also selects automatic labels.
                companion = struct([]);
                if action == "set"
                    companion = yamada.source.AxesInspectorEdits.automaticCompanion(component,path,requested,registry,effective);
                end
                % An explicit size that a later FontSize or label call returns to automatic has
                % no effect, so a new value is written after every certain setting instead.
                if isempty(companion) && ~isempty(original) && action == "set" && isa(effective,"function_handle")
                    [~, ~, code] = effective(path);
                    if code == "automatic-text"
                        [edits, placement] = yamada.source.AxesInspectorEdits.insert( ...
                            document,component,path,encoded,requested,yamada.model.PropertySetting.empty,registry, ...
                            struct([]),true);
                        forward.Placements = placement;
                        batch = yamada.source.SourcePatchBatch(source,edits);
                        return
                    end
                end
                if ~isempty(companion)
                    [edits, placement] = yamada.source.AxesInspectorEdits.insert( ...
                        document,component,path,encoded,requested,yamada.model.PropertySetting.empty,registry,companion);
                    forward.Placements = placement;
                    [modePaths, ~, owned] = yamada.catalog.AxesSettingFunctionCatalog.effects(companion,requested);
                    paths = [path modePaths(~owned)];
                elseif isempty(original) || action == "override"
                    [edits, placement] = yamada.source.AxesInspectorEdits.insert( ...
                        document,component,path,encoded,requested,original,registry);
                    forward.Placements = placement;
                else
                    assert(original.IsCertain && original.ValueKind == "literal" && ...
                        (original.IsEditable || original.Method == "functionCall") && ~isempty(original.ValueSpan), ...
                        "yamada:AxesInspectorEdits:Ownership", "This source value cannot be replaced safely.");
                    span = original.ValueSpan;
                    before = extractBetween(source,span.StartOffset,span.EndOffset);
                    assert(~contains(before,[string(newline),string(char(13))]), ...
                        "yamada:AxesInspectorEdits:MultilineSource", "The source argument spans multiple physical lines.");
                    edits = struct("Start",span.StartOffset,"End",span.EndOffset,"Text",encoded);
                    affected = original;
                    if original.Method == "functionCall"
                        affected = component.Settings(string({component.Settings.Method}) == "functionCall");
                        affected = affected(arrayfun(@(item) isequal(item.SourceSpan,original.SourceSpan) && ...
                            isequal(item.ValueSpan,span),affected));
                        assert(all([affected.IsCertain]) && all(string({affected.ValueKind}) == "literal"));
                    end
                    paths = unique(string({affected.Path}),"stable");
                    for setting = affected
                        forward.Changes(end+1) = struct("SettingId",setting.Id,"Value",{requested});
                        inverse.Changes(end+1) = struct("SettingId",setting.Id,"Value",{setting.LiteralValue});
                    end
                end
            end
            batch = yamada.source.SourcePatchBatch(source,edits);
        end
    end

    methods (Static, Access = private)
        function [batch, requested, forward, inverse, paths] = geographicLimits(document,component,value,registry)
            % geographicLimits Replace two arguments from one owned call as a single transaction.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                value (2,2) double {mustBeReal,mustBeFinite}
                registry (1,1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                batch (1,1) yamada.source.SourcePatchBatch
                requested (2,2) double
                forward (1,1) struct
                inverse (1,1) struct
                paths (1,:) string
            end

            % Keep longitude in its supplied order to support antimeridian crossings.
            assert(all(abs(value(1,:)) <= 90) && value(1,1) <= value(1,2), ...
                "yamada:AxesInspectorEdits:LatitudeLimits","Latitude limits must be ordered and between -90 and 90.");
            paths = ["RequestedLatitudeLimits","RequestedLongitudeLimits"];
            forward = struct("Changes",struct("SettingId",{},"Value",{}), ...
                "Placements",struct("Statement",{},"Setting",{},"Offset",{}),"RemovedIds",zeros(1,0));
            inverse = forward;
            requested = value;
            latitude = component.getSettings(paths(1));
            longitude = component.getSettings(paths(2));
            encoded = [yamada.source.LiteralEncoder.encode(value(1,:)), ...
                yamada.source.LiteralEncoder.encode(value(2,:))];
            if isempty(latitude) && isempty(longitude)
                [edits, forward.Placements] = yamada.source.AxesInspectorEdits.insert( ...
                    document,component,"GeographicLimits",strjoin(encoded,", "),value,yamada.model.PropertySetting.empty,registry);
            else
                assert(~isempty(latitude) && ~isempty(longitude) && ...
                    isequal(latitude(end).SourceSpan,longitude(end).SourceSpan), ...
                    "yamada:AxesInspectorEdits:Ownership","The geographic limits do not share an owned source call.");
                settings = [latitude(end),longitude(end)];
                assert(all([settings.IsCertain]) && all(string({settings.Method}) == "functionCall"), ...
                    "yamada:AxesInspectorEdits:Ownership","The geographic limits cannot be replaced safely.");
                edits = struct("Start",{},"End",{},"Text",{});
                for index = 1:2
                    span = settings(index).ValueSpan;
                    assert(~isempty(span) && ~contains(extractBetween(document.CurrentText, ...
                        span.StartOffset,span.EndOffset),[string(newline),string(char(13))]), ...
                        "yamada:AxesInspectorEdits:MultilineSource","A geographic limit spans multiple physical lines.");
                    edits(index) = struct("Start",span.StartOffset,"End",span.EndOffset,"Text",encoded(index));
                    forward.Changes(index) = struct("SettingId",settings(index).Id,"Value",{value(index,:)});
                    inverse.Changes(index) = struct("SettingId",settings(index).Id,"Value",{settings(index).LiteralValue});
                end
            end
            batch = yamada.source.SourcePatchBatch(document.CurrentText,edits);
        end

        function [batch, requested, forward, inverse, paths] = axisStyle(document,component,value,registry)
            % axisStyle Select one aspect-ratio keyword of axis as a single reversible statement edit.
            %   The last style keyword is replaced in place, keeping its call's other
            %   keywords such as vis3d. Without one, the keyword is added before the
            %   keywords of the last call, so that a later vis3d still freezes its ratios,
            %   or a new call is written after every certain setting. Later settings that
            %   override the call's effects are left in place.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                value
                registry (1,1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                batch (1,1) yamada.source.SourcePatchBatch
                requested
                forward (1,1) struct
                inverse (1,1) struct
                paths (1,:) string
            end

            % Validate the keyword against the offered styles.
            assert(((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && ...
                any(string(value) == yamada.model.AxesInspectorProperties.axisStyles()), ...
                "yamada:AxesInspectorEdits:AxisStyle","Choose an axis style.");
            requested = string(value);
            settings = component.getSettings("AxisStyle");
            if isempty(settings)
                [batch, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.insertAxisCall(document,component,requested,registry);
                return
            end

            % Replace the last style token, or lead the last call with the new keyword.
            keywords = yamada.model.AxesInspectorProperties.axisKeywords(settings);
            styles = find(keywords ~= "vis3d");
            if isempty(styles), call = settings(end); else, call = settings(styles(end)); end
            if call.Syntax == "implicitCall"
                % normal also returns the vis3d Modes to auto, so an active vis3d follows it.
                [~, vis3d] = yamada.model.AxesInspectorProperties.axisKeywordState(settings);
                keywords = requested;
                if requested == "normal" && vis3d, keywords(end+1) = "vis3d"; end
                [batch, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.insertAxisCall(document,component,keywords,registry);
                return
            end
            [tokens, starts] = yamada.source.AxesInspectorEdits.axisCallKeywords(document,component,call,registry);
            if isempty(styles)
                tokens = [requested tokens];
            else
                tokens(starts == call.ValueSpan.StartOffset) = requested;
            end
            [batch, forward, inverse, paths] = ...
                yamada.source.AxesInspectorEdits.rewriteAxisCall(document,component,call,tokens,registry);
        end

        function [batch, requested, forward, inverse, paths] = axisVis3d(document,component,value,registry)
            % axisVis3d Add or remove the vis3d keyword of the last axis call.
            %   Turning it on appends vis3d to the keywords of the last call, as in
            %   axis(app.UIAxes,"equal","vis3d"), or writes axis(app.UIAxes,"vis3d").
            %   Turning it off removes the vis3d keywords after the last normal, and
            %   removes a call that has no other keyword.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                value
                registry (1,1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                batch (1,1) yamada.source.SourcePatchBatch
                requested
                forward (1,1) struct
                inverse (1,1) struct
                paths (1,:) string
            end

            % Validate the toggle against the current keyword state.
            assert(isscalar(value) && (islogical(value) || isnumeric(value)) && any(double(value) == [0 1]), ...
                "yamada:AxesInspectorEdits:AxisVis3d","Choose whether vis3d applies.");
            requested = logical(value);
            settings = component.getSettings("AxisStyle");
            [~, active, indices] = yamada.model.AxesInspectorProperties.axisKeywordState(settings);
            assert(active ~= requested, "yamada:AxesInspectorEdits:AxisVis3d","The vis3d keyword is already in this state.");
            if requested && isempty(settings)
                [batch, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.insertAxisCall(document,component,"vis3d",registry);
                return
            end

            % An inferred-target call is superseded by a new explicit call after it.
            if requested && settings(end).Syntax == "implicitCall"
                [batch, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.insertAxisCall(document,component,"vis3d",registry);
                return
            end
            if ~requested && any([settings(indices).Syntax] == "implicitCall")
                % Only normal returns the vis3d Modes to auto, so the style is restated after it.
                style = yamada.model.AxesInspectorProperties.axisKeywordState(settings);
                keywords = "normal";
                if style ~= "normal", keywords(end+1) = style; end
                [batch, forward, inverse, paths] = ...
                    yamada.source.AxesInspectorEdits.insertAxisCall(document,component,keywords,registry);
                return
            end

            % Edit the keywords of one call; vis3d from several calls is left as source.
            if requested
                call = settings(end);
                tokens = yamada.source.AxesInspectorEdits.axisCallKeywords(document,component,call,registry);
                tokens(end+1) = "vis3d";
            else
                calls = settings(indices);
                call = calls(end);
                assert(all(arrayfun(@(setting) isequal(setting.SourceSpan,call.SourceSpan),calls)), ...
                    "yamada:AxesInspectorEdits:Ownership","The vis3d keyword is set by several axis calls.");
                [tokens, starts] = yamada.source.AxesInspectorEdits.axisCallKeywords(document,component,call,registry);
                removed = arrayfun(@(setting) setting.ValueSpan.StartOffset,calls);
                tokens = tokens(~ismember(starts,removed));
            end
            [batch, forward, inverse, paths] = ...
                yamada.source.AxesInspectorEdits.rewriteAxisCall(document,component,call,tokens,registry);
        end

        function [batch, forward, inverse, paths] = insertAxisCall(document,component,keywords,registry)
            % insertAxisCall Write a new axis call with the given keywords after every certain setting.
            %   Several keywords, as in axis(app.UIAxes,"normal","vis3d"), have their
            %   effects rebuilt from the catalog forms of the whole keyword list.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                keywords (1,:) string {mustBeNonempty}
                registry (1,1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                batch (1,1) yamada.source.SourcePatchBatch
                forward (1,1) struct
                inverse (1,1) struct
                paths (1,:) string
            end

            % Validate every keyword against the loaded release before writing.
            for keyword = keywords
                yamada.source.AxesInspectorEdits.axisForm(component,keyword,registry);
            end
            form = yamada.source.AxesInspectorEdits.axisForm(component,keywords(1),registry);
            forward = struct("Changes",struct("SettingId",{},"Value",{}), ...
                "Placements",struct("Statement",{},"Setting",{},"Offset",{}),"RemovedIds",zeros(1,0));
            inverse = forward;
            encoded = strjoin(arrayfun(@(keyword) yamada.source.LiteralEncoder.encode(keyword),keywords),", ");
            [edits, forward.Placements] = yamada.source.AxesInspectorEdits.insert(document,component, ...
                "AxisStyle",encoded,keywords(1),yamada.model.PropertySetting.empty,registry,form);

            % Rebuild the effects of a keyword list from the inserted statement.
            if numel(keywords) > 1
                placement = forward.Placements;
                [~, ~, tokens, spans, forms] = yamada.source.PropertySettingSyntax.axesCall(placement.Statement,registry);
                [effectPaths, values, used, owned, elements] = yamada.catalog.AxesSettingFunctionCatalog.match( ...
                    forms,component.Factory,tokens,false);
                assert(~isempty(effectPaths),"yamada:AxesInspectorEdits:AxisStyle","This axis style is unavailable in the loaded release.");
                [ownedSpans, editable] = yamada.source.AxesSettingPlacement.ownership( ...
                    component.Factory,effectPaths,owned,used,tokens,spans,elements);
                template = placement.Setting(1);
                created = yamada.model.PropertySetting.empty;
                for effect = 1:numel(effectPaths)
                    location = struct("Method","functionCall","Syntax","call","SourceSpan",template.SourceSpan, ...
                        "ValueSpan",ownedSpans{effect},"SourceSnapshotId",template.SourceSnapshotId,"IsEditable",editable(effect));
                    setting = yamada.model.PropertySetting(effectPaths(effect),values{effect},location);
                    created(end+1) = setting.withScope(template.OwnerMethod,template.ScopeSpan); %#ok<AGROW>
                end
                forward.Placements.Setting = created;
            end
            paths = string({forward.Placements.Setting.Path});
            batch = yamada.source.SourcePatchBatch(document.CurrentText,edits);
        end

        function [tokens, starts] = axisCallKeywords(document,component,call,registry)
            % axisCallKeywords Return the keywords of an explicit-target axis call and their offsets.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                call (1,1) yamada.model.PropertySetting
                registry (1,1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                tokens (1,:) string
                starts (1,:) double
            end

            % Only a certain call with an explicit target owns replaceable keywords.
            assert(call.IsCertain && call.Method == "functionCall" && ~isempty(call.ValueSpan), ...
                "yamada:AxesInspectorEdits:Ownership","This axis call cannot be replaced safely.");
            statement = yamada.source.AxesInspectorEdits.callStatement(document,call);
            [~, target, raw, spans] = yamada.source.PropertySettingSyntax.axesCall(statement,registry);
            receiver = "app." + document.sourceComponentName(component.Id);
            assert(target == document.sourceComponentName(component.Id) && ...
                startsWith(statement.Text,regexpPattern("axis\s*\(\s*" + regexptranslate("escape",receiver) + "\s*,")), ...
                "yamada:AxesInspectorEdits:Ownership","An axis call without its explicit target is read-only.");
            tokens = strings(1,numel(raw));
            for index = 1:numel(raw)
                [value, safe] = yamada.source.MatlabLiteralParser.parse(raw(index));
                assert(safe && ((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))), ...
                    "yamada:AxesInspectorEdits:Ownership","This axis call cannot be replaced safely.");
                tokens(index) = string(value);
            end
            starts = [spans.StartOffset];
        end

        function [batch, forward, inverse, paths] = rewriteAxisCall(document,component,call,tokens,registry)
            % rewriteAxisCall Replace the keyword list of one axis call as a reversible statement edit.
            %   The call keeps its place, receiver and quote style; its implied effects
            %   are rebuilt from the catalog forms of the new keywords. A call left
            %   without keywords is removed with the line it vacates.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                call (1,1) yamada.model.PropertySetting
                tokens (1,:) string
                registry (1,1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                batch (1,1) yamada.source.SourcePatchBatch
                forward (1,1) struct
                inverse (1,1) struct
                paths (1,:) string
            end

            forward = struct("Changes",struct("SettingId",{},"Value",{}), ...
                "Placements",struct("Statement",{},"Setting",{},"Offset",{}),"RemovedIds",zeros(1,0));
            inverse = forward;
            source = document.CurrentText;
            statement = yamada.source.AxesInspectorEdits.callStatement(document,call);
            [~, ~, raw, spans] = yamada.source.PropertySettingSyntax.axesCall(statement,registry);
            old = component.Settings(arrayfun(@(setting) isequal(setting.SourceSpan,call.SourceSpan),component.Settings));
            forward.RemovedIds = [old.Id];
            anchor = call.SourceSpan.StartOffset - 1;

            % Remove a call without keywords together with the line it vacates.
            if isempty(tokens)
                edits = yamada.source.SourceFormatting.cleanDeletions(source, ...
                    struct("Start",call.SourceSpan.StartOffset,"End",call.SourceSpan.EndOffset,"Text",""));
                batch = yamada.source.SourcePatchBatch(source,edits);
                inverse.Placements = struct("Statement",statement,"Setting",old,"Offset",edits(1).Start-1);
                paths = unique(string({old.Path}),"stable");
                return
            end

            % Encode the keywords in the quote style of the call's first keyword.
            encoded = strings(size(tokens));
            for index = 1:numel(tokens)
                yamada.source.AxesInspectorEdits.axisForm(component,tokens(index),registry);
                if startsWith(raw(1),"'"), encoded(index) = yamada.source.LiteralEncoder.encode(char(tokens(index)));
                else, encoded(index) = yamada.source.LiteralEncoder.encode(tokens(index)); end
            end
            text = strjoin(encoded,", ");
            first = spans(1).StartOffset;
            last = spans(end).EndOffset;
            batch = yamada.source.SourcePatchBatch(source,struct("Start",first,"End",last,"Text",text));

            % Rebuild the statement in post-edit coordinates with the new keywords' effects.
            offsets = statement.CodeOffsets;
            head = find(offsets == first,1);
            tail = find(offsets == last,1);
            assert(isscalar(head) && isscalar(tail));
            delta = strlength(text) - (last - first + 1);
            newText = extractBefore(statement.Text,head) + text + extractAfter(statement.Text,tail);
            newOffsets = [offsets(1:head-1), first + (0:strlength(text)-1), offsets(tail+1:end) + delta];
            sourceSpan = yamada.model.SourceSpan(call.SourceSpan.StartOffset,call.SourceSpan.EndOffset + delta);
            replaced = yamada.source.SourceStatement(newText,sourceSpan,newOffsets);
            [~, ~, newTokens, newSpans, forms] = yamada.source.PropertySettingSyntax.axesCall(replaced,registry);
            [effectPaths, values, used, owned, elements] = yamada.catalog.AxesSettingFunctionCatalog.match( ...
                forms,component.Factory,newTokens,false);
            assert(~isempty(effectPaths),"yamada:AxesInspectorEdits:AxisStyle","This axis style is unavailable in the loaded release.");
            [ownedSpans, editable] = yamada.source.AxesSettingPlacement.ownership( ...
                component.Factory,effectPaths,owned,used,newTokens,newSpans,elements);
            snapshot = "";
            if isfield(document.Metadata,"SourceSnapshotId"), snapshot = document.Metadata.SourceSnapshotId; end
            analysis = document.sourceAnalysis();
            method = analysis.Layout.Methods(string({analysis.Layout.Methods.Name}) == call.OwnerMethod);
            assert(isscalar(method));
            [scope, valid] = batch.mapSpan(method.Span);
            assert(valid);
            created = yamada.model.PropertySetting.empty;
            for effect = 1:numel(effectPaths)
                location = struct("Method","functionCall","Syntax","call","SourceSpan",sourceSpan, ...
                    "ValueSpan",ownedSpans{effect},"SourceSnapshotId",snapshot,"IsEditable",editable(effect));
                setting = yamada.model.PropertySetting(effectPaths(effect),values{effect},location);
                created(end+1) = setting.withScope(call.OwnerMethod,scope); %#ok<AGROW>
            end
            forward.Placements = struct("Statement",replaced,"Setting",created,"Offset",anchor);
            inverse.Placements = struct("Statement",statement,"Setting",old,"Offset",anchor);
            paths = unique([string({old.Path}) string({created.Path})],"stable");
        end

        function statement = callStatement(document,call)
            % callStatement Return the one analyzed statement of a recorded call.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                call (1,1) yamada.model.PropertySetting
            end
            arguments (Output)
                statement (1,1) yamada.source.SourceStatement
            end
            analysis = document.sourceAnalysis();
            index = analysis.statementIndices(call.SourceSpan);
            assert(isscalar(index),"yamada:AxesInspectorEdits:Ownership","This axis call cannot be replaced safely.");
            statement = analysis.Statements(index);
        end

        function form = axisForm(component,keyword,registry)
            % axisForm Return the reviewed axis form of one keyword in the loaded release.
            arguments (Input)
                component (1,1) yamada.model.ComponentRecord
                keyword (1,1) string
                registry (1,1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                form (1,1) struct
            end
            form = yamada.catalog.AxesSettingFunctionCatalog.formById("axis." + keyword,registry);
            assert(isscalar(form) && any(string(form.targetFactories) == component.Factory), ...
                "yamada:AxesInspectorEdits:AxisStyle","This axis style is unavailable in the loaded release.");
        end

        function result = checkedValue(path,value,original)
            % checkedValue Validate Inspector inputs and preserve text representation where possible.
            arguments (Input)
                path (1,1) string
                value
                original yamada.model.PropertySetting
            end
            arguments (Output)
                result
            end

            member = extractAfter(path,".");
            if any(path == ["TickLabelFormat","Colormap"]), member = path; end
            switch member
                case "String"
                    lines = string(value);
                    assert(isvector(lines) && ~any(ismissing(lines)), ...
                        "yamada:AxesInspectorEdits:Text", "Enter valid text lines.");
                    if isempty(original)
                        value = reshape(lines,1,[]);
                    elseif ischar(original.LiteralValue)
                        if isscalar(lines)
                            value = char(lines);
                        elseif ~isrow(original.LiteralValue)
                            value = char(lines);
                        else
                            value = cellstr(reshape(lines,1,[]));
                        end
                    elseif iscell(original.LiteralValue)
                        value = reshape(cellstr(lines),1,[]);
                    else
                        value = reshape(lines,1,[]);
                    end
                case "Color"
                    try
                        value = validatecolor(value);
                    catch
                        error("yamada:AxesInspectorEdits:Color","Enter a MATLAB color name, hex code, or RGB triplet.");
                    end
                case "FontName"
                    value = string(value);
                    assert(isscalar(value) && ~ismissing(value) && strlength(value)>0, ...
                        "yamada:AxesInspectorEdits:FontName", "Enter one font name.");
                case "FontSize"
                    assert(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && value > 0, ...
                        "yamada:AxesInspectorEdits:FontSize", "Enter a positive font size.");
                case "FontWeight"
                    value = string(validatestring(value,["normal","bold"]));
                case "FontAngle"
                    value = string(validatestring(value,["normal","italic"]));
                case "Interpreter"
                    value = string(validatestring(value,["tex","latex","none"]));
                case "Colormap"
                    assert(isa(value,"double") && ismatrix(value) && isreal(value) && ...
                        ~isempty(value) && size(value,2) == 3 && all(isfinite(value(:))) && ...
                        all(value(:) >= 0 & value(:) <= 1), ...
                        "yamada:AxesInspectorEdits:Colormap","Choose a colormap with RGB values between zero and one.");
                case {"Exponent","TickLabelRotation"}
                    assert(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value), ...
                        "yamada:AxesInspectorEdits:RulerNumber", "Enter a finite number.");
                    if member == "Exponent"
                        assert(value == fix(value), "yamada:AxesInspectorEdits:RulerExponent", "Enter an integer exponent.");
                    end
                case "SecondaryLabel.String"
                    value = string(value);
                    assert(isscalar(value) && ~ismissing(value), ...
                        "yamada:AxesInspectorEdits:RulerSecondaryLabel", "Enter one secondary label.");
                    if ~isempty(original) && ischar(original.LiteralValue), value = char(value); end
                case "TickLabelFormat"
                    if path == "TickLabelFormat"
                        value = string(validatestring(value,yamada.model.AxesInspectorProperties.formats()));
                    else
                        value = string(value);
                        assert(isscalar(value) && ~ismissing(value) && strlength(value)>0, ...
                            "yamada:AxesInspectorEdits:RulerFormat", "Enter one tick label format.");
                        if ~isempty(original) && ischar(original.LiteralValue), value = char(value); end
                    end
            end
            result = value;
        end

        function form = automaticCompanion(component,path,value,registry,effective)
            % automaticCompanion Return the call that also selects a manual value's automatic Mode.
            %   The catalog companion form names the Mode it implies; the form is returned only
            %   while that Mode's effective value differs from it or is unknown.
            arguments (Input)
                component (1,1) yamada.model.ComponentRecord
                path (1,1) string
                value
                registry (1,1) yamada.model.ComponentRegistry
                effective = []
            end
            arguments (Output)
                form struct
            end

            form = struct([]);
            if strlength(registry.CatalogRoot) == 0, return, end
            catalog = yamada.catalog.AxesSettingFunctionCatalog.formsWritingPath(component.Factory,path,registry);
            for item = catalog
                candidate = item{1};
                if ~isfield(candidate,"companionInsertion") || ~candidate.companionInsertion, continue, end
                [paths, values, owned] = yamada.catalog.AxesSettingFunctionCatalog.effects(candidate,value);
                selected = false;
                for effect = find(~owned)
                    if isa(effective,"function_handle")
                        [current, known] = effective(paths(effect));
                    else
                        settings = component.getSettings(paths(effect));
                        known = true; current = values{effect};
                        if ~isempty(settings), current = settings(end).LiteralValue; end
                    end
                    selected = selected || ~known || ...
                        ~yamada.catalog.AxesSettingFunctionCatalog.sameLiteral(current,values{effect});
                end
                if selected
                    form = yamada.catalog.AxesSettingFunctionCatalog.insertionForm(component.Factory,path,value,registry, ...
                        struct("Path",num2cell(paths(~owned)),"Value",values(~owned)));
                    return
                end
            end
        end

        function [edit, placement] = insert(document,component,path,encoded,value,original,registry,companion,afterAll)
            % insert Emit one setting beside a proven initialization statement.
            %   A companion form is written after every certain setting, which includes the
            %   manual values that it returns to automatic. afterAll writes an assignment
            %   there, after the settings that would otherwise override it.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                path (1,1) string
                encoded (1,1) string
                value
                original yamada.model.PropertySetting
                registry (1,1) yamada.model.ComponentRegistry
                companion struct = struct([])
                afterAll (1,1) logical = false
            end
            arguments (Output)
                edit (1,1) struct
                placement (1,1) struct
            end
            span = component.SourceSpans.Creation;
            assert(~isempty(span) && isfield(component.Metadata,"InitializationCreationCertain") && ...
                component.Metadata.InitializationCreationCertain, ...
                "yamada:AxesInspectorEdits:Creation", "A unique initialization statement is required.");
            if ~isempty(original)
                span = original.SourceSpan;
            else
                settings = component.Settings;
                certain = settings([settings.IsCertain] & string({settings.Method}) ~= "nameValue");
                if ~isempty(certain), span = certain(end).SourceSpan; end
            end
            source = document.CurrentText;
            analysis = document.sourceAnalysis();
            receiver = "app." + component.Name;
            snapshot = "";
            if isfield(document.Metadata,"SourceSnapshotId"), snapshot = document.Metadata.SourceSnapshotId; end

            % A dependent setting follows its main path: an option joins the main call.
            form = companion;
            if isempty(form) && isempty(original) && path ~= "GeographicLimits" && ~afterAll
                [main, groupForm] = yamada.catalog.AxesSettingFunctionCatalog.settingGroup(component.Factory,path,registry);
                mainSettings = yamada.model.PropertySetting.empty;
                if ~isempty(main), mainSettings = component.getSettings(main); end
                if ~isempty(mainSettings) && mainSettings(end).Method == "functionCall"
                    [edit, merged, callEnd] = yamada.source.AxesSettingPlacement.optionMerge( ...
                        document,component,path,value,groupForm,registry);
                    if ~isempty(edit)
                        placement = struct("Statement",yamada.source.SourceStatement.empty, ...
                            "Setting",merged,"Offset",callEnd);
                        return
                    end
                end
                % Without a main setting, a reviewed call form precedes an assignment unless a local method shadows it.
                if isempty(mainSettings)
                    form = yamada.source.AxesSettingPlacement.callForm(component.Factory,path,value,registry);
                    if ~isempty(form) && any(string({analysis.Layout.Methods.Name}) == string(form.name))
                        form = struct([]);
                    end
                end
            end
            index = analysis.statementIndices(span);
            assert(isscalar(index));
            owner = analysis.Layout.Owner(index);
            method = analysis.Layout.Methods(string({analysis.Layout.Methods.Name}) == owner);
            assert(isscalar(method));
            suffix = "";
            syntax = "assignment";
            name = "";
            if ~isempty(form)
                name = string(form.name);
                [prefix, suffix] = yamada.source.AxesSettingPlacement.callText(form,receiver);
                syntax = "functionCall";
            elseif isempty(original) && path == "GeographicLimits"
                name = "geolimits";
                prefix = name + "(" + receiver + ", ";
                suffix = ")";
                syntax = "functionCall";
            else
                prefix = receiver + "." + path + " = ";
            end
            if syntax == "functionCall"
                assert(~any(string({analysis.Layout.Methods.Name}) == name), ...
                    "yamada:AxesInspectorEdits:ShadowedFunction", "A local method shadows this axes function.");
            end

            raw = prefix + encoded + suffix;
            statement = raw + ";";
            % Keep a trailing comment attached to its original statement.
            % A statement without a terminator ends at its line, so its span can include the CR.
            last = span.EndOffset;
            if last > 0 && extractBetween(source,last,last) == sprintf('\r'), last = last - 1; end
            tail = char(extractAfter(source,last));
            lineBreak = regexp(tail,'\r?\n','start','once');
            offset = last;
            ending = string(newline);
            if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
            if ~isempty(lineBreak)
                rest = string(tail(1:lineBreak-1));
                if strlength(strtrim(rest)) == 0 || startsWith(strtrim(rest),"%")
                    offset = offset + lineBreak - 1;
                    statement = ending + yamada.source.SourceFormatting.indent(source,span.StartOffset) + statement;
                else
                    statement = " " + statement;
                end
            else
                statement = " " + statement;
            end
            edit = struct("Start",offset+1,"End",offset,"Text",statement);
            first = offset + strlength(statement) - strlength(raw);
            sourceSpan = yamada.model.SourceSpan(first,first + strlength(raw));
            indexed = yamada.source.SourceStatement(raw,sourceSpan,first + (0:strlength(raw)-1));
            if syntax == "assignment"
                setting = yamada.source.PropertySettingSyntax.assignment(indexed,snapshot,0);
            elseif path == "GeographicLimits"
                % Bind each argument span to the same inserted call.
                latitudeLength = strlength(yamada.source.LiteralEncoder.encode(value(1,:)));
                latitudeStart = first + strlength(prefix);
                longitudeStart = latitudeStart + latitudeLength + 2;
                spans = [yamada.model.SourceSpan(latitudeStart,latitudeStart+latitudeLength-1), ...
                    yamada.model.SourceSpan(longitudeStart,first+strlength(raw)-2)];
                paths = ["RequestedLatitudeLimits","RequestedLongitudeLimits"];
                setting = yamada.model.PropertySetting.empty;
                for index = 1:2
                    location = struct("Method","functionCall","Syntax","call","SourceSpan",sourceSpan, ...
                        "ValueSpan",spans(index),"SourceSnapshotId",snapshot,"IsEditable",false);
                    setting(index) = yamada.model.PropertySetting(paths(index),value(index,:),location);
                end
            else
                valueFirst = first + strlength(prefix);
                setting = yamada.source.AxesSettingPlacement.callSettings(component.Factory,form,value,path, ...
                    sourceSpan,yamada.model.SourceSpan(valueFirst,valueFirst+strlength(encoded)-1),snapshot);
            end
            batch = yamada.source.SourcePatchBatch(source,edit);
            [scope, valid] = batch.mapSpan(method.Span);
            assert(valid);
            for index = 1:numel(setting)
                setting(index) = setting(index).withScope(owner,scope);
            end
            placement = struct("Statement",indexed,"Setting",setting,"Offset",offset);
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
