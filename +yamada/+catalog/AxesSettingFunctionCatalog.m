classdef AxesSettingFunctionCatalog
    % AxesSettingFunctionCatalog Match release-specific axes setting call forms.
    %   Decodes only inert literals. Each effect identifies its source argument;
    %   callers retain statement ownership and decide when the target is certain.

    methods (Static)
        function forms = forName(name, root)
            % forName Look up the exact function name in the packaged catalog.
            arguments (Input)
                name (1, 1) string
                root (1, 1) string
            end
            arguments (Output)
                forms cell
            end

            catalog = yamada.catalog.AxesSettingFunctionCatalog.index(root);
            forms = {};
            if isKey(catalog.ByName, name), forms = catalog.ByName{name}; end
        end

        function form = formById(id, root)
            % formById Return one packaged call form, or an empty struct when the release lacks it.
            arguments (Input)
                id (1, 1) string
                root (1, 1) string
            end
            arguments (Output)
                form struct
            end

            catalog = yamada.catalog.AxesSettingFunctionCatalog.index(root);
            form = struct([]);
            if isKey(catalog.ById, id), form = catalog.ById{id}; end
        end

        function elements = elementSlice(factory, path, current, root)
            % elementSlice Return the slice of a vector argument that one path owns.
            %   current is the whole decoded argument. The result is empty when no
            %   element effect of a form for the factory accepts it for the path.
            arguments (Input)
                factory (1, 1) string
                path (1, 1) string
                current
                root (1, 1) string
            end
            arguments (Output)
                elements (1, :) double
            end

            elements = zeros(1, 0);
            catalog = yamada.catalog.AxesSettingFunctionCatalog.index(root);
            for item = values(catalog.ById)'
                form = item{1};
                if ~any(string(form.targetFactories) == factory), continue, end
                args = yamada.catalog.AxesSettingFunctionCatalog.records(form.arguments);
                for effect = yamada.catalog.AxesSettingFunctionCatalog.records(form.effects)
                    effect = effect{1}; %#ok<FXSET>
                    if ~isfield(effect, "elements") || string(effect.path) ~= path, continue, end
                    spec = args{cellfun(@(argument) string(argument.id) == string(effect.argument), args)};
                    if yamada.catalog.AxesSettingFunctionCatalog.accepts(spec, current)
                        elements = reshape(double(effect.elements), 1, []);
                        return
                    end
                end
            end
        end

        function form = insertionForm(factory, path, value, root, requested)
            % insertionForm Select the reviewed call form that writes one new value for a property.
            %   An insertion form's implied effects match a plain assignment. A companion
            %   form, such as xlim(ax,"padded"), is used only when every value it implies,
            %   here XLimMode "auto", is requested in the same edit.
            arguments (Input)
                factory (1, 1) string
                path (1, 1) string
                value
                root (1, 1) string
                requested struct = struct("Path", {}, "Value", {})
            end
            arguments (Output)
                form struct
            end

            catalog = yamada.catalog.AxesSettingFunctionCatalog.index(root);
            form = struct([]);
            key = factory + " " + path;
            if isKey(catalog.Insertion, key)
                candidate = catalog.ById{catalog.Insertion(key)};
            elseif isKey(catalog.Companion, key)
                candidate = catalog.ById{catalog.Companion(key)};
                [paths, values, owned] = yamada.catalog.AxesSettingFunctionCatalog.effects(candidate, value);
                requestedPaths = string({requested.Path});
                for effect = find(~owned)
                    match = find(requestedPaths == paths(effect), 1);
                    if isempty(match) || ~yamada.catalog.AxesSettingFunctionCatalog.sameLiteral( ...
                            requested(match).Value, values{effect})
                        return
                    end
                end
            else
                return
            end
            args = yamada.catalog.AxesSettingFunctionCatalog.records(candidate.arguments);
            if yamada.catalog.AxesSettingFunctionCatalog.accepts(args{1}, value), form = candidate; end
        end

        function paths = automaticPaths(factory, path, root)
            % automaticPaths Return the explicit values a call owning a path returns to automatic.
            arguments (Input)
                factory (1, 1) string
                path (1, 1) string
                root (1, 1) string
            end
            arguments (Output)
                paths (1, :) string
            end

            paths = strings(1, 0);
            if strlength(root) == 0, return, end
            catalog = yamada.catalog.AxesSettingFunctionCatalog.index(root);
            key = factory + " " + path;
            if isKey(catalog.Automatic, key), paths = catalog.Automatic{key}; end
        end

        function forms = formsWritingPath(factory, path, root)
            % formsWritingPath Return the call forms for a factory whose argument owns a path.
            arguments (Input)
                factory (1, 1) string
                path (1, 1) string
                root (1, 1) string
            end
            arguments (Output)
                forms cell
            end

            forms = {};
            catalog = yamada.catalog.AxesSettingFunctionCatalog.index(root);
            key = factory + " " + path;
            if isKey(catalog.Companion, key), forms{end + 1} = catalog.ById{catalog.Companion(key)}; end
            if isKey(catalog.Insertion, key), forms{end + 1} = catalog.ById{catalog.Insertion(key)}; end
        end

        function result = sameLiteral(left, right)
            % sameLiteral Compare decoded literals, treating character vectors and strings alike.
            arguments (Input)
                left
                right
            end
            arguments (Output)
                result (1, 1) logical
            end

            text = @(value) (ischar(value) && (isrow(value) || isempty(value))) || (isstring(value) && isscalar(value));
            if text(left) && text(right)
                result = string(left) == string(right);
            else
                result = isequaln(left, right);
            end
        end

        function [main, form] = settingGroup(factory, path, root)
            % settingGroup Return the main path and call form whose option owns a dependent path.
            %   A group exists only where the dependent setting is meaningless without its main path.
            arguments (Input)
                factory (1, 1) string
                path (1, 1) string
                root (1, 1) string
            end
            arguments (Output)
                main string
                form struct
            end

            catalog = yamada.catalog.AxesSettingFunctionCatalog.index(root);
            main = strings(1, 0);
            form = struct([]);
            for group = catalog.Groups
                candidate = catalog.ById{group.Form};
                if ~any(string(candidate.targetFactories) == factory), continue, end
                if strlength(yamada.catalog.AxesSettingFunctionCatalog.optionName(candidate, path)) > 0
                    main = group.Main;
                    form = candidate;
                    return
                end
            end
        end

        function name = optionName(form, path)
            % optionName Return the declared option that writes exactly this one path.
            arguments (Input)
                form (1, 1) struct
                path (1, 1) string
            end
            arguments (Output)
                name (1, 1) string
            end

            name = "";
            if ~isfield(form, "options"), return, end
            for item = yamada.catalog.AxesSettingFunctionCatalog.records(form.options)
                option = item{1};
                if isequal(reshape(string(option.paths), 1, []), path)
                    name = string(option.name);
                    return
                end
            end
        end

        function [paths, values, owned] = effects(form, value)
            % effects Expand one inserted argument into its owned and implied property values.
            arguments (Input)
                form (1, 1) struct
                value
            end
            arguments (Output)
                paths (1, :) string
                values cell
                owned (1, :) logical
            end

            paths = strings(1, 0); values = {}; owned = false(1, 0);
            for item = yamada.catalog.AxesSettingFunctionCatalog.records(form.effects)
                effect = item{1};
                paths(end + 1) = string(effect.path); %#ok<AGROW>
                owned(end + 1) = isfield(effect, "argument"); %#ok<AGROW>
                if owned(end) && isfield(effect, "elements") && ~isempty(value)
                    values{end + 1} = value(reshape(double(effect.elements), 1, [])); %#ok<AGROW>
                elseif owned(end)
                    values{end + 1} = value; %#ok<AGROW>
                else
                    literal = effect.literal;
                    if ischar(literal), literal = string(literal); end
                    values{end + 1} = literal; %#ok<AGROW>
                end
            end
        end

        function [paths, values, argumentsUsed, owned, elements] = match(forms, factory, tokens, implicit)
            % match Resolve a unique literal form and its affected property paths.
            %   owned marks effects whose value belongs to their argument token; implied
            %   literal effects have no token of their own. elements lists, per effect,
            %   the slice of a vector argument it owns, or is empty for the whole token.
            arguments (Input)
                forms cell
                factory (1, 1) string
                tokens (1, :) string
                implicit (1, 1) logical
            end
            arguments (Output)
                paths (1, :) string
                values cell
                argumentsUsed (1, :) double
                owned (1, :) logical
                elements cell
            end

            paths = strings(1,0); values = {}; argumentsUsed = []; owned = false(1,0); elements = {};
            matched = false;
            for item = forms
                form = item{1};
                if ~any(string(form.targetFactories) == factory) || ...
                        (implicit && string(form.target.implicit) ~= "inferWithWarning")
                    continue
                end
                [p, v, indices, o, e] = yamada.catalog.AxesSettingFunctionCatalog.decode(form,tokens);
                if isempty(p), continue, end
                if matched
                    paths = strings(1,0); values = {}; argumentsUsed = []; owned = false(1,0); elements = {};
                    return
                end
                paths = p; values = v; argumentsUsed = indices; owned = o; elements = e;
                matched = true;
            end
            if matched || numel(tokens) < 2, return, end

            % A call of several composable keywords, such as axis(ax,"equal","vis3d"),
            % applies each keyword's form in order; each keyword owns its own token.
            for index = 1:numel(tokens)
                composable = forms(cellfun(@(form) isfield(form,"composable") && form.composable, forms));
                [p, v, indices, o, e] = yamada.catalog.AxesSettingFunctionCatalog.match( ...
                    composable, factory, tokens(index), implicit);
                if isempty(p)
                    paths = strings(1,0); values = {}; argumentsUsed = []; owned = false(1,0); elements = {};
                    return
                end
                paths = [paths p]; values = [values v]; argumentsUsed = [argumentsUsed indices + index - 1]; %#ok<AGROW>
                owned = [owned o]; elements = [elements e]; %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function catalog = index(root)
            % index Load each packaged catalog root once and reuse its lookup tables.
            arguments (Input)
                root (1, 1) string
            end
            arguments (Output)
                catalog (1, 1) struct
            end

            persistent cached
            persistent catalogRoot
            if isempty(cached) || catalogRoot ~= root
                cached = yamada.catalog.AxesSettingFunctionCatalog.load(root);
                catalogRoot = root;
            end
            catalog = cached;
        end

        function catalog = load(root)
            % load Index packaged call forms and check argument, insertion and group references.
            arguments (Input)
                root (1, 1) string
            end
            arguments (Output)
                catalog (1, 1) struct
            end

            [~, release] = fileparts(root);
            catalog = struct("ByName", dictionary(string([]), {}), "ById", dictionary(string([]), {}), ...
                "Insertion", dictionary(string([]), string([])), "Companion", dictionary(string([]), string([])), ...
                "Automatic", dictionary(string([]), {}), "Groups", struct("Main", {}, "Form", {}));
            path = fullfile(root,"axes-setting-functions.json");
            if root == "" || ~isfile(path), return, end
            data = jsondecode(fileread(path));
            assert(data.schemaVersion == 1 && string(data.matlabRelease) == release, ...
                "yamada:AxesSettingFunctionCatalog:Version", "Invalid axes setting function catalog version.");
            for item = yamada.catalog.AxesSettingFunctionCatalog.records(data.forms)
                form = item{1};
                args = yamada.catalog.AxesSettingFunctionCatalog.records(form.arguments);
                names = string(cellfun(@(argument) argument.id,args,"UniformOutput",false));
                assert(~isKey(catalog.ById,string(form.id)) && numel(unique(names)) == numel(names) && ...
                    form.target.position == 1 && form.outputs == 0 && ~isempty(form.effects), ...
                    "yamada:AxesSettingFunctionCatalog:Form", "Invalid axes setting form %s.",form.id);
                ownedPaths = strings(1,0);
                for effect = yamada.catalog.AxesSettingFunctionCatalog.records(form.effects)
                    effect = effect{1};
                    fromArgument = isfield(effect,"argument");
                    assert(xor(fromArgument,isfield(effect,"literal")) && ...
                        (~fromArgument || any(names == string(effect.argument))), ...
                        "yamada:AxesSettingFunctionCatalog:Effect", "Invalid effect in axes setting form %s.",form.id);
                    if fromArgument, ownedPaths(end+1) = string(effect.path); end %#ok<AGROW>
                    if isfield(effect,"elements")
                        spec = args{names == string(effect.argument)};
                        assert(fromArgument && string(spec.type) == "axisLimits" && ...
                            all(ismember(effect.elements,1:spec.count)), ...
                            "yamada:AxesSettingFunctionCatalog:Effect", "Invalid element effect in axes setting form %s.",form.id);
                    end
                end
                % An insertion or companion form writes exactly one owned path from its only argument.
                for kind = ["insertion", "companionInsertion"]
                    if ~isfield(form,kind) || ~form.(kind), continue, end
                    assert(isscalar(args) && isscalar(ownedPaths) && ...
                        ~(isfield(form,"insertion") && isfield(form,"companionInsertion")), ...
                        "yamada:AxesSettingFunctionCatalog:Insertion", "Insertion form %s must own one path.",form.id);
                    for factory = reshape(string(form.targetFactories),1,[])
                        key = factory + " " + ownedPaths;
                        assert(~isKey(catalog.Insertion,key) && ~isKey(catalog.Companion,key), ...
                            "yamada:AxesSettingFunctionCatalog:Insertion", "Several insertion forms write %s.",key);
                        if kind == "insertion", catalog.Insertion(key) = string(form.id);
                        else, catalog.Companion(key) = string(form.id); end
                    end
                end
                % A call can return other explicit values, such as a label's FontSize, to automatic.
                if isfield(form,"automaticPaths")
                    automatic = reshape(string(form.automaticPaths),1,[]);
                    assert(~isempty(automatic) && isscalar(ownedPaths) && ~any(ismember(automatic,ownedPaths)), ...
                        "yamada:AxesSettingFunctionCatalog:Form", "Invalid automatic paths in axes setting form %s.",form.id);
                    for factory = reshape(string(form.targetFactories),1,[])
                        catalog.Automatic(factory + " " + ownedPaths) = {automatic};
                    end
                end
                catalog.ById(string(form.id)) = {form};
                name = string(form.name);
                existing = {};
                if isKey(catalog.ByName,name), existing = catalog.ByName{name}; end
                catalog.ByName(name) = {[existing {form}]};
            end
            % Each group's main path is the owned argument of a form that declares options.
            if ~isfield(data,"settingGroups"), return, end
            for item = yamada.catalog.AxesSettingFunctionCatalog.records(data.settingGroups)
                group = item{1};
                main = string(group.main); id = string(group.form);
                assert(isKey(catalog.ById,id), "yamada:AxesSettingFunctionCatalog:Group", ...
                    "Setting group %s names an unknown form.",main);
                form = catalog.ById{id};
                [paths, ~, owned] = yamada.catalog.AxesSettingFunctionCatalog.effects(form,[]);
                assert(isequal(paths(owned),main) && isfield(form,"options"), ...
                    "yamada:AxesSettingFunctionCatalog:Group", "Setting group %s must own its main path.",main);
                catalog.Groups(end+1) = struct("Main",main,"Form",id);
            end
        end

        function [paths, values, indices, owned, elements] = decode(form,tokens)
            % decode Match positional literals and optional name-value arguments.
            arguments (Input)
                form (1, 1) struct
                tokens (1, :) string
            end
            arguments (Output)
                paths (1, :) string
                values cell
                indices (1, :) double
                owned (1, :) logical
                elements cell
            end

            paths = strings(1,0); values = {}; indices = []; owned = false(1,0); elements = {};
            args = yamada.catalog.AxesSettingFunctionCatalog.records(form.arguments);
            count = numel(args);
            if numel(tokens) < count || (numel(tokens) > count && ~isfield(form,"options")), return, end
            decoded = cell(1,count);
            names = strings(1,count);
            for index = 1:count
                spec = args{index};
                [value, safe] = yamada.source.MatlabLiteralParser.parse(tokens(index));
                if ~safe || ~yamada.catalog.AxesSettingFunctionCatalog.accepts(spec,value), return, end
                decoded{index} = value;
                names(index) = string(spec.id);
            end
            [optionPaths, optionValues, optionIndices, valid] = ...
                yamada.catalog.AxesSettingFunctionCatalog.decodeOptions(form,tokens,count);
            if ~valid, return, end

            % Implied literal effects point to the triggering input but own no token.
            for item = yamada.catalog.AxesSettingFunctionCatalog.records(form.effects)
                effect = item{1};
                paths(end+1) = string(effect.path); %#ok<AGROW>
                owned(end+1) = isfield(effect,"argument"); %#ok<AGROW>
                elements{end+1} = zeros(1,0); %#ok<AGROW>
                if owned(end)
                    index = find(names == string(effect.argument),1);
                    value = decoded{index};
                    % An element effect owns a slice of a vector argument, such as XLim of axis limits.
                    if isfield(effect,"elements")
                        elements{end} = reshape(double(effect.elements),1,[]);
                        value = value(elements{end});
                    end
                    values{end+1} = value; %#ok<AGROW>
                    indices(end+1) = index; %#ok<AGROW>
                else
                    value = effect.literal;
                    if ischar(value), value = string(value); end
                    values{end+1} = value; %#ok<AGROW>
                    indices(end+1) = 1; %#ok<AGROW>
                end
            end
            paths = [paths optionPaths]; values = [values optionValues]; indices = [indices optionIndices];
            owned = [owned true(size(optionPaths))];
            elements = [elements repmat({zeros(1,0)},size(optionPaths))];
        end

        function [paths, values, indices, valid] = decodeOptions(form,tokens,count)
            % decodeOptions Resolve only declared options with supported literal values.
            arguments (Input)
                form (1, 1) struct
                tokens (1, :) string
                count (1, 1) double
            end
            arguments (Output)
                paths (1, :) string
                values cell
                indices (1, :) double
                valid (1, 1) logical
            end

            paths = strings(1,0); values = {}; indices = []; valid = true;
            index = count + 1;
            seen = strings(1,0);
            while index <= numel(tokens)
                valid = false;
                option = regexp(char(tokens(index)), '^([A-Za-z]\w*)\s*=\s*(.+)$', 'tokens', 'once');
                if isempty(option)
                    [name, safe] = yamada.source.MatlabLiteralParser.parse(tokens(index));
                    if ~safe || ~yamada.catalog.AxesSettingFunctionCatalog.isTextScalar(name) || index == numel(tokens), return, end
                    index = index + 1;
                    token = tokens(index);
                else
                    name = option{1};
                    token = string(option{2});
                end
                options = yamada.catalog.AxesSettingFunctionCatalog.records(form.options);
                selected = options(cellfun(@(item) string(item.name) == string(name),options));
                if ~isscalar(selected) || any(seen == string(name)), return, end
                specs = selected{1};
                [value, safe] = yamada.source.MatlabLiteralParser.parse(token);
                if ~safe || ~yamada.catalog.AxesSettingFunctionCatalog.accepts(specs,value), return, end
                affected = reshape(string(specs.paths),1,[]);
                paths = [paths affected]; %#ok<AGROW>
                values = [values repmat({value},size(affected))]; %#ok<AGROW>
                indices = [indices repmat(index,size(affected))]; %#ok<AGROW>
                seen(end+1) = string(name); %#ok<AGROW>
                valid = true;
                index = index + 1;
            end
        end

        function result = accepts(spec,value)
            % accepts Check an inert decoded value against its catalog argument kind.
            arguments (Input)
                spec (1, 1) struct
                value
            end
            arguments (Output)
                result (1, 1) logical
            end

            numeric = isnumeric(value) && isreal(value) && all(isfinite(value(:)));
            scalarText = yamada.catalog.AxesSettingFunctionCatalog.isTextScalar(value);
            textList = (isstring(value) && isvector(value) && ~any(ismissing(value))) || ...
                (iscell(value) && (isvector(value) || isempty(value)) && ...
                all(cellfun(@(item) ischar(item) && (isrow(item) || isempty(item)),value),"all"));
            switch string(spec.type)
                case "textLiteral"
                    result = scalarText || textList || (ischar(value) && ismatrix(value));
                case "textScalar"
                    result = scalarText && strlength(string(value)) > 0;
                case "textList"
                    result = scalarText || textList;
                    % The separate Mode form owns these special tokens.
                    if scalarText && any(string(value) == ["auto","manual","mode"]), result = false; end
                case "enum"
                    result = scalarText && any(string(value) == string(spec.values));
                case "finiteNumber"
                    result = numeric && isscalar(value);
                case "latitudeLimits"
                    result = numeric && isvector(value) && numel(value) == 2 && ...
                        value(1) <= value(2) && all(abs(value) <= 90);
                case "longitudeLimits"
                    result = numeric && isvector(value) && numel(value) == 2;
                case "increasingFinitePair"
                    result = numeric && isrow(value) && numel(value) == 2 && value(1) < value(2);
                case "increasingFiniteVector"
                    result = numeric && (isempty(value) || (isrow(value) && all(diff(value) > 0)));
                case "axisLimits"
                    % Consecutive pairs are increasing limits, for example [x1 x2 y1 y2].
                    result = numeric && isrow(value) && numel(value) == spec.count && ...
                        all(value(1:2:end) < value(2:2:end));
                case "positiveNumber"
                    result = numeric && isscalar(value) && value > 0;
                case "fontName"
                    result = scalarText && strlength(string(value)) > 0;
                case "matlabColor"
                    result = false;
                    if scalarText || (numeric && isrow(value) && numel(value) == 3)
                        try
                            validatecolor(value);
                            result = true;
                        catch
                            % Invalid colors are retained as unsupported source.
                        end
                    end
                otherwise
                    error("yamada:AxesSettingFunctionCatalog:ArgumentKind", "Unknown axes argument kind %s.",spec.type);
            end
        end

        function result = isTextScalar(value)
            % isTextScalar Recognize a character vector or a nonmissing string scalar.
            arguments (Input)
                value
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = (ischar(value) && (isrow(value) || isempty(value))) || ...
                (isstring(value) && isscalar(value) && ~ismissing(value));
        end

        function cells = records(value)
            % records Normalize homogeneous and heterogeneous JSON object arrays.
            arguments (Input)
                value
            end
            arguments (Output)
                cells cell
            end
            if iscell(value), cells = reshape(value,1,[]); else, cells = reshape(num2cell(value),1,[]); end
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
