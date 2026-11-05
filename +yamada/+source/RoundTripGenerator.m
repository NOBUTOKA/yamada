classdef RoundTripGenerator
    % RoundTripGenerator Apply conservative localized edits to parsed handle-based source.
    %   This generator preserves an opened document byte-for-byte until an editable
    %   value changes. It only rewrites owned direct assignments and only inserts
    %   or removes components when declarations and initialization spans are known.

    properties (Access = private)
        Registry yamada.model.ComponentRegistry
        PreparedInsertions struct = struct([])
        PropertyValidationNames string = strings(1, 0)
    end

    methods
        function obj = RoundTripGenerator(registry)
            % RoundTripGenerator Create a source-preserving generator.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry = ...
                    yamada.model.ComponentRegistry.createDefault()
            end

            obj.Registry = registry;
        end

        function [source, diagnostics, edits] = generate(obj, document)
            % generate Produce a localized source preview for one parsed document.
            arguments (Input)
                obj (1, 1) yamada.source.RoundTripGenerator
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                source string
                diagnostics yamada.model.Diagnostic
                edits struct
            end

            edits = struct("Start", {}, "End", {}, "Text", {});
            % New documents keep the canonical generator as their source owner.
            evaluationScope = document.evaluationContext(obj.Registry).readScope(); %#ok<NASGU>
            if strlength(document.CurrentText) == 0
                [source, diagnostics] = yamada.source.NewAppGenerator(obj.Registry).generate(document);
                return
            end
            if isfield(document.Metadata, "SourceSnapshotText") && ...
                    document.Metadata.SourceSnapshotText ~= document.CurrentText
                source = "";
                diagnostics = yamada.model.Diagnostic("stale-source-snapshot", "error", ...
                    "The source baseline changed without reparsing its setting locations.");
                document.Diagnostics = diagnostics;
                return
            end
            source = document.CurrentText;
            diagnostics = yamada.model.Diagnostic.empty;
            % Only the insertion planner may defer validation until its complete source is parsed.
            if isempty(obj.PreparedInsertions)
                diagnostics = yamada.validation.ModelValidator.validate(document, obj.Registry, obj.PropertyValidationNames);
            end
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                return
            end

            % A validated batch may already have emitted every statement for these exact inputs.
            if isempty(obj.PreparedInsertions)
                context = document.evaluationContext(obj.Registry);
                [emitted, found] = context.lookup("complete-insertion-source");
                if found && context.matches(document, obj.Registry)
                    source = emitted;
                    document.GeneratedText = source;
                    document.Diagnostics = diagnostics;
                    return
                end
            end

            % Build source edits first, then apply them from the end backwards.
            edits = struct("Start", {}, "End", {}, "Text", {});
            % Complete subtree ownership includes internal child-parent references.
            for pendingIndex = 1:numel(document.PendingEdits)
                pending = document.PendingEdits{pendingIndex};
                if isstruct(pending) && isfield(pending, "Kind") && pending.Kind == "delete-subtree"
                    try
                        rewrittenReferences = yamada.model.SourceSpan.empty;
                        if isfield(pending, "RewrittenReferences"), rewrittenReferences = pending.RewrittenReferences; end
                        if isfield(pending, "Records"), records = pending.Records;
                        else, records = yamada.model.SourceOwnership.snapshot(pending.Components); end
                        removals = yamada.source.SubtreeSourceEdits.deletion(source, records, rewrittenReferences);
                        edits = [edits removals]; %#ok<AGROW>
                    catch exception
                        diagnostics(end + 1) = yamada.model.Diagnostic("unsafe-subtree-deletion", ...
                            "error", string(exception.message)); %#ok<AGROW>
                    end
                end
            end
            deleted = obj.deletedComponents(document);
            for index = 1:numel(deleted)
                [componentEdits, diagnostic] = obj.deletionEdits(source, deleted(index));
                if ~isempty(diagnostic)
                    diagnostics(end + 1) = diagnostic; %#ok<AGROW>
                else
                    edits = [edits componentEdits]; %#ok<AGROW>
                end
            end
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                document.Diagnostics = diagnostics;
                return
            end

            % Relocate source-owned subtree initialization before ordinary property rewrites.
            relocationAnchor = 0;
            try
                [relocations, movedIds] = yamada.source.SubtreeReparentSourceEdits.build(document, obj.Registry);
                edits = [edits relocations];
                insertion = relocations([relocations.Start] > [relocations.End]);
                if ~isempty(insertion), relocationAnchor = max([insertion.End]); end
            catch exception
                diagnostics(end + 1) = yamada.model.Diagnostic("unsafe-subtree-reparent", ...
                    "error", string(exception.message));
                document.Diagnostics = diagnostics;
                return
            end
            % Rewrite only parsed assignment statements whose literal value changed.
            for index = 1:numel(document.Components)
                component = document.Components(index);
                if any(movedIds == component.Id), continue, end
                if yamada.source.PropertyInsertionPlanner.needsPlan(document, component)
                    try
                        if isempty(obj.PreparedInsertions)
                            insertionEdits = yamada.source.PropertyInsertionPlanner.generationEdits(document, component, obj.Registry);
                        else
                            match = find(string({obj.PreparedInsertions.ComponentId}) == component.Id);
                            if ~isscalar(match)
                                error("yamada:RoundTripGenerator:MissingPreparedInsertion", ...
                                    "Every pending owner needs one prepared insertion plan.");
                            end
                            insertionEdits = obj.PreparedInsertions(match).Edits;
                        end
                        edits = [edits insertionEdits]; %#ok<AGROW>
                    catch exception
                        diagnostics(end + 1) = obj.error("unsafe-property-insertion", component, string(exception.message)); %#ok<AGROW>
                        source = "";
                        document.Diagnostics = diagnostics;
                        return
                    end
                end
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if obj.Registry.isReadOnlyProperty(component.Factory, entry.Path, component.CreationArguments)
                        % Catalog editability never authorizes removing existing source.
                        continue
                    end
                    pending = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == component.Id & ...
                        string({document.CallbackEdits.Name}) == entry.Path);
                    if ~isempty(pending), continue, end
                    if isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                    if entry.ValueKind ~= "literal"
                        continue
                    end
                    if isfield(entry.Metadata, "SourceSettingId")
                        settings = component.getSettings(entry.Path);
                        originalSetting = settings(string({settings.Id}) == string(entry.Metadata.SourceSettingId));
                        if isempty(originalSetting)
                            diagnostics(end + 1) = obj.error("ambiguous-property-setting", component, ...
                                "Property value ownership is unknown."); %#ok<AGROW>
                            source = "";
                            document.Diagnostics = diagnostics;
                            return
                        end
                        if ~isequaln(originalSetting(end).LiteralValue, entry.LiteralValue)
                            edits(end + 1) = obj.edit(entry.Metadata.ValueSpan, ...
                                yamada.source.LiteralEncoder.encode(entry.LiteralValue)); %#ok<AGROW>
                        end
                        continue
                    end
                    if obj.isKnownSpan(entry.SourceSpan)
                        original = extractBetween(source, entry.SourceSpan.StartOffset, ...
                            entry.SourceSpan.EndOffset);
                        if ~obj.isUnchangedLiteral(string(original), entry.LiteralValue)
                            replacement = obj.assignmentText(component, entry, source, ...
                                entry.SourceSpan.StartOffset);
                            edits(end + 1) = obj.edit(entry.SourceSpan, replacement); %#ok<AGROW>
                        end
                    end
                end
            end

            % Add generated components only beside a parsed declaration/init section.
            generated = document.Components(~arrayfun(@yamada.model.SourceOwnership.hasSource, document.Components));
            if ~isempty(generated)
                [additionEdits, diagnostic] = obj.additionEdits(source, document, generated, relocationAnchor, ~isempty(movedIds));
                if ~isempty(diagnostic)
                    diagnostics(end + 1) = diagnostic;
                else
                    edits = [edits additionEdits];
                end
            end
            [callbackEdits, callbackDiagnostics] = yamada.source.CallbackSourceEdits.build(document);
            diagnostics = [diagnostics(:)' callbackDiagnostics(:)'];
            edits = yamada.source.CallbackSourceEdits.combineInsertions([edits callbackEdits]);
            edits = yamada.source.SourceFormatting.cleanDeletions(source, edits);
            edits = yamada.source.SourceFormatting.separateComponents(source, edits, document.sourceAnalysis());
            if yamada.validation.ModelValidator.hasErrors(diagnostics) || ...
                    ~obj.nonOverlapping(edits)
                if ~obj.nonOverlapping(edits)
                    diagnostics(end + 1) = yamada.model.Diagnostic("overlapping-source-edits", ...
                        "error", "Source edits overlap and cannot be applied safely.");
                end
                document.Diagnostics = diagnostics;
                return
            end
            source = obj.applyEdits(source, edits);
            source = yamada.source.ComponentNameRewriter.rewrite(source, document.RenameEdits);
            document.GeneratedText = source;
            document.Diagnostics = diagnostics;
        end
    end

    methods (Access = ?yamada.model.DocumentModel)
        function edits = componentInsertionEdits(obj, document, components)
            % componentInsertionEdits Emit only new component syntax using the existing generation policies.
            arguments (Input)
                obj (1, 1) yamada.source.RoundTripGenerator
                document (1, 1) yamada.model.DocumentModel
                components yamada.model.ComponentRecord
            end
            arguments (Output)
                edits struct
            end
            source = document.CurrentText;
            [edits, diagnostics] = obj.additionEdits(source, document, components);
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            % Property declarations own the CR preceding their newline; insert after that whole line.
            declaration = edits(1); ending = obj.lineEnding(document);
            tail = extractAfter(source, declaration.End); nextLine = strfind(tail, newline);
            assert(~isempty(nextLine), "yamada:DocumentModel:UnsafeSubtreeEdit", "A declaration requires its existing line terminator.");
            declaration.End = declaration.End + nextLine(1); declaration.Start = declaration.End + 1;
            declaration.Text = extractAfter(declaration.Text, strlength(ending)) + ending;
            edits(1) = declaration;
            edits = yamada.source.SourceFormatting.separateComponents(source, edits, document.sourceAnalysis());
        end

        function [source, diagnostics] = generatePropertyCandidate(obj, document, name)
            % generatePropertyCandidate Bound property validation for an otherwise proven document checkpoint.
            arguments (Input)
                obj (1, 1) yamada.source.RoundTripGenerator
                document (1, 1) yamada.model.DocumentModel
                name (1, 1) string
            end
            arguments (Output)
                source string
                diagnostics yamada.model.Diagnostic
            end
            obj.PropertyValidationNames = name;
            [source, diagnostics] = obj.generate(document);
        end
    end

    methods (Access = {?yamada.source.PropertyInsertionPlanner})
        function [source, diagnostics, edits] = generatePreparedInsertions(obj, document, plans)
            % generatePreparedInsertions Emit internal tentative source for mandatory candidate validation.
            %   The value generator keeps these plans private to this call. The caller
            %   must bind the emitted edits and verify every pending request.
            arguments (Input)
                obj (1, 1) yamada.source.RoundTripGenerator
                document (1, 1) yamada.model.DocumentModel
                plans struct
            end
            arguments (Output)
                source string
                diagnostics yamada.model.Diagnostic
                edits struct
            end
            obj.PreparedInsertions = plans;
            [source, diagnostics, edits] = obj.generate(document);
        end
    end

    methods (Access = private)
        function result = deletedComponents(~, document)
            % deletedComponents Return component records captured by explicit deletion.
            result = struct([]);
            for index = 1:numel(document.PendingEdits)
                pending = document.PendingEdits{index};
                if isstruct(pending) && isfield(pending, "Kind") && ...
                        pending.Kind == "delete-component"
                    if isfield(pending, "Record"), record = pending.Record;
                    else, record = yamada.model.SourceOwnership.snapshot(pending.Component); end
                    if isempty(result), result = record; else, result(end + 1) = record; end %#ok<AGROW>
                end
            end
        end

        function [edits, diagnostic] = deletionEdits(obj, source, component)
            % deletionEdits Remove a component only when all direct uses are owned.
            edits = struct("Start", {}, "End", {}, "Text", {});
            diagnostic = yamada.model.Diagnostic.empty;
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
            for setting = component.Settings
                if ~isempty(setting.SourceSpan), spans(end + 1) = setting.SourceSpan; end %#ok<AGROW>
            end
            [~, uniqueSpans] = unique([[spans.StartOffset]' [spans.EndOffset]'], "rows", "stable");
            spans = spans(uniqueSpans);
            statements = yamada.source.MatlabLexicalScanner.splitStatements(source);
            creationText = extractBetween(source, component.SourceSpans.Creation.StartOffset, component.SourceSpans.Creation.EndOffset);
            originalName = regexp(creationText, 'app\.(\w+)\s*=', 'tokens', 'once');
            sourceName = component.Name;
            if ~isempty(originalName), sourceName = string(originalName{1}); end
            for index = 1:numel(statements)
                statement = statements(index);
                if ~isempty(regexp(statement.Text, 'app\s*\.\s*' + sourceName + '(?!\w)', 'once')) && ...
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

        function [edits, diagnostic] = additionEdits(obj, source, document, components, relocationAnchor, initializationEmitted)
            % additionEdits Append generated declarations and initialization safely.
            arguments (Input)
                obj (1, 1) yamada.source.RoundTripGenerator
                source (1, 1) string
                document (1, 1) yamada.model.DocumentModel
                components yamada.model.ComponentRecord
                relocationAnchor (1, 1) double {mustBeNonnegative, mustBeInteger} = 0
                initializationEmitted (1, 1) logical = false
            end
            arguments (Output)
                edits struct
                diagnostic yamada.model.Diagnostic
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            diagnostic = yamada.model.Diagnostic.empty;
            parsed = document.Components(arrayfun(@yamada.model.SourceOwnership.hasSource, document.Components));
            if isempty(parsed)
                diagnostic = yamada.model.Diagnostic("ambiguous-component-insertion", ...
                    "error", "No parsed component section is available for safe insertion.");
                return
            end
            declarations = [parsed.SourceSpans];
            declarationSpans = [declarations.Declaration];
            creationSpans = [declarations.Creation];
            if any(~arrayfun(@(span) obj.isKnownSpan(span), declarationSpans)) || ...
                    any(~arrayfun(@(span) obj.isKnownSpan(span), creationSpans))
                diagnostic = yamada.model.Diagnostic("ambiguous-component-insertion", ...
                    "error", "Parsed component source spans are incomplete.");
                return
            end
            declarationOffset = max([declarationSpans.EndOffset]);
            creationOffset = max([creationSpans.EndOffset relocationAnchor]);
            if ~initializationEmitted
                try
                    creationOffset = yamada.model.AncestorGeometryPolicy.creationAnchor(document);
                catch exception
                    diagnostic = yamada.model.Diagnostic("ambiguous-component-insertion", "error", string(exception.message));
                    return
                end
            end
            eol = obj.lineEnding(document);
            declarationsText = "";
            creationText = "";
            deferredSelection = "";
            for index = 1:numel(components)
                component = components(index);
                parent = document.getComponent(component.ParentId);
                if isempty(parent) || ~yamada.model.SourceOwnership.hasSource(parent) && ...
                        ~any(string({components(1:index - 1).Id}) == parent.Id)
                    diagnostic = obj.error("ambiguous-component-insertion", component, ...
                        "Generated component parent initialization is not anchored.");
                    return
                end
                declarationsText = declarationsText + eol + obj.indent(source, declarationOffset) + ...
                    component.Name + " " + component.DeclaredType;
                if initializationEmitted, continue, end
                arguments = "app." + parent.Name;
                for argumentIndex = 1:numel(component.CreationArguments)
                    arguments = arguments + ", " + yamada.source.LiteralEncoder.encode( ...
                        component.CreationArguments{argumentIndex});
                end
                creationText = creationText + eol + obj.indent(source, creationOffset) + ...
                    "app." + component.Name + " = " + component.Factory + "(" + arguments + ");";
                pending = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == component.Id);
                for callback = pending(:)'
                    if any(callback.Action == ["Add", "New", "Connect"])
                        creationText = creationText + eol + obj.indent(source, creationOffset) + yamada.source.CallbackSourceEdits.bindingText(component.Name, callback.Name, callback.HandlerName, callback.BindingExpression);
                    end
                end
                entries = yamada.model.PropertyApplicationPlanner.forComponent( ...
                    component, document, obj.Registry);
                for propertyIndex = 1:numel(entries)
                    entry = entries(propertyIndex);
                    if obj.Registry.isReadOnlyProperty(component.Factory, entry.Path, component.CreationArguments)
                        continue
                    end
                    if isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                    if entry.ValueKind ~= "literal"
                        diagnostic = obj.error("nonliteral-component-insertion", component, ...
                            "Generated component has a nonliteral property.");
                        return
                    end
                    assignment = eol + obj.indent(source, creationOffset) + ...
                        obj.assignmentText(component, entry, source, creationOffset);
                    if yamada.model.ButtonSelectionPolicy.deferValue(component, entry.Path)
                        deferredSelection = deferredSelection + assignment;
                    else
                        creationText = creationText + assignment;
                    end
                end
            end
            creationText = creationText + deferredSelection;
            if ~initializationEmitted
                try
                    references = yamada.model.SubtreeReferencePolicy.assignments(document, components, obj.Registry);
                    for reference = references
                        creationText = creationText + eol + obj.indent(source, creationOffset) + reference;
                    end
                catch exception
                    diagnostic = yamada.model.Diagnostic("unsafe-component-reference", "error", string(exception.message));
                    return
                end
            end
            edits = [obj.insertion(declarationOffset, declarationsText), ...
                obj.insertion(creationOffset, creationText)];
        end

        function text = assignmentText(~, component, entry, ~, ~)
            % assignmentText Format one direct assignment using local source indentation.
            text = "app." + component.Name + "." + ...
                entry.Path + " = " + yamada.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
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
            [originalValue, isLiteral] = yamada.source.MatlabLiteralParser.parse( ...
                valueText);
            result = isLiteral && isequaln(originalValue, value);
        end

        function result = indent(~, source, offset)
            % indent Recover the whitespace preceding one source offset on its line.
            result = yamada.source.SourceFormatting.indent(source, offset);
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
            result = yamada.model.Diagnostic(code, "error", message, component.Id);
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
