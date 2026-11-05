classdef NewAppGenerator
    % NewAppGenerator Generate canonical source for a new handle-based application.
    %   This class validates a shared document, emits registry-backed component
    %   declarations and initialization, and stores the generated preview. It does
    %   not rewrite existing source or write files to disk.
    %
    %   Example:
    %       document = yamada.model.NewAppFactory.createEmpty("ExampleApp");
    %       source = yamada.source.NewAppGenerator().generate(document);

    properties (Access = private)
        Registry yamada.model.ComponentRegistry
    end

    methods
        function obj = NewAppGenerator(registry)
            % NewAppGenerator Create a generator backed by a component registry.
            arguments (Input)
                registry = []
            end
            arguments (Output)
                obj (1, 1) yamada.source.NewAppGenerator
            end

            % Use initial definitions unless the caller supplies extensions.
            if isempty(registry)
                registry = yamada.model.ComponentRegistry.createDefault();
            end
            obj.Registry = registry;
        end

        function [source, diagnostics] = generate(obj, document)
            % generate Emit a canonical handle-based class from a new-app document.
            arguments (Input)
                obj (1, 1) yamada.source.NewAppGenerator
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                source string
                diagnostics yamada.model.Diagnostic
            end

            % Once canonical source exists, use the same source-preserving path as opened documents.
            if strlength(document.CurrentText) > 0
                [source, diagnostics] = yamada.source.RoundTripGenerator(obj.Registry).generate(document);
                return
            end
            % Block generation when shared validation finds unsafe state.
            evaluationScope = document.evaluationContext(obj.Registry).readScope(); %#ok<NASGU>
            diagnostics = yamada.validation.ModelValidator.validate( ...
                document, obj.Registry);
            source = "";
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                return
            end

            % Emit class identity and component property declarations.
            lines = [compose("classdef %s < handle", document.ClassName), ...
                compose("    %% %s Define a programmatic handle-based application.", ...
                document.ClassName), ...
                "", "    properties (Access = private)"];
            for index = 1:numel(document.Components)
                component = document.Components(index);
                lines(end + 1) = compose("        %-20s %s", ...
                    component.Name, component.DeclaredType); %#ok<AGROW>
            end
            lines = [lines, "    end", "", "    methods (Access = private)", "", ...
                "        function createComponents(app)", ...
                "            % createComponents Create and configure UI components.", ...
                "            arguments (Input)", ...
                compose("                app (1, 1) %s", document.ClassName), ...
                "            end", ""];

            deferredSelection = strings(1, 0);
            % Emit components in parent-before-child document order.
            for index = 1:numel(document.Components)
                component = document.Components(index);
                parent = document.getComponent(component.ParentId);

                % Build a registry-derived factory call without executing it.
                factoryArguments = strings(1, 0);
                if ~isempty(parent)
                    factoryArguments(end + 1) = "app." + parent.Name; %#ok<AGROW>
                end
                for argumentIndex = 1:numel(component.CreationArguments)
                    factoryArguments(end + 1) = yamada.source.LiteralEncoder.encode( ...
                        component.CreationArguments{argumentIndex}); %#ok<AGROW>
                end
                if isempty(parent) && component.Factory == "uifigure"
                    factoryArguments = [factoryArguments, ...
                        """Visible""", """off"""]; %#ok<AGROW>
                end
                lines(end + 1) = compose("            app.%s = %s(%s);", ...
                    component.Name, component.Factory, ...
                    strjoin(factoryArguments, ", ")); %#ok<AGROW>

                % Keep the default close path unless a user-owned close handler replaces it.
                pendingClose = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == component.Id & ...
                    string({document.CallbackEdits.Name}) == "CloseRequestFcn" & ...
                    ismember(string({document.CallbackEdits.Action}), ["Add", "New", "Connect"]));
                if component.Factory == "uifigure" && isempty(pendingClose)
                    lines(end + 1) = "            " + yamada.source.CallbackSourceEdits.defaultClose(component.Name); %#ok<AGROW>
                end

                % Encode only safe literals while retaining property paths.
                entries = yamada.model.PropertyApplicationPlanner.forComponent( ...
                    component, document, obj.Registry);
                for propertyIndex = 1:numel(entries)
                    entry = entries(propertyIndex);
                    if obj.Registry.isReadOnlyProperty(component.Factory, entry.Path, component.CreationArguments)
                        continue
                    end
                    pending = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == component.Id & ...
                        string({document.CallbackEdits.Name}) == entry.Path);
                    if ~isempty(pending), continue, end
                    if component.Id == document.RootComponentId && ...
                            entry.Path == "Visible"
                        continue
                    end
                    if isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                    if entry.ValueKind ~= "literal"
                        diagnostics(end + 1) = yamada.model.Diagnostic( ...
                            "nonliteral-new-app-property", "error", ...
                            sprintf("Property ""%s"" is not a literal and " + ...
                            "cannot be emitted by the new-app generator.", entry.Path), ...
                            component.Id, entry.SourceSpan); %#ok<AGROW>
                        source = "";
                        document.Diagnostics = diagnostics;
                        return
                    end
                    try
                        valueText = yamada.source.LiteralEncoder.encode(entry.LiteralValue);
                    catch exception
                        diagnostics(end + 1) = yamada.model.Diagnostic( ...
                            "unsupported-literal", "error", exception.message, ...
                            component.Id, entry.SourceSpan); %#ok<AGROW>
                        source = "";
                        document.Diagnostics = diagnostics;
                        return
                    end
                    assignment = compose("            app.%s.%s = %s;", component.Name, entry.Path, valueText);
                    if yamada.model.ButtonSelectionPolicy.deferValue(component, entry.Path)
                        deferredSelection(end + 1) = assignment; %#ok<AGROW>
                    else
                        lines(end + 1) = assignment; %#ok<AGROW>
                    end
                end
                % Emit managed callbacks without exposing executable expressions to Safe Preview.
                pending = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == component.Id);
                for callback = pending(:)'
                    if any(callback.Action == ["Add", "New", "Connect"])
                        lines(end + 1) = "            " + yamada.source.CallbackSourceEdits.bindingText(component.Name, callback.Name, callback.HandlerName, callback.BindingExpression); %#ok<AGROW>
                    end
                end
                % Separate component blocks for readable generated diffs.
                lines(end + 1) = ""; %#ok<AGROW>
            end

            % Exclusive values may select siblings, so every sibling must already exist.
            lines = [lines deferredSelection];
            % Resolve allowlisted references only after every target exists.
            try
                references = yamada.model.SubtreeReferencePolicy.assignments(document, document.Components, obj.Registry);
                lines = [lines "            " + references];
            catch exception
                diagnostics(end + 1) = yamada.model.Diagnostic("unsafe-component-reference", "error", string(exception.message));
                source = "";
                document.Diagnostics = diagnostics;
                return
            end
            root = document.getComponent(document.RootComponentId);
            visible = root.getProperty("Visible");
            visibleText = """on""";
            if ~isempty(visible), visibleText = yamada.source.LiteralEncoder.encode(visible.LiteralValue); end

            % Add callback methods in a separate private block before constructor generation.
            pending = document.CallbackEdits;
            methods = strings(1, 0);
            for callback = pending(:)'
                if any(callback.Action == ["Add", "New"]) && ~isempty(document.getComponent(callback.ComponentId))
                    methods(end + 1) = yamada.source.CallbackSourceEdits.methodText(callback, document.ClassName); %#ok<AGROW>
                end
            end
            lines = [lines, "        end", "    end", ""];
            if ~isempty(methods)
                lines = [lines, "    methods (Access = private)", methods, "    end", ""];
            end
            % Bind figure destruction to its owner without replacing a user's DeleteFcn.
            lines = [lines, "    methods (Access = private)", ...
                "        function figureDeleted(app, ~, ~)", ...
                "            % figureDeleted Release the owner when its figure is destroyed.", ...
                "            arguments (Input)", ...
                compose("                app (1, 1) %s", document.ClassName), ...
                "                ~", "                ~", "            end", ...
                "            if isvalid(app), delete(app); end", ...
                "        end", "    end", ""];
            lines = [lines, ...
                "    methods (Access = public)", "", ...
                compose("        function app = %s", document.ClassName), ...
                compose("            %% %s Construct the application.", document.ClassName), ...
                "            arguments (Output)", ...
                compose("                app (1, 1) %s", document.ClassName), ...
                "            end", "", ...
                "            try", ...
                "                createComponents(app);", ...
                compose("                addlistener(app.%s, ""ObjectBeingDestroyed"", @app.figureDeleted);", root.Name), ...
                compose("                app.%s.Visible = %s;", root.Name, visibleText), ...
                "            catch exception", ...
                "                delete(app);", ...
                "                rethrow(exception);", ...
                "            end", ...
                "        end", "", ...
                "        function delete(app)", ...
                "            % delete Delete the application UI figure.", ...
                compose("            if ~isempty(app.%s) && isvalid(app.%s)", root.Name, root.Name), ...
                compose("                delete(app.%s);", root.Name), ...
                "            end", "        end", "    end", "end"];

            % Store a preview using the document's selected source convention.
            lineEnding = yamada.source.NewAppGenerator.lineEndingText( ...
                document.LineEnding);
            source = strjoin(lines, lineEnding) + lineEnding;
            formatted = yamada.source.SourceFormatting.separateComponents("", ...
                struct("Start", 1, "End", 0, "Text", source));
            source = formatted.Text;
            source = yamada.source.ComponentNameRewriter.rewrite(source, document.RenameEdits);
            document.GeneratedText = source;
            document.Diagnostics = diagnostics;
        end
    end

    methods (Static, Access = private)
        function result = lineEndingText(convention)
            % lineEndingText Convert one named source convention into its text.
            arguments (Input)
                convention (1, 1) string
            end
            arguments (Output)
                result (1, 1) string
            end

            % Reject conventions that cannot delimit a generated multi-line class.
            switch convention
                case "CRLF"
                    result = sprintf("\r\n");
                case "LF"
                    result = newline;
                otherwise
                    error("yamada:NewAppGenerator:UnsupportedLineEnding", ...
                        "Line ending convention ""%s"" is not supported for generation.", ...
                        convention);
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
