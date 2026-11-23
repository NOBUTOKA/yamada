classdef AxesSettingPlacement
    % AxesSettingPlacement Decide how axes settings are written to source.
    %   Applies one priority for every axes family setting:
    %   1. An existing owned value is replaced where it was written.
    %   2. A dependent setting of a group, such as Title.Color, follows the
    %      method of its main path, adding a call option where one exists.
    %   3. Otherwise a reviewed single-path call form is preferred over
    %      constructor arguments and assignments.
    %   The class also defines which recognized call effects own a token.
    %
    %   Example:
    %       form = yamada.source.AxesSettingPlacement.callForm( ...
    %           "uiaxes", "XLim", [0 1], registry.CatalogRoot);

    methods (Static)
        function [valueSpans, editable] = ownership(factory, paths, owned, argumentsUsed, tokens, spans)
            % ownership Return each call effect's value token and whether it is replaceable in place.
            %   An implied literal effect owns no token. An owned effect is replaceable only
            %   when its single-line token belongs to it alone and no specialized Inspector
            %   editor owns the path.
            arguments (Input)
                factory (1, 1) string
                paths (1, :) string
                owned (1, :) logical
                argumentsUsed (1, :) double
                tokens (1, :) string
                spans yamada.model.SourceSpan
            end
            arguments (Output)
                valueSpans cell
                editable (1, :) logical
            end

            count = numel(paths);
            valueSpans = cell(1, count);
            editable = false(1, count);
            specialized = [yamada.model.AxesInspectorProperties.paths(factory), ...
                "RequestedLatitudeLimits", "RequestedLongitudeLimits"];
            for effect = 1:count
                if ~owned(effect), valueSpans{effect} = yamada.model.SourceSpan.empty; continue, end
                argument = argumentsUsed(effect);
                valueSpans{effect} = spans(argument);
                shared = nnz(owned & argumentsUsed == argument) > 1;
                multiline = contains(tokens(argument), [string(newline), string(char(13))]);
                editable(effect) = ~shared && ~multiline && ~any(specialized == paths(effect));
            end
        end

        function form = callForm(factory, path, value, root)
            % callForm Return the reviewed call form preferred for a new setting, or an empty struct.
            arguments (Input)
                factory (1, 1) string
                path (1, 1) string
                value
                root (1, 1) string
            end
            arguments (Output)
                form struct
            end

            form = struct([]);
            if ~any(factory == ["axes", "uiaxes", "polaraxes", "geoaxes"]) || strlength(root) == 0, return, end
            form = yamada.catalog.AxesSettingFunctionCatalog.insertionForm(factory, path, value, root);
        end

        function [prefix, suffix] = callText(form, receiver)
            % callText Return the text around the encoded argument of an inserted call.
            arguments (Input)
                form (1, 1) struct
                receiver (1, 1) string
            end
            arguments (Output)
                prefix (1, 1) string
                suffix (1, 1) string
            end
            prefix = string(form.name) + "(" + receiver + ", ";
            suffix = ")";
        end

        function settings = callSettings(factory, form, value, path, sourceSpan, valueSpan, snapshot)
            % callSettings Build the owned and implied occurrences of one inserted call.
            arguments (Input)
                factory (1, 1) string
                form (1, 1) struct
                value
                path (1, 1) string
                sourceSpan (1, 1) yamada.model.SourceSpan
                valueSpan (1, 1) yamada.model.SourceSpan
                snapshot (1, 1) string
            end
            arguments (Output)
                settings yamada.model.PropertySetting
            end

            [paths, values, owned] = yamada.catalog.AxesSettingFunctionCatalog.effects(form, value);
            [~, editable] = yamada.source.AxesSettingPlacement.ownership(factory, paths, owned, ...
                ones(size(paths)), "", valueSpan);
            settings = yamada.model.PropertySetting.empty;
            for effect = 1:numel(paths)
                location = struct("Method", "functionCall", "Syntax", "call", "SourceSpan", sourceSpan, ...
                    "SourceSnapshotId", snapshot, "IsEditable", false);
                if owned(effect)
                    location.ValueSpan = valueSpan;
                    location.IsEditable = editable(effect) && paths(effect) == path;
                end
                settings(end + 1) = yamada.model.PropertySetting(paths(effect), values{effect}, location); %#ok<AGROW>
            end
        end

        function [edit, settings, callEnd] = optionMerge(document, component, path, value, form, root)
            % optionMerge Add one option to an existing call of the main path's function.
            %   The last certain call that declares the option exactly is preferred; earlier
            %   calls of the same function follow. An empty edit means no call can hold it.
            %   callEnd is the end of the extended call statement before the edit.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                path (1, 1) string
                value
                form (1, 1) struct
                root (1, 1) string
            end
            arguments (Output)
                edit struct
                settings yamada.model.PropertySetting
                callEnd (1, 1) double
            end

            edit = struct("Start", {}, "End", {}, "Text", {});
            settings = yamada.model.PropertySetting.empty;
            callEnd = 0;
            calls = component.Settings(string({component.Settings.Method}) == "functionCall" & [component.Settings.IsCertain]);
            if isempty(calls), return, end
            analysis = document.sourceAnalysis();
            source = document.CurrentText;
            % Visit each owned call statement once, from the latest to the earliest.
            starts = arrayfun(@(item) item.SourceSpan.StartOffset, calls);
            [~, first] = unique(starts, "last");
            calls = calls(sort(first, "descend"));
            for call = calls
                index = analysis.statementIndices(call.SourceSpan);
                if ~isscalar(index), continue, end
                statement = analysis.Statements(index);
                [name, target, tokens, spans, forms] = yamada.source.PropertySettingSyntax.axesCall(statement, root);
                if name ~= string(form.name) || target ~= document.sourceComponentName(component.Id) || isempty(spans)
                    continue
                end
                matched = yamada.source.AxesSettingPlacement.matchedForm(forms, component.Factory, tokens);
                if isempty(matched), continue, end
                option = yamada.catalog.AxesSettingFunctionCatalog.optionName(matched, path);
                if strlength(option) == 0, continue, end
                same = component.Settings(arrayfun(@(item) isequal(item.SourceSpan, call.SourceSpan), component.Settings));
                if any(string({same.Path}) == path), continue, end

                % Follow the call's existing option syntax and keep its trailing trivia.
                encoded = yamada.source.LiteralEncoder.encode(value);
                if any(~cellfun(@isempty, regexp(cellstr(tokens), '^[A-Za-z]\w*\s*=', 'once')))
                    pair = option + "=" + encoded;
                    valueOffset = strlength(option + "=");
                else
                    pair = yamada.source.LiteralEncoder.encode(option) + ", " + encoded;
                    valueOffset = strlength(yamada.source.LiteralEncoder.encode(option) + ", ");
                end
                offset = spans(end).EndOffset;
                inserted = ", " + pair;
                edit = struct("Start", offset + 1, "End", offset, "Text", inserted);
                batch = yamada.source.SourcePatchBatch(source, edit);
                [span, valid] = batch.mapSpan(call.SourceSpan);
                assert(valid, "yamada:AxesSettingPlacement:Ownership", "The call range cannot hold a new option.");
                valueFirst = offset + strlength(", ") + valueOffset + 1;
                location = struct("Method", "functionCall", "Syntax", "call", "SourceSpan", span, ...
                    "ValueSpan", yamada.model.SourceSpan(valueFirst, valueFirst + strlength(encoded) - 1), ...
                    "SourceSnapshotId", call.SourceSnapshotId, "IsEditable", false);
                setting = yamada.model.PropertySetting(path, value, location);
                [scope, valid] = batch.mapSpan(call.ScopeSpan);
                assert(valid);
                settings = setting.withScope(call.OwnerMethod, scope);
                callEnd = call.SourceSpan.EndOffset;
                return
            end
        end

        function form = matchedForm(forms, factory, tokens)
            % matchedForm Return the unique catalog form that recognized a call's tokens.
            arguments (Input)
                forms cell
                factory (1, 1) string
                tokens (1, :) string
            end
            arguments (Output)
                form struct
            end

            form = struct([]);
            for item = forms
                candidate = item{1};
                if isempty(yamada.catalog.AxesSettingFunctionCatalog.match({candidate}, factory, tokens, false)), continue, end
                if ~isempty(form), form = struct([]); return, end
                form = candidate;
            end
        end

        function result = isImplied(entry)
            % isImplied Identify a value implied by a recognized call without a token of its own.
            %   Such a value is superseded by a new setting after the call instead of a rewrite.
            arguments (Input)
                entry yamada.model.PropertyEntry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = isscalar(entry) && isfield(entry.Metadata, "SettingMethod") && ...
                entry.Metadata.SettingMethod == "functionCall" && isfield(entry.Metadata, "ValueSpan") && ...
                isempty(entry.Metadata.ValueSpan);
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
