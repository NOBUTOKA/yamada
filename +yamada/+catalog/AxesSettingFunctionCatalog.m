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

            persistent byName
            persistent catalogRoot
            if isempty(byName) || catalogRoot ~= root
                byName = yamada.catalog.AxesSettingFunctionCatalog.load(root);
                catalogRoot = root;
            end
            forms = {};
            if isKey(byName, name), forms = byName{name}; end
        end

        function [paths, values, argumentsUsed] = match(forms, factory, tokens, implicit)
            % match Resolve a unique literal form and its affected property paths.
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
            end

            paths = strings(1,0); values = {}; argumentsUsed = [];
            matched = false;
            for item = forms
                form = item{1};
                if ~any(string(form.targetFactories) == factory) || ...
                        (implicit && string(form.target.implicit) ~= "inferWithWarning")
                    continue
                end
                [p, v, indices] = yamada.catalog.AxesSettingFunctionCatalog.decode(form,tokens);
                if isempty(p), continue, end
                if matched
                    paths = strings(1,0); values = {}; argumentsUsed = [];
                    return
                end
                paths = p; values = v; argumentsUsed = indices;
                matched = true;
            end
        end
    end

    methods (Static, Access = private)
        function byName = load(root)
            % load Index packaged call forms and check source argument references.
            arguments (Input)
                root (1, 1) string
            end
            arguments (Output)
                byName dictionary
            end

            [~, release] = fileparts(root);
            byName = dictionary(string([]), {});
            path = fullfile(root,"axes-setting-functions.json");
            if root == "" || ~isfile(path), return, end
            data = jsondecode(fileread(path));
            assert(data.schemaVersion == 1 && string(data.matlabRelease) == release, ...
                "yamada:AxesSettingFunctionCatalog:Version", "Invalid axes setting function catalog version.");
            ids = strings(1,0);
            for item = yamada.catalog.AxesSettingFunctionCatalog.records(data.forms)
                form = item{1};
                args = yamada.catalog.AxesSettingFunctionCatalog.records(form.arguments);
                names = string(cellfun(@(argument) argument.id,args,"UniformOutput",false));
                assert(~any(ids == string(form.id)) && numel(unique(names)) == numel(names) && ...
                    form.target.position == 1 && form.outputs == 0 && ~isempty(form.effects), ...
                    "yamada:AxesSettingFunctionCatalog:Form", "Invalid axes setting form %s.",form.id);
                ids(end+1) = string(form.id); %#ok<AGROW>
                for effect = yamada.catalog.AxesSettingFunctionCatalog.records(form.effects)
                    effect = effect{1};
                    fromArgument = isfield(effect,"argument");
                    assert(xor(fromArgument,isfield(effect,"literal")) && ...
                        (~fromArgument || any(names == string(effect.argument))), ...
                        "yamada:AxesSettingFunctionCatalog:Effect", "Invalid effect in axes setting form %s.",form.id);
                end
                name = string(form.name);
                existing = {};
                if isKey(byName,name), existing = byName{name}; end
                byName(name) = {[existing {form}]};
            end
        end

        function [paths, values, indices] = decode(form,tokens)
            % decode Match positional literals and optional name-value arguments.
            arguments (Input)
                form (1, 1) struct
                tokens (1, :) string
            end
            arguments (Output)
                paths (1, :) string
                values cell
                indices (1, :) double
            end

            paths = strings(1,0); values = {}; indices = [];
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

            % Fixed effects point to the triggering input and stay read-only.
            for item = yamada.catalog.AxesSettingFunctionCatalog.records(form.effects)
                effect = item{1};
                paths(end+1) = string(effect.path); %#ok<AGROW>
                if isfield(effect,"argument")
                    index = find(names == string(effect.argument),1);
                    values{end+1} = decoded{index}; %#ok<AGROW>
                    indices(end+1) = index; %#ok<AGROW>
                else
                    value = effect.literal;
                    if ischar(value), value = string(value); end
                    values{end+1} = value; %#ok<AGROW>
                    indices(end+1) = 1; %#ok<AGROW>
                end
            end
            paths = [paths optionPaths]; values = [values optionValues]; indices = [indices optionIndices];
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
                case "increasingFinitePair"
                    result = numeric && isrow(value) && numel(value) == 2 && value(1) < value(2);
                case "increasingFiniteVector"
                    result = numeric && (isempty(value) || (isrow(value) && all(diff(value) > 0)));
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
