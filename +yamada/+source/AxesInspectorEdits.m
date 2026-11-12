classdef AxesInspectorEdits
    % AxesInspectorEdits Plan source-preserving axes text and format edits.
    %   The document reparses the emitted candidate before publishing it.

    methods (Static)
        function [batch, requested] = plan(document, component, path, value, action)
            % plan Build a reversible patch against one exact source snapshot.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                path (1,1) string
                value
                action (1,1) string {mustBeMember(action,["set","override","share"])}
            end
            arguments (Output)
                batch (1,1) yamada.source.SourcePatchBatch
                requested
            end

            assert(any(yamada.model.AxesInspectorProperties.paths(component.Factory) == path), ...
                "yamada:AxesInspectorEdits:Path", "This setting is unavailable for the selected axes.");
            settings = component.getSettings(path);
            original = yamada.model.PropertySetting.empty;
            if ~isempty(settings), original = settings(end); end
            [shared, canShare, titleValue] = yamada.model.AxesInspectorProperties.subtitleLink(component,path);
            source = document.CurrentText;
            if action == "share"
                assert(canShare && ~shared, "yamada:AxesInspectorEdits:Share", ...
                    "This Subtitle override has no proven Title setting to restore.");
                span = original.SourceSpan;
                edit = struct("Start",span.StartOffset,"End",span.EndOffset,"Text","");
                edits = yamada.source.SourceFormatting.cleanDeletions(source,edit);
                requested = titleValue;
            else
                if action == "override"
                    assert(shared, "yamada:AxesInspectorEdits:Share", "This setting is already independent.");
                    value = titleValue;
                else
                    assert(~shared, "yamada:AxesInspectorEdits:Share", "Unlink this setting before editing it.");
                end
                requested = yamada.source.AxesInspectorEdits.checkedValue(path,value,original);
                encoded = yamada.source.LiteralEncoder.encode(requested);
                if isempty(original) || action == "override"
                    edits = yamada.source.AxesInspectorEdits.insert(document,component,path,encoded,original);
                else
                    assert(original.IsCertain && original.ValueKind == "literal" && ...
                        (original.IsEditable || original.Method == "functionCall") && ~isempty(original.ValueSpan), ...
                        "yamada:AxesInspectorEdits:Ownership", "This source value cannot be replaced safely.");
                    span = original.ValueSpan;
                    before = extractBetween(source,span.StartOffset,span.EndOffset);
                    assert(~contains(before,[string(newline),string(char(13))]), ...
                        "yamada:AxesInspectorEdits:MultilineSource", "The source argument spans multiple physical lines.");
                    edits = struct("Start",span.StartOffset,"End",span.EndOffset,"Text",encoded);
                end
            end
            batch = yamada.source.SourcePatchBatch(source,edits);
        end
    end

    methods (Static, Access = private)
        function result = checkedValue(path,value,original)
            % checkedValue Validate Inspector inputs and preserve text representation where possible.
            arguments (Input)
                path (1,1) string
                value
                original yamada.model.PropertySetting
            end
            arguments (Output)
                result
            end

            member = extractAfter(path,".");
            if path == "TickLabelFormat", member = path; end
            switch member
                case "String"
                    lines = string(value);
                    assert(isvector(lines) && ~any(ismissing(lines)), ...
                        "yamada:AxesInspectorEdits:Text", "Enter valid text lines.");
                    if isempty(original)
                        value = reshape(lines,1,[]);
                    elseif ischar(original.LiteralValue)
                        if isscalar(lines)
                            value = char(lines);
                        elseif ~isrow(original.LiteralValue)
                            value = char(lines);
                        else
                            value = cellstr(reshape(lines,1,[]));
                        end
                    elseif iscell(original.LiteralValue)
                        value = reshape(cellstr(lines),1,[]);
                    else
                        value = reshape(lines,1,[]);
                    end
                case "Color"
                    try
                        value = validatecolor(value);
                    catch
                        error("yamada:AxesInspectorEdits:Color","Enter a MATLAB color name, hex code, or RGB triplet.");
                    end
                case "FontName"
                    value = string(value);
                    assert(isscalar(value) && ~ismissing(value) && strlength(value)>0, ...
                        "yamada:AxesInspectorEdits:FontName", "Enter one font name.");
                case "FontSize"
                    assert(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && value > 0, ...
                        "yamada:AxesInspectorEdits:FontSize", "Enter a positive font size.");
                case "FontWeight"
                    value = string(validatestring(value,["normal","bold"]));
                case "FontAngle"
                    value = string(validatestring(value,["normal","italic"]));
                case "Interpreter"
                    value = string(validatestring(value,["tex","latex","none"]));
                case "TickLabelFormat"
                    value = string(validatestring(value,yamada.model.AxesInspectorProperties.formats()));
            end
            result = value;
        end

        function edit = insert(document,component,path,encoded,original)
            % insert Emit one setting beside a proven initialization statement.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                path (1,1) string
                encoded (1,1) string
                original yamada.model.PropertySetting
            end
            arguments (Output)
                edit (1,1) struct
            end
            span = component.SourceSpans.Creation;
            assert(~isempty(span) && isfield(component.Metadata,"InitializationCreationCertain") && ...
                component.Metadata.InitializationCreationCertain, ...
                "yamada:AxesInspectorEdits:Creation", "A unique initialization statement is required.");
            if ~isempty(original)
                span = original.SourceSpan;
            else
                settings = component.Settings;
                certain = settings([settings.IsCertain] & string({settings.Method}) ~= "nameValue");
                if ~isempty(certain), span = certain(end).SourceSpan; end
            end
            source = document.CurrentText;
            receiver = "app." + component.Name;
            if isempty(original) && (endsWith(path,".String") || path == "TickLabelFormat")
                switch path
                    case "Title.String"
                        name = "title";
                    case "Subtitle.String"
                        name = "subtitle";
                    case "XLabel.String"
                        name = "xlabel";
                    case "YLabel.String"
                        name = "ylabel";
                    case "ZLabel.String"
                        name = "zlabel";
                    case "TickLabelFormat"
                        name = "geotickformat";
                end
                statement = name + "(" + receiver + ", " + encoded + ");";
            else
                statement = receiver + "." + path + " = " + encoded + ";";
            end

            % Keep a trailing comment attached to its original statement.
            tail = char(extractAfter(source,span.EndOffset));
            lineBreak = regexp(tail,'\r?\n','start','once');
            offset = span.EndOffset;
            ending = string(newline);
            if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
            if ~isempty(lineBreak)
                rest = string(tail(1:lineBreak-1));
                if strlength(strtrim(rest)) == 0 || startsWith(strtrim(rest),"%")
                    offset = offset + lineBreak - 1;
                    statement = ending + yamada.source.SourceFormatting.indent(source,span.StartOffset) + statement;
                else
                    statement = " " + statement;
                end
            else
                statement = " " + statement;
            end
            edit = struct("Start",offset+1,"End",offset,"Text",statement);
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
