classdef NewAppGenerator
    % NewAppGenerator Generate canonical source for a new AppBase application.
    %   This class validates a shared document, emits registry-backed component
    %   declarations and initialization, and stores the generated preview. It does
    %   not rewrite existing source or write files to disk.
    %
    %   Example:
    %       document = macd.model.NewAppFactory.createEmpty("ExampleApp");
    %       source = macd.source.NewAppGenerator().generate(document);

    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods
        function obj = NewAppGenerator(registry)
            % NewAppGenerator Create a generator backed by a component registry.
            arguments (Input)
                registry = []
            end
            arguments (Output)
                obj (1, 1) macd.source.NewAppGenerator
            end

            % Use initial definitions unless the caller supplies extensions.
            if isempty(registry)
                registry = macd.model.ComponentRegistry.createDefault();
            end
            obj.Registry = registry;
        end

        function [source, diagnostics] = generate(obj, document)
            % generate Emit a canonical AppBase class from a new-app document.
            arguments (Input)
                obj (1, 1) macd.source.NewAppGenerator
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                source string
                diagnostics macd.model.Diagnostic
            end

            % Block generation when shared validation finds unsafe state.
            diagnostics = macd.validation.ModelValidator.validate( ...
                document, obj.Registry);
            source = "";
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                return
            end

            % Emit class identity and component property declarations.
            lines = [compose("classdef %s < matlab.apps.AppBase", document.ClassName), ...
                compose("    %% %s Define a programmatic AppBase application.", ...
                document.ClassName), ...
                "    %   This class owns its generated UI component hierarchy and", ...
                "    %   application lifecycle. It does not require an MLAPP file.", ...
                "    %", "    %   Example:", ...
                compose("    %%       app = %s();", document.ClassName), ...
                "", "    properties (Access = public)"];
            for index = 1:numel(document.Components)
                component = document.Components(index);
                lines(end + 1) = compose( ...
                    "        %% %s - Generated UI component handle.", ...
                    component.Name); %#ok<AGROW>
                lines(end + 1) = compose("        %-20s %s", ...
                    component.Name, component.DeclaredType); %#ok<AGROW>
            end
            lines = [lines, "    end", "", "    methods (Access = private)", "", ...
                "        function createComponents(app)", ...
                "            % createComponents Create and configure UI components.", ...
                "            arguments (Input)", ...
                compose("                app (1, 1) %s", document.ClassName), ...
                "            end", ""];

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
                    factoryArguments(end + 1) = macd.source.LiteralEncoder.encode( ...
                        component.CreationArguments{argumentIndex}); %#ok<AGROW>
                end
                if isempty(parent) && component.Factory == "uifigure"
                    factoryArguments = [factoryArguments, ...
                        """Visible""", """off"""]; %#ok<AGROW>
                end
                lines(end + 1) = compose( ...
                    "            %% Create a %s component.", component.Factory); %#ok<AGROW>
                lines(end + 1) = compose("            app.%s = %s(%s);", ...
                    component.Name, component.Factory, ...
                    strjoin(factoryArguments, ", ")); %#ok<AGROW>

                % Encode only safe literals while retaining property paths.
                if ~isempty(component.Properties)
                    lines(end + 1) = ...
                        "            % Configure safe literal properties."; %#ok<AGROW>
                end
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if component.Id == document.RootComponentId && ...
                            entry.Path == "Visible"
                        continue
                    end
                    if entry.ValueKind ~= "literal"
                        diagnostics(end + 1) = macd.model.Diagnostic( ...
                            "nonliteral-new-app-property", "error", ...
                            sprintf("Property ""%s"" is not a literal and " + ...
                            "cannot be emitted by the new-app generator.", entry.Path), ...
                            component.Id, entry.SourceSpan); %#ok<AGROW>
                        source = "";
                        document.Diagnostics = diagnostics;
                        return
                    end
                    try
                        valueText = macd.source.LiteralEncoder.encode(entry.LiteralValue);
                    catch exception
                        diagnostics(end + 1) = macd.model.Diagnostic( ...
                            "unsupported-literal", "error", exception.message, ...
                            component.Id, entry.SourceSpan); %#ok<AGROW>
                        source = "";
                        document.Diagnostics = diagnostics;
                        return
                    end
                    lines(end + 1) = compose("            app.%s.%s = %s;", ...
                        component.Name, entry.Path, valueText); %#ok<AGROW>
                end
                % Separate component blocks for readable generated diffs.
                lines(end + 1) = ""; %#ok<AGROW>
            end

            % Reveal the root only after every child is configured.
            root = document.getComponent(document.RootComponentId);
            visible = root.getProperty("Visible");
            if ~isempty(visible)
                visibleText = macd.source.LiteralEncoder.encode(visible.LiteralValue);
                lines(end + 1) = compose("            app.%s.Visible = %s;", ...
                    root.Name, visibleText);
            end

            % Finish the constructor, registration, and destructor skeleton.
            lines = [lines, "        end", "    end", "", ...
                "    methods (Access = public)", "", ...
                compose("        function app = %s", document.ClassName), ...
                compose("            %% %s Construct and register the application.", ...
                document.ClassName), ...
                "            arguments (Output)", ...
                compose("                app (1, 1) %s", document.ClassName), ...
                "            end", "", ...
                "            % Build the UI before registering the application.", ...
                "            createComponents(app);", ...
                compose("            registerApp(app, app.%s);", root.Name), "", ...
                "            % Match App Designer behavior for no-output calls.", ...
                "            if nargout == 0", "                clear app", ...
                "            end", "        end", "", ...
                "        function delete(app)", ...
                "            % delete Delete the application UI figure.", ...
                "            arguments (Input)", ...
                compose("                app (1, 1) %s", document.ClassName), ...
                "            end", "", ...
                "            % Release the root figure and all child components.", ...
                compose("            delete(app.%s);", root.Name), ...
                "        end", "    end", "end"];

            % Store the exact CRLF preview on the shared document model.
            source = strjoin(lines, sprintf("\r\n")) + sprintf("\r\n");
            document.GeneratedText = source;
            document.Diagnostics = diagnostics;
        end
    end
end

%{
MatlabAppClassDesigner - Canonical source generator for new AppBase classes.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
