classdef SubtreeSourceEdits
    % SubtreeSourceEdits Capture and patch owned subtree source without execution.

    methods (Static)
        function edits = deletion(components)
            % deletion Collect only the source spans already bound to removed components.
            arguments (Input)
                components
            end
            arguments (Output)
                edits struct
            end

            % Accept live API inputs at the boundary; command state retains source-only values.
            if ~isstruct(components), components = yamada.model.SourceOwnership.snapshot(components); end
            % Use only the spans the model already owns.
            spans = yamada.model.SourceSpan.empty;
            for component = components
                if ~yamada.model.SourceOwnership.hasSource(component), continue, end
                own = [component.SourceSpans.Declaration component.SourceSpans.Creation];
                own = own(arrayfun(@(span) span.isKnown(), own));
                for entry = component.Properties
                    if isempty(entry.SourceSpan) || ~entry.SourceSpan.isKnown(), continue, end
                    own(end + 1) = entry.SourceSpan; %#ok<AGROW>
                end
                for setting = component.Settings
                    if ~isempty(setting.SourceSpan) && setting.SourceSpan.isKnown()
                        own(end + 1) = setting.SourceSpan;
                    end %#ok<AGROW>
                end
                spans = [spans own]; %#ok<AGROW>
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            if isempty(spans), return, end
            [~, uniqueSpans] = unique([[spans.StartOffset]' [spans.EndOffset]'], "rows", "stable");
            spans = spans(uniqueSpans);

            for span = spans
                edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, "Text", ""); %#ok<AGROW>
            end
        end

        function fragments = capture(document, snapshot)
            % capture Freeze owned initializer text with relative offsets for known references.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                snapshot (1, 1) yamada.model.SubtreeSnapshot
            end
            arguments (Output)
                fragments (1, :) struct
            end
            source = document.CurrentText;
            analysis = document.sourceAnalysis();
            fragments = struct("Offset", {}, "Owner", {}, "Text", {}, "Name", {}, ...
                "Parent", {}, "References", {}, "Path", {}, "PlacementArguments", {}, "AxesCall", {}, "Sequence", {});
            placement = [yamada.model.PositionGeometry.rectanglePaths(), "Layout.Row", "Layout.Column"];
            for record = snapshot.Records
                % Use the statement index to deduplicate factory name-value settings.
                current = document.getComponent(record.Id).Settings;
                spans = [record.SourceSpans.Creation [current.SourceSpan]];
                [~, distinct] = unique([spans.StartOffset], "stable");
                for span = spans(distinct)
                    indices = analysis.statementIndices(span, false);
                    assert(isscalar(indices), "yamada:SubtreeSourceEdits:MissingStatement", "The owned statement is missing from the current index.");
                    statement = analysis.Statements(indices(1));
                    code = char(statement.Text);
                    start = statement.Span.StartOffset;
                    stop = max(statement.Span.EndOffset, statement.CodeOffsets(end));
                    raw = extractBetween(source, start, stop);
                    raw = strip(raw, "right");
                    % Preserve the original delimiter and multiline comments.
                    if stop < strlength(source) && extractBetween(source, stop + 1, stop + 1) == ";"
                        raw = raw + ";";
                    end
                    name = regexp(code, '^app\.(?<name>\w+)', 'names', 'once');
                    nameRange = [];
                    if ~isempty(name)
                        nameRange = statement.CodeOffsets([5 4 + strlength(string(name.name))]) - start + 1;
                    end
                    parentRange = []; path = "";
                    references = struct("Range", {}, "Target", {}, "Path", {});
                    placementArguments = struct("Start", {}, "End", {}, "Text", {}, "Path", {});
                    settings = current(arrayfun(@(item) ~isempty(item.SourceSpan) && ...
                        item.SourceSpan.StartOffset == start, current));
                    if isempty(nameRange)
                        % Reviewed axes calls retain their arguments, with an explicit copied target.
                        open = find(code == '(', 1);
                        [first, last] = regexp(code, '(?<=\()\s*app\s*\.\s*\w+', 'once');
                        if isempty(first)
                            boundary = statement.CodeOffsets(open) - start + 2;
                            nameRange = [boundary boundary - 1];
                        else
                            nameRange = statement.CodeOffsets([first last]) - start + 1;
                        end
                    elseif start == record.SourceSpans.Creation.StartOffset
                        [first, last] = regexp(code, '(?<=\()\s*app\.\w+', 'once');
                        if ~isempty(first)
                            parentRange = statement.CodeOffsets([first last]) - start + 1;
                        end
                        if record.Id == snapshot.RootId
                            for setting = settings(ismember(string({settings.Path}), placement))
                                removals = yamada.source.FactoryCallEditor.remove(statement, setting);
                                for removal = removals
                                    placementArguments(end + 1) = struct("Start", removal.Start - start + 1, ...
                                        "End", removal.End - start + 1, "Text", "", "Path", setting.Path); %#ok<AGROW>
                                end
                            end
                        end
                    elseif isscalar(settings)
                        setting = settings(1);
                        path = setting.Path;
                    end
                    % Only recognized component references are retargeted. Opaque RHS text stays intact.
                    for setting = settings(ismember(string({settings.Path}), ["SelectedTab", "SelectedObject", "ContextMenu"]))
                        if setting.ValueKind ~= "expression", continue, end
                        target = yamada.source.SubtreeSourceEdits.referenceTarget( ...
                            document, record.Id, setting.Path, setting.SourceExpression);
                        if isempty(target), continue, end
                        range = [setting.ValueSpan.StartOffset setting.ValueSpan.EndOffset] - start + 1;
                        references(end + 1) = struct("Range", range, "Target", target.Id, "Path", setting.Path); %#ok<AGROW>
                    end
                    sequence = record.Metadata.InitializationCreationSequence;
                    if ~isempty(settings), sequence = min([settings.Sequence]); end
                    fragments(end + 1) = struct("Offset", start, "Owner", record.Id, "Text", raw, ...
                        "Name", nameRange, "Parent", parentRange, "References", references, ...
                        "Path", path, "PlacementArguments", placementArguments, ...
                        "AxesCall", isempty(name), "Sequence", sequence); %#ok<AGROW>
                end
            end
            [~, order] = sortrows([[fragments.Sequence]' [fragments.Offset]']);
            fragments = reshape(fragments(order), 1, []);
        end

        function texts = insertion(snapshot, document, names, parentId, changes)
            % insertion Retarget the copied statements without interpreting their other expressions.
            arguments (Input)
                snapshot (1, 1) yamada.model.SubtreeSnapshot
                document (1, 1) yamada.model.DocumentModel
                names (1, :) string
                parentId (1, 1) string
                changes (1, :) struct
            end
            arguments (Output)
                texts (1, :) string
            end
            ids = string({snapshot.Records.Id});
            paths = string({changes.Path});
            removed = string({changes([changes.Remove]).Path});
            if any(removed == "Position"), paths = [paths "InnerPosition" "OuterPosition"]; end
            texts = strings(1, 0);
            for fragment = snapshot.SourceFragments
                owner = find(ids == fragment.Owner, 1);
                if owner == 1 && any(fragment.Path == paths), continue, end
                name = names(owner);
                if fragment.AxesCall
                    name = "app." + name;
                    if fragment.Name(2) < fragment.Name(1), name = name + ", "; end
                end
                edits = struct("Start", fragment.Name(1), "End", fragment.Name(2), "Text", name);
                if ~isempty(fragment.Parent)
                    if owner == 1
                        parent = document.getComponent(parentId).Name;
                    else
                        parent = names(ids == snapshot.Records(owner).ParentId);
                    end
                    edits(end + 1) = struct("Start", fragment.Parent(1), "End", fragment.Parent(2), "Text", "app." + parent);
                end
                % Internal references follow their renamed copies, and an external target that
                % the destination still holds follows its current name. Component identities are
                % random, so a found identity is the copied target itself; it must still pass the
                % rule Copy applied. Otherwise the reference keeps its copied text and its target
                % is the author's responsibility.
                for reference = fragment.References
                    mapped = find(ids == reference.Target, 1);
                    if isempty(mapped)
                        target = document.getComponent(reference.Target);
                        if isempty(target) || reference.Path ~= "ContextMenu" || ...
                                target.Factory ~= "uicontextmenu" || target.ParentId ~= document.RootComponentId
                            continue
                        end
                        name = target.Name;
                    else
                        name = names(mapped);
                    end
                    edits(end + 1) = struct("Start", reference.Range(1), "End", reference.Range(2), ...
                        "Text", "app." + name); %#ok<AGROW>
                end
                removals = fragment.PlacementArguments;
                if ~isempty(removals)
                    edits = [edits rmfield(removals(ismember(string({removals.Path}), paths)), "Path")]; %#ok<AGROW>
                end
                batch = yamada.source.SourcePatchBatch(fragment.Text, edits);
                texts(end + 1) = batch.AfterText; %#ok<AGROW>
            end
            for change = changes
                if change.Remove, continue, end
                texts(end + 1) = "app." + names(1) + "." + change.Path + " = " + ...
                    yamada.source.LiteralEncoder.encode(change.Value) + ";"; %#ok<AGROW>
            end
        end

        function target = referenceTarget(document, ownerId, path, expression)
            % referenceTarget Identify a recognized static component reference without evaluating its expression.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                ownerId (1, 1) string
                path (1, 1) string
                expression (1, 1) string
            end
            arguments (Output)
                target yamada.model.ComponentRecord
            end
            target = yamada.model.ComponentRecord.empty;
            match = regexp(expression, '^app\.(\w+)$', 'tokens', 'once');
            if isempty(match), return, end
            candidate = document.getComponentByName(string(match{1}));
            if isempty(candidate), return, end
            if path == "ContextMenu"
                compatible = candidate.Factory == "uicontextmenu" && candidate.ParentId == document.RootComponentId;
            else
                compatible = candidate.ParentId == ownerId && ...
                    (path == "SelectedTab" && candidate.Factory == "uitab" || ...
                     path == "SelectedObject" && any(candidate.Factory == ["uiradiobutton", "uitogglebutton"]));
            end
            if compatible, target = candidate; end
        end

        function code = codeMask(source)
            % codeMask Hide literals and comments while preserving source offsets.
            arguments (Input)
                source (1, 1) string
            end
            arguments (Output)
                code char
            end

            text = char(source);
            code = text;
            index = 1;
            block = false;
            while index <= numel(text)
                if block
                    if index < numel(text) && strcmp(text(index:index + 1), '%}')
                        code(index:index + 1) = '  ';
                        index = index + 2;
                        block = false;
                    else
                        if ~ismember(text(index), [char(10) char(13)]), code(index) = ' '; end
                        index = index + 1;
                    end
                elseif text(index) == '%'
                    if index < numel(text) && text(index + 1) == '{', block = true; end
                    while index <= numel(text) && ~ismember(text(index), [char(10) char(13)])
                        code(index) = ' ';
                        index = index + 1;
                    end
                elseif text(index) == '"' || (text(index) == '''' && ...
                        ~(index > 1 && ~isempty(regexp(text(index - 1), '[\w\]\)}."]', 'once'))))
                    quote = text(index);
                    code(index) = ' ';
                    index = index + 1;
                    while index <= numel(text)
                        character = text(index);
                        if ~ismember(character, [char(10) char(13)]), code(index) = ' '; end
                        index = index + 1;
                        if character == quote
                            if index <= numel(text) && text(index) == quote
                                code(index) = ' ';
                                index = index + 1;
                            else
                                break
                            end
                        end
                    end
                else
                    index = index + 1;
                end
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
