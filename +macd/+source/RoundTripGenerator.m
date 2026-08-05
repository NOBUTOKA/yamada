classdef RoundTripGenerator
    % RoundTripGenerator Apply conservative localized edits to parsed AppBase source.
    %   This generator preserves an opened document byte-for-byte until an editable
    %   value changes. It only rewrites owned direct assignments and only inserts
    %   or removes components when declarations and initialization spans are known.

    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods
        function obj = RoundTripGenerator(registry)
            % RoundTripGenerator Create a source-preserving generator.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry = ...
                    macd.model.ComponentRegistry.createDefault()
            end

            obj.Registry = registry;
        end

        function [source, diagnostics] = generate(obj, document)
            % generate Produce a localized source preview for one parsed document.
            arguments (Input)
                obj (1, 1) macd.source.RoundTripGenerator
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                source string
                diagnostics macd.model.Diagnostic
            end

            % New documents keep the canonical generator as their source owner.
            if strlength(document.OriginalText) == 0
                [source, diagnostics] = macd.source.NewAppGenerator(obj.Registry).generate(document);
                return
            end
            source = document.OriginalText;
            diagnostics = macd.validation.ModelValidator.validate(document, obj.Registry);
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                return
            end

            % Build source edits first, then apply them from the end backwards.
            edits = struct("Start", {}, "End", {}, "Text", {});
            deleted = obj.deletedComponents(document);
            for index = 1:numel(deleted)
                [componentEdits, diagnostic] = obj.deletionEdits(source, deleted(index));
                if ~isempty(diagnostic)
                    diagnostics(end + 1) = diagnostic; %#ok<AGROW>
                else
                    edits = [edits componentEdits]; %#ok<AGROW>
                end
            end
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                document.Diagnostics = diagnostics;
                return
            end

            % Rewrite only parsed assignment statements whose literal value changed.
            for index = 1:numel(document.Components)
                component = document.Components(index);
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if entry.ValueKind ~= "literal"
                        continue
                    end
                    if obj.isKnownSpan(entry.SourceSpan)
                        replacement = obj.assignmentText(component, entry, source, ...
                            entry.SourceSpan.StartOffset);
                        original = extractBetween(source, entry.SourceSpan.StartOffset, ...
                            entry.SourceSpan.EndOffset);
                        if ~obj.isUnchangedLiteral(string(original), entry.LiteralValue)
                            edits(end + 1) = obj.edit(entry.SourceSpan, replacement); %#ok<AGROW>
                        end
                    elseif obj.isKnownSpan(component.SourceSpans.Creation)
                        insertion = component.SourceSpans.Creation.EndOffset;
                        text = obj.lineEnding(document) + obj.indent(source, insertion) + ...
                            obj.assignmentText(component, entry, source, insertion);
                        edits(end + 1) = obj.insertion(insertion, text); %#ok<AGROW>
                    end
                end
            end

            % Add generated components only beside a parsed declaration/init section.
            generated = document.Components([document.Components.Origin] == "generated");
            if ~isempty(generated)
                [additionEdits, diagnostic] = obj.additionEdits(source, document, generated);
                if ~isempty(diagnostic)
                    diagnostics(end + 1) = diagnostic;
                else
                    edits = [edits additionEdits];
                end
            end
            if macd.validation.ModelValidator.hasErrors(diagnostics) || ...
                    ~obj.nonOverlapping(edits)
                if ~obj.nonOverlapping(edits)
                    diagnostics(end + 1) = macd.model.Diagnostic("overlapping-source-edits", ...
                        "error", "Source edits overlap and cannot be applied safely.");
                end
                document.Diagnostics = diagnostics;
                return
            end
            source = obj.applyEdits(source, edits);
            document.GeneratedText = source;
            document.Diagnostics = diagnostics;
        end
    end

    methods (Access = private)
        function result = deletedComponents(~, document)
            % deletedComponents Return component records captured by explicit deletion.
            result = macd.model.ComponentRecord.empty;
            for index = 1:numel(document.PendingEdits)
                pending = document.PendingEdits{index};
                if isstruct(pending) && isfield(pending, "Kind") && ...
                        pending.Kind == "delete-component"
                    result(end + 1) = pending.Component; %#ok<AGROW>
                end
            end
        end

        function [edits, diagnostic] = deletionEdits(obj, source, component)
            % deletionEdits Remove a component only when all direct uses are owned.
            edits = struct("Start", {}, "End", {}, "Text", {});
            diagnostic = macd.model.Diagnostic.empty;
            spans = [component.SourceSpans.Declaration component.SourceSpans.Creation];
            if any(~arrayfun(@(span) obj.isKnownSpan(span), spans))
                diagnostic = obj.error("ambiguous-component-deletion", component, ...
                    "Component declaration or creation ownership is unknown.");
                return
            end
            for index = 1:numel(component.Properties)
                entry = component.Properties(index);
                if ~obj.isKnownSpan(entry.SourceSpan)
                    diagnostic = obj.error("ambiguous-component-deletion", component, ...
                        "Component property ownership is unknown.");
                    return
                end
                spans(end + 1) = entry.SourceSpan; %#ok<AGROW>
            end
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            for index = 1:numel(statements)
                statement = statements(index);
                if contains(statement.Text, "app." + component.Name) && ...
                        ~obj.spanContained(statement.Span, spans)
                    diagnostic = obj.error("ambiguous-component-deletion", component, ...
                        "Component is referenced outside editor-owned statements.");
                    return
                end
            end
            for index = 1:numel(spans)
                edits(end + 1) = obj.edit(spans(index), ""); %#ok<AGROW>
            end
        end

        function [edits, diagnostic] = additionEdits(obj, source, document, components)
            % additionEdits Append generated declarations and initialization safely.
            edits = struct("Start", {}, "End", {}, "Text", {});
            diagnostic = macd.model.Diagnostic.empty;
            parsed = document.Components([document.Components.Origin] == "parsed");
            if isempty(parsed)
                diagnostic = macd.model.Diagnostic("ambiguous-component-insertion", ...
                    "error", "No parsed component section is available for safe insertion.");
                return
            end
            declarations = [parsed.SourceSpans];
            declarationSpans = [declarations.Declaration];
            creationSpans = [declarations.Creation];
            if any(~arrayfun(@(span) obj.isKnownSpan(span), declarationSpans)) || ...
                    any(~arrayfun(@(span) obj.isKnownSpan(span), creationSpans))
                diagnostic = macd.model.Diagnostic("ambiguous-component-insertion", ...
                    "error", "Parsed component source spans are incomplete.");
                return
            end
            declarationOffset = max([declarationSpans.EndOffset]);
            creationOffset = max([creationSpans.EndOffset]);
            eol = obj.lineEnding(document);
            declarationsText = "";
            creationText = "";
            for index = 1:numel(components)
                component = components(index);
                parent = document.getComponent(component.ParentId);
                if isempty(parent) || ~obj.isKnownSpan(component.SourceSpans.Creation) && ...
                        parent.Origin == "generated"
                    diagnostic = obj.error("ambiguous-component-insertion", component, ...
                        "Generated component parent initialization is not anchored.");
                    return
                end
                declarationsText = declarationsText + eol + obj.indent(source, declarationOffset) + ...
                    component.Name + " " + component.DeclaredType;
                arguments = "app." + parent.Name;
                for argumentIndex = 1:numel(component.CreationArguments)
                    arguments = arguments + ", " + macd.source.LiteralEncoder.encode( ...
                        component.CreationArguments{argumentIndex});
                end
                creationText = creationText + eol + obj.indent(source, creationOffset) + ...
                    "app." + component.Name + " = " + component.Factory + "(" + arguments + ");";
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if entry.ValueKind ~= "literal"
                        diagnostic = obj.error("nonliteral-component-insertion", component, ...
                            "Generated component has a nonliteral property.");
                        return
                    end
                    creationText = creationText + eol + obj.indent(source, creationOffset) + ...
                        obj.assignmentText(component, entry, source, creationOffset);
                end
            end
            edits = [obj.insertion(declarationOffset, declarationsText), ...
                obj.insertion(creationOffset, creationText)];
        end

        function text = assignmentText(~, component, entry, ~, ~)
            % assignmentText Format one direct assignment using local source indentation.
            text = "app." + component.Name + "." + ...
                entry.Path + " = " + macd.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
        end

        function result = isUnchangedLiteral(~, statementText, value)
            % isUnchangedLiteral Compare one parsed assignment literal to model data.
            result = false;
            tokens = regexp(char(statementText), ...
                '^app\.[A-Za-z]\w*\.[A-Za-z]\w*(?:\.[A-Za-z]\w*)*\s*=\s*(?<value>[\s\S]+)$', ...
                "names", "once");
            if isempty(tokens)
                return
            end
            valueText = string(strtrim(tokens.value));
            if endsWith(valueText, ";")
                valueText = extractBefore(valueText, strlength(valueText));
            end
            [originalValue, isLiteral] = macd.source.MatlabLiteralParser.parse( ...
                valueText);
            result = isLiteral && isequaln(originalValue, value);
        end

        function result = indent(~, source, offset)
            % indent Recover the whitespace preceding one source offset on its line.
            lineStart = find(extractBefore(source, offset) == newline, 1, "last");
            if isempty(lineStart)
                lineStart = 0;
            end
            result = extractBetween(source, lineStart + 1, offset - 1);
            result = string(regexp(char(result), '^\s*', 'match', 'once'));
        end

        function result = lineEnding(~, document)
            % lineEnding Convert the document convention into text for an insertion.
            if document.LineEnding == "CRLF"
                result = sprintf("\r\n");
            else
                result = newline;
            end
        end

        function result = applyEdits(~, source, edits)
            % applyEdits Apply independent inclusive-offset replacements right to left.
            [~, order] = sort([edits.Start], "descend");
            result = source;
            for index = order
                edit = edits(index);
                result = extractBefore(result, edit.Start) + edit.Text + ...
                    extractAfter(result, edit.End);
            end
        end

        function result = nonOverlapping(~, edits)
            % nonOverlapping Check source replacements do not claim the same offsets.
            result = true;
            for first = 1:numel(edits)
                for second = first + 1:numel(edits)
                    if edits(first).Start <= edits(second).End && ...
                            edits(second).Start <= edits(first).End
                        result = false;
                        return
                    end
                end
            end
        end

        function result = spanContained(~, span, containers)
            % spanContained Return true when an owned span fully contains a statement.
            result = false;
            for index = 1:numel(containers)
                container = containers(index);
                if span.StartOffset >= container.StartOffset && ...
                        span.EndOffset <= container.EndOffset
                    result = true;
                    return
                end
            end
        end

        function result = isKnownSpan(~, span)
            % isKnownSpan Return false for an empty optional source span.
            result = ~isempty(span) && span.isKnown();
        end

        function result = edit(~, span, text)
            % edit Create one inclusive source replacement record.
            result = struct("Start", span.StartOffset, "End", span.EndOffset, ...
                "Text", string(text));
        end

        function result = insertion(~, offset, text)
            % insertion Create an insertion immediately after one source offset.
            result = struct("Start", offset + 1, "End", offset, "Text", string(text));
        end

        function result = error(~, code, component, message)
            % error Create one component-scoped source-generation error.
            result = macd.model.Diagnostic(code, "error", message, component.Id);
        end
    end
end

%{
MatlabAppClassDesigner - Conservative localized source round-trip generator.
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
