classdef AppSourceParser
    % AppSourceParser Parse a conservative AppBase source subset without running it.
    %   This static parser reads AppBase inheritance, component declarations,
    %   registry-supported factory calls, parent links, and direct property
    %   assignments into a shared DocumentModel. Unsupported expressions remain
    %   source-backed and are reported rather than evaluated or discarded.
    %
    %   Example:
    %       registry = macd.model.ComponentRegistry.createDefault();
    %       document = macd.source.AppSourceParser.parseFile( ...
    %           "ExampleApp.m", registry);

    %#ok<*AGROW> Parsed source findings are intentionally accumulated in source order.

    methods (Static)
        function [document, diagnostics] = parseFile(filePath, registry)
            % parseFile Read UTF-8 AppBase source and parse it without execution.
            arguments (Input)
                filePath (1, 1) string {mustBeFile}
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                diagnostics macd.model.Diagnostic
            end

            % Read and validate UTF-8 bytes without executing input source.
            [bytes, readDiagnostic] = macd.source.AppSourceParser.readBytes(filePath);
            hasBom = numel(bytes) >= 3 && ...
                isequal(bytes(1:3), uint8([239 187 191]));
            if hasBom
                bytes = bytes(4:end);
            end
            isValidUtf8 = macd.source.AppSourceParser.isValidUtf8(bytes);
            source = string(native2unicode(bytes, "UTF-8"));

            % Block editing when decoding would irreversibly replace input bytes.
            if ~isValidUtf8
                document = macd.model.DocumentModel("ParsedApp");
                document.FilePath = filePath;
                document.OriginalText = source;
                document.Encoding = "UTF-8";
                document.LineEnding = macd.source.AppSourceParser.lineEnding(source);
                diagnostics = macd.source.AppSourceParser.diagnostic( ...
                    "invalid-utf8", "error", ...
                    "Input source is not valid UTF-8 and cannot be edited safely.", ...
                    "", macd.model.SourceSpan.empty);
                document.Diagnostics = diagnostics;
                return
            end

            % Parse decoded text and append file-format diagnostics afterwards.
            [document, diagnostics] = macd.source.AppSourceParser.parseText( ...
                source, registry, filePath);
            if ~isempty(readDiagnostic)
                diagnostics(end + 1) = readDiagnostic;
            end
            if hasBom
                diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                    "utf8-bom", "warning", ...
                    "Input source has a UTF-8 BOM; it is retained only in diagnostics.", ...
                    "", macd.model.SourceSpan.empty);
            end
            document.Diagnostics = diagnostics;
        end

        function [document, diagnostics] = parseText(source, registry, filePath)
            % parseText Parse AppBase source text into the shared document model.
            arguments (Input)
                source string
                registry (1, 1) macd.model.ComponentRegistry
                filePath string = ""
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                diagnostics macd.model.Diagnostic
            end

            % Split source lexically before applying limited structural recognition.
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            [className, isAppBase] = macd.source.AppSourceParser.findAppBaseClass( ...
                statements);
            if strlength(className) == 0
                className = "ParsedApp";
            end
            document = macd.model.DocumentModel(className);
            document.FilePath = filePath;
            document.OriginalText = source;
            document.Encoding = "UTF-8";
            document.LineEnding = macd.source.AppSourceParser.lineEnding(source);
            diagnostics = macd.model.Diagnostic.empty;
            if ~isAppBase
                diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                    "not-appbase-class", "error", ...
                    "Source does not declare a class derived from matlab.apps.AppBase.", ...
                    "", macd.model.SourceSpan.empty);
                document.Diagnostics = diagnostics;
                return
            end

            % Collect declared component types before constructing model records.
            declarations = macd.source.AppSourceParser.propertyDeclarations(statements);

            % Recover supported component creation calls in original source order.
            for index = 1:numel(statements)
                statement = statements(index);
                creation = macd.source.AppSourceParser.creationMatch(statement.Text);
                if isempty(creation)
                    continue
                end
                if ~registry.contains(creation.Factory)
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "unsupported-factory", "warning", ...
                        "Component factory is not registered and was retained as source.", ...
                        creation.Name, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        macd.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "unsupported-factory");
                    continue
                end

                % Recover an optional parent and safe literal factory arguments.
                [parentName, creationArguments, isSupported] = ...
                    macd.source.AppSourceParser.creationArguments(creation.Arguments);
                if ~isSupported
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "nonliteral-creation-argument", "warning", ...
                        "Component creation has an unsupported argument and was retained as source.", ...
                        creation.Name, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        macd.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "nonliteral-creation-argument");
                    continue
                end

                % Resolve declaration metadata and parent identity before mutation.
                definition = registry.get(creation.Factory);
                declaredType = definition.DeclaredType;
                declarationSpan = macd.model.SourceSpan.empty;
                if isKey(declarations, char(creation.Name))
                    declaration = declarations(char(creation.Name));
                    declaredType = declaration.DeclaredType;
                    declarationSpan = declaration.Span;
                else
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "missing-component-declaration", "warning", ...
                        "Component creation has no matching property declaration.", ...
                        creation.Name, statement.Span);
                end
                parentId = "";
                if strlength(parentName) > 0
                    parent = document.getComponentByName(parentName);
                    if isempty(parent)
                        diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                            "missing-parent", "warning", ...
                            "Component parent is not available from supported prior source.", ...
                            creation.Name, statement.Span);
                        document.UnknownRegions(end + 1) = ...
                            macd.model.UnknownSourceRegion( ...
                            statement.Text, statement.Span, "missing-parent");
                        continue
                    end
                    parentId = parent.Id;
                end

                % Create an editable record only after all ownership is understood.
                component = macd.model.ComponentRecord( ...
                    "parsed-" + creation.Name, creation.Name, creation.Factory, ...
                    declaredType, "parsed");
                component.CreationArguments = creationArguments;
                component.SourceSpans = struct( ...
                    "Declaration", declarationSpan, "Creation", statement.Span);
                try
                    document.addComponent(component, parentId);
                catch exception
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "invalid-component-creation", "warning", exception.message, ...
                        creation.Name, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        macd.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "invalid-component-creation");
                end
            end

            % Recover direct assignments after components and parent links exist.
            for index = 1:numel(statements)
                statement = statements(index);
                assignment = macd.source.AppSourceParser.assignmentMatch(statement.Text);
                if isempty(assignment)
                    continue
                end
                component = document.getComponentByName(assignment.ComponentName);
                if isempty(component)
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "unknown-assignment-component", "warning", ...
                        "Property assignment has no supported component record.", ...
                        assignment.ComponentName, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        macd.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "unknown-assignment-component");
                    continue
                end

                % Do not mistake callback logic preceding creation for initialization.
                if statement.Span.StartOffset < ...
                        component.SourceSpans.Creation.StartOffset
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "assignment-before-creation", "warning", ...
                        "Property assignment precedes supported component creation and was retained as source.", ...
                        component.Id, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        macd.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "assignment-before-creation");
                    continue
                end

                % Keep unsupported expressions opaque instead of evaluating them.
                [value, isLiteral] = macd.source.MatlabLiteralParser.parse( ...
                    assignment.ValueText);
                existingEntry = component.getProperty(assignment.Path);
                if ~isempty(existingEntry) && ~existingEntry.IsEditable
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "conflicting-property-assignment", "warning", ...
                        "Later assignment conflicts with retained source expression and was retained as source.", ...
                        component.Id, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        macd.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "conflicting-property-assignment");
                    continue
                end
                entry = component.setProperty(assignment.Path, value);
                if ~isLiteral
                    entry.setSourceExpression(assignment.ValueText);
                    diagnostics(end + 1) = macd.source.AppSourceParser.diagnostic( ...
                        "source-expression", "warning", ...
                        "Property expression was retained as read-only source text.", ...
                        component.Id, statement.Span);
                    document.UnknownRegions(end + 1) = ...
                        macd.model.UnknownSourceRegion( ...
                        statement.Text, statement.Span, "source-expression");
                end
                entry.SourceSpan = statement.Span;
            end

            % Combine parser findings with shared model validation diagnostics.
            validationDiagnostics = macd.validation.ModelValidator.validate( ...
                document, registry);
            diagnostics = [diagnostics(:)' validationDiagnostics(:)'];
            document.Diagnostics = diagnostics;
        end
    end

    methods (Static, Access = private)
        function [bytes, diagnostic] = readBytes(filePath)
            % readBytes Read a file in binary mode without source execution.
            arguments (Input)
                filePath string
            end
            arguments (Output)
                bytes uint8
                diagnostic macd.model.Diagnostic
            end

            % Return a structured error only when the input file cannot be read.
            bytes = uint8.empty;
            diagnostic = macd.model.Diagnostic.empty;
            [fileId, message] = fopen(filePath, "rb");
            if fileId < 0
                diagnostic = macd.source.AppSourceParser.diagnostic( ...
                    "read-failed", "error", string(message), "", ...
                    macd.model.SourceSpan.empty);
                return
            end
            cleanup = onCleanup(@() fclose(fileId));
            bytes = fread(fileId, Inf, "*uint8")';
            clear cleanup
        end

        function result = isValidUtf8(bytes)
            % isValidUtf8 Return true when bytes round-trip through UTF-8 unchanged.
            arguments (Input)
                bytes uint8
            end
            arguments (Output)
                result (1, 1) logical
            end

            % Reject input that decoding would replace with a different byte sequence.
            decoded = native2unicode(bytes, "UTF-8");
            encoded = unicode2native(decoded, "UTF-8");
            result = isequal(bytes, encoded);
        end

        function [className, isAppBase] = findAppBaseClass(statements)
            % findAppBaseClass Locate a supported AppBase class declaration.
            arguments (Input)
                statements macd.source.SourceStatement
            end
            arguments (Output)
                className string
                isAppBase logical
            end

            % Match only one declaration form and leave all others unsupported.
            className = "";
            isAppBase = false;
            pattern = '^classdef\s+(?<name>[A-Za-z]\w*)\s*<\s*matlab\.apps\.AppBase\s*$';
            for index = 1:numel(statements)
                tokens = regexp(char(statements(index).Text), pattern, "names", "once");
                if ~isempty(tokens)
                    className = string(tokens.name);
                    isAppBase = true;
                    return
                end
            end
        end

        function declarations = propertyDeclarations(statements)
            % propertyDeclarations Collect declared types from property blocks.
            arguments (Input)
                statements macd.source.SourceStatement
            end
            arguments (Output)
                declarations containers.Map
            end

            % Track only direct property block lines, never function-local values.
            declarations = containers.Map("KeyType", "char", "ValueType", "any");
            inProperties = false;
            pattern = '^(?<name>[A-Za-z]\w*)\s+(?<type>[A-Za-z]\w*(?:\.[A-Za-z]\w*)*)\s*$';
            for index = 1:numel(statements)
                statement = statements(index);
                text = statement.Text;
                if startsWith(text, "properties")
                    inProperties = true;
                    continue
                end
                if inProperties && text == "end"
                    inProperties = false;
                    continue
                end
                if ~inProperties
                    continue
                end
                tokens = regexp(char(text), pattern, "names", "once");
                if isempty(tokens)
                    continue
                end
                declarations(tokens.name) = struct( ...
                    "DeclaredType", string(tokens.type), "Span", statement.Span);
            end
        end

        function creation = creationMatch(text)
            % creationMatch Match one direct app component factory assignment.
            arguments (Input)
                text string
            end
            arguments (Output)
                creation
            end

            % Require a complete direct assignment to avoid partial source claims.
            creation = [];
            pattern = ['^app\.(?<name>[A-Za-z]\w*)\s*=\s*' ...
                '(?<factory>[A-Za-z]\w*)\s*\((?<arguments>[\s\S]*)\)$'];
            tokens = regexp(char(text), pattern, "names", "once");
            if ~isempty(tokens)
                creation = struct( ...
                    "Name", string(tokens.name), ...
                    "Factory", string(tokens.factory), ...
                    "Arguments", string(tokens.arguments));
            end
        end

        function assignment = assignmentMatch(text)
            % assignmentMatch Match one direct app component property assignment.
            arguments (Input)
                text string
            end
            arguments (Output)
                assignment
            end

            % Restrict matches to direct paths so callbacks and arbitrary code stay opaque.
            assignment = [];
            pattern = ['^app\.(?<component>[A-Za-z]\w*)\.' ...
                '(?<path>[A-Za-z]\w*(?:\.[A-Za-z]\w*)*)\s*=\s*' ...
                '(?<value>[\s\S]+)$'];
            tokens = regexp(char(text), pattern, "names", "once");
            if ~isempty(tokens)
                assignment = struct( ...
                    "ComponentName", string(tokens.component), ...
                    "Path", string(tokens.path), ...
                    "ValueText", string(strtrim(tokens.value)));
            end
        end

        function [parentName, values, isSupported] = creationArguments(text)
            % creationArguments Parse an optional app parent and literal arguments.
            arguments (Input)
                text string
            end
            arguments (Output)
                parentName string
                values cell
                isSupported logical
            end

            % Split top-level commas while preserving nested and quoted arguments.
            parentName = "";
            values = {};
            isSupported = true;
            elements = macd.source.AppSourceParser.splitArguments(char(text));
            if isempty(elements)
                return
            end
            firstElement = string(strtrim(elements{1}));
            parentTokens = regexp(char(firstElement), ...
                '^app\.(?<name>[A-Za-z]\w*)$', "names", "once");
            startIndex = 1;
            if ~isempty(parentTokens)
                parentName = string(parentTokens.name);
                startIndex = 2;
            end
            for index = startIndex:numel(elements)
                [value, isLiteral] = macd.source.MatlabLiteralParser.parse( ...
                    string(elements{index}));
                if ~isLiteral
                    values = {};
                    isSupported = false;
                    return
                end
                values{end + 1} = value;
            end
        end

        function elements = splitArguments(text)
            % splitArguments Split comma-separated source while tracking nesting.
            arguments (Input)
                text char
            end
            arguments (Output)
                elements cell
            end

            % Use the same quote and delimiter rules as the lexical scanner.
            if isempty(strtrim(text))
                elements = {};
                return
            end
            elements = {};
            startOffset = 1;
            parenDepth = 0;
            bracketDepth = 0;
            braceDepth = 0;
            inCharacterVector = false;
            inString = false;
            index = 1;
            while index <= numel(text)
                character = text(index);
                nextCharacter = char(0);
                if index < numel(text)
                    nextCharacter = text(index + 1);
                end
                if character == '''' && ~inString
                    if inCharacterVector && nextCharacter == ''''
                        index = index + 2;
                        continue
                    end
                    inCharacterVector = ~inCharacterVector;
                elseif character == '"' && ~inCharacterVector
                    if inString && nextCharacter == '"'
                        index = index + 2;
                        continue
                    end
                    inString = ~inString;
                elseif ~inCharacterVector && ~inString
                    switch character
                        case '('
                            parenDepth = parenDepth + 1;
                        case ')'
                            parenDepth = max(parenDepth - 1, 0);
                        case '['
                            bracketDepth = bracketDepth + 1;
                        case ']'
                            bracketDepth = max(bracketDepth - 1, 0);
                        case '{'
                            braceDepth = braceDepth + 1;
                        case '}'
                            braceDepth = max(braceDepth - 1, 0);
                    end
                end
                if character == ',' && ~inCharacterVector && ~inString && ...
                        parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
                    elements{end + 1} = text(startOffset:index - 1);
                    startOffset = index + 1;
                end
                index = index + 1;
            end
            elements{end + 1} = text(startOffset:end);
        end

        function result = lineEnding(source)
            % lineEnding Identify the source line-ending convention without rewrite.
            arguments (Input)
                source string
            end
            arguments (Output)
                result string
            end

            % Record the observed convention for later no-edit round-trip work.
            if contains(source, sprintf("\r\n"))
                result = "CRLF";
            elseif contains(source, newline)
                result = "LF";
            else
                result = "None";
            end
        end

        function result = diagnostic(code, severity, message, componentId, span)
            % diagnostic Create one parser diagnostic with optional source context.
            arguments (Input)
                code string
                severity string
                message string
                componentId string
                span macd.model.SourceSpan
            end
            arguments (Output)
                result (1, 1) macd.model.Diagnostic
            end

            result = macd.model.Diagnostic( ...
                code, severity, message, componentId, span);
        end
    end
end

%{
MatlabAppClassDesigner - Conservative read-only parser for AppBase source.
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
