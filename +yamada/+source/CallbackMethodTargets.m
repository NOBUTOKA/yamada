classdef CallbackMethodTargets
    % CallbackMethodTargets Filter cached method signatures using trusted type information.
    %   Discovery never executes opened app code, defaults or validation functions.
    %   Unknown constraints remain visible as unchecked rather than being rejected.

    methods (Static)
        function name = defaultName(document, componentId, callback, registry)
            % defaultName Share the reviewed naming rule and collision numbering with the name popup.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                callback (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                name (1, 1) string
            end
            component = document.getComponent(componentId);
            assert(~isempty(component), "yamada:DocumentModel:UnsafeCallbackEdit", "The callback component no longer exists.");
            parentFactory = "";
            if component.ParentId ~= "", parentFactory = document.getComponent(component.ParentId).Factory; end
            definitions = registry.getEffectiveCallbacks(component.Factory, parentFactory, component.CreationArguments);
            definition = definitions(string({definitions.Path}) == callback);
            assert(isscalar(definition), "yamada:DocumentModel:UnsafeCallbackEdit", "The callback definition is unavailable.");
            stem = yamada.source.ComponentNameRewriter.defaultHandler(component.Name, callback, definition.HandlerSuffix);
            used = yamada.source.CallbackMethodTargets.reservedNames(document);
            name = stem; suffix = 1;
            while any(used == name)
                suffix = suffix + 1;
                name = stem + "_" + suffix;
            end
        end

        function used = reservedNames(document)
            % reservedNames Read cached identifiers and history reservations without parsing source again.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                used (1, :) string
            end
            names = document.sourceAnalysis().nameIndex();
            used = [string({document.Components.Name}), string({document.CallbackEdits.HandlerName}), ...
                string({document.RenameEdits.OldName}), string({document.RenameEdits.NewName}), ...
                document.ClassName, "createComponents", "delete", "figureDeleted", ...
                reshape(names.Members, 1, []), string(regexp(names.Code, '[A-Za-z]\w*', 'match')), ...
                string(properties("handle"))', string(methods("handle"))'];
            for item = document.History
                edit = item{1};
                if edit.Kind == "callback"
                    previous = [edit.Before edit.After];
                    used = [used string({previous.HandlerName})]; %#ok<AGROW>
                    if isfield(edit, "DeletedHandler"), used = [used edit.DeletedHandler]; end %#ok<AGROW>
                end
            end
        end

        function targets = list(document, componentId, name, registry)
            % list Read eligible directly declared instance methods for one callback.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                name (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                targets (1, :) struct
            end
            targets = struct("Name", {}, "Label", {}, "Expression", {}, "Unchecked", {});
            component = document.getComponent(componentId);
            if isempty(component), return, end
            parentFactory = "";
            if component.ParentId ~= "", parentFactory = document.getComponent(component.ParentId).Factory; end
            definitions = registry.getEffectiveCallbacks(component.Factory, parentFactory, component.CreationArguments);
            definition = definitions(string({definitions.Path}) == name);
            if ~isscalar(definition), return, end
            analysis = document.sourceAnalysis();
            if ~analysis.Layout.Valid, return, end
            methods = analysis.Layout.Methods;
            for method = methods
                signature = method.Signature;
                if ~signature.Eligible || any(method.Name == [document.ClassName, "delete", "createComponents", "figureDeleted"]) || ...
                        nnz(string({methods.Name}) == method.Name) ~= 1
                    continue
                end
                actual = repmat("", size(signature.Inputs));
                actual(1) = document.ClassName;
                if numel(actual) == 3, actual(2) = component.DeclaredType; end
                if numel(actual) > 1, actual(end) = definition.CallbackSignature.ClassName; end
                accepted = true;
                unchecked = any(signature.Unchecked);
                for index = 1:numel(actual)
                    [compatible, known] = yamada.source.CallbackMethodTargets.compatible(actual(index), signature.Classes(index));
                    accepted = accepted && compatible;
                    unchecked = unchecked || ~known;
                end
                if ~accepted, continue, end
                parameters = signature.Inputs;
                % The implicit receiver's class adds no useful information to the label.
                for index = find(signature.Classes ~= "" & (1:numel(parameters)) > 1)
                    parameters(index) = parameters(index) + " " + signature.Classes(index);
                end
                label = method.Name + "(" + strjoin(parameters, ", ") + ")";
                if unchecked, label = label + " [unchecked]"; end
                targets(end + 1) = struct("Name", method.Name, "Label", label, ...
                    "Expression", signature.binding(method.Name), "Unchecked", unchecked); %#ok<AGROW>
            end
        end

        function [accepted, known] = compatible(actual, expected)
            % compatible Reject only proven type mismatches without loading arbitrary user classes.
            arguments (Input)
                actual (1, 1) string
                expected (1, 1) string
            end
            arguments (Output)
                accepted (1, 1) logical
                known (1, 1) logical
            end
            accepted = true;
            known = expected == "" || actual ~= "" && actual == expected;
            if known, return, end
            if actual == "", return, end

            % Only MathWorks-installed classes may be reflected; user code is never loaded.
            builtin = ["double", "single", "logical", "char", "string", "cell", "struct", ...
                "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64"];
            if any(expected == builtin) && any(actual == builtin)
                % MATLAB can convert several built-in argument classes during validation.
                return
            end
            actualMeta = yamada.source.CallbackMethodTargets.trustedClass(actual);
            if ~isempty(actualMeta) && yamada.source.CallbackMethodTargets.derivesFrom(actualMeta, expected)
                known = true;
                return
            end
            expectedMeta = yamada.source.CallbackMethodTargets.trustedClass(expected);
            if isempty(actualMeta) || isempty(expectedMeta), return, end
            known = true;
            accepted = yamada.source.CallbackMethodTargets.derivesFrom(actualMeta, expected);
        end
    end

    methods (Static, Access = private)
        function metadata = trustedClass(name)
            % trustedClass Reflect only installed public class definitions under matlabroot.
            arguments (Input)
                name (1, 1) string
            end
            arguments (Output)
                metadata meta.class
            end
            metadata = meta.class.empty;
            if isempty(regexp(name, '^[A-Za-z]\w*(?:\.[A-Za-z]\w*)*$', 'once')), return, end
            location = string(which(name));
            installed = startsWith(lower(location), lower(string(matlabroot) + filesep));
            builtin = startsWith(location, "built-in (") && contains(lower(location), lower(string(matlabroot) + filesep)) || ...
                name == "event.EventData" && location == "event.EventData is a built-in method";
            if ~installed && ~builtin, return, end
            metadata = meta.class.fromName(name);
        end

        function result = derivesFrom(metadata, name)
            % derivesFrom Walk trusted class ancestry without constructing instances.
            arguments (Input)
                metadata (1, 1) meta.class
                name (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = string(metadata.Name) == name;
            if result, return, end
            for parent = reshape(metadata.SuperclassList, 1, [])
                if yamada.source.CallbackMethodTargets.derivesFrom(parent, name), result = true; return, end
            end
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
