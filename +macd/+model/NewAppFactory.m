classdef NewAppFactory
    % NewAppFactory Create registry-backed intermediate models for new apps.
    %   This static factory is responsible for initializing a document and its
    %   root UIFigure with safe editable defaults. It does not generate or save
    %   MATLAB source.
    %
    %   Example:
    %       document = macd.model.NewAppFactory.createEmpty("ExampleApp");

    methods (Static)
        function document = createEmpty(className, registry)
            % createEmpty Create a new document with one editable UIFigure root.
            arguments (Input)
                className string
                registry = []
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end

            % Use the standard registry unless the caller provides an extension.
            if isempty(registry)
                registry = macd.model.ComponentRegistry.createDefault();
            end

            % Create the shared document and registry-backed root record.
            definition = registry.get("uifigure");
            document = macd.model.DocumentModel(className);
            document.LineEnding = macd.model.NewAppFactory.defaultLineEnding();
            root = macd.model.ComponentRecord( ...
                macd.model.NewAppFactory.createId(), "UIFigure", ...
                definition.Factory, definition.DeclaredType, "generated");
            root.CreationArguments = definition.CreationArguments;

            % Seed only safe editable literals needed by a minimal app.
            root.setProperty("Position", [100 100 640 480]);
            root.setProperty("Name", className);
            root.setProperty("Visible", "on");
            document.addComponent(root);
        end
    end

    methods (Static, Access = private)
        function result = defaultLineEnding()
            % defaultLineEnding Return the host platform convention for new files.
            arguments (Output)
                result (1, 1) string
            end

            % Match the conventional line ending used for new local text files.
            if ispc
                result = "CRLF";
            else
                result = "LF";
            end
        end

        function id = createId()
            % createId Create a stable opaque identifier for a new component.
            arguments (Output)
                id string
            end

            % Two random 32-bit segments provide practical in-document uniqueness.
            id = string(sprintf("component-%08x-%08x", ...
                randi([0 intmax("uint32")]), randi([0 intmax("uint32")])));
        end
    end
end

%{
MatlabAppClassDesigner - Factory for a new empty AppBase document model.
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
