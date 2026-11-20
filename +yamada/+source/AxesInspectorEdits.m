classdef AxesInspectorEdits
    % AxesInspectorEdits Plan source-preserving axes text and format edits.
    %   Each patch carries typed occurrence changes for indexed publication and history.

    methods (Static)
        function [batch, requested, forward, inverse, paths] = plan(document, component, path, value, action)
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
                forward (1,1) struct
                inverse (1,1) struct
                paths (1,:) string
            end

            assert(any(yamada.model.AxesInspectorProperties.paths(component.Factory) == path), ...
                "yamada:AxesInspectorEdits:Path", "This setting is unavailable for the selected axes.");
            settings = component.getSettings(path);
            original = yamada.model.PropertySetting.empty;
            if ~isempty(settings), original = settings(end); end
            [shared, canShare, titleValue] = yamada.model.AxesInspectorProperties.subtitleLink(component,path);
            source = document.CurrentText;
            analysis = document.sourceAnalysis();
            forward = struct("Changes",struct("SettingId",{},"Value",{}), ...
                "Placements",struct("Statement",{},"Setting",{},"Offset",{}),"RemovedIds",zeros(1,0));
            inverse = forward;
            paths = path;
            if action == "share"
                assert(canShare && ~shared, "yamada:AxesInspectorEdits:Share", ...
                    "This Subtitle override has no proven Title setting to restore.");
                span = original.SourceSpan;
                edit = struct("Start",span.StartOffset,"End",span.EndOffset,"Text","");
                edits = yamada.source.SourceFormatting.cleanDeletions(source,edit);
                requested = titleValue;
                forward.RemovedIds = original.Id;
                index = analysis.statementIndices(span);
                assert(isscalar(index));
                inverse.Placements = struct("Statement",analysis.Statements(index), ...
                    "Setting",original,"Offset",edits(1).Start-1);
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
                    [edits, placement] = yamada.source.AxesInspectorEdits.insert( ...
                        document,component,path,encoded,requested,original);
                    forward.Placements = placement;
                else
                    assert(original.IsCertain && original.ValueKind == "literal" && ...
                        (original.IsEditable || original.Method == "functionCall") && ~isempty(original.ValueSpan), ...
                        "yamada:AxesInspectorEdits:Ownership", "This source value cannot be replaced safely.");
                    span = original.ValueSpan;
                    before = extractBetween(source,span.StartOffset,span.EndOffset);
                    assert(~contains(before,[string(newline),string(char(13))]), ...
                        "yamada:AxesInspectorEdits:MultilineSource", "The source argument spans multiple physical lines.");
                    edits = struct("Start",span.StartOffset,"End",span.EndOffset,"Text",encoded);
                    affected = original;
                    if original.Method == "functionCall"
                        affected = component.Settings(string({component.Settings.Method}) == "functionCall");
                        affected = affected(arrayfun(@(item) isequal(item.SourceSpan,original.SourceSpan) && ...
                            isequal(item.ValueSpan,span),affected));
                        assert(all([affected.IsCertain]) && all(string({affected.ValueKind}) == "literal"));
                    end
                    paths = unique(string({affected.Path}),"stable");
                    for setting = affected
                        forward.Changes(end+1) = struct("SettingId",setting.Id,"Value",{requested});
                        inverse.Changes(end+1) = struct("SettingId",setting.Id,"Value",{setting.LiteralValue});
                    end
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
            if any(path == ["TickLabelFormat","Colormap"]), member = path; end
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
                case "Colormap"
                    assert(isa(value,"double") && ismatrix(value) && isreal(value) && ...
                        ~isempty(value) && size(value,2) == 3 && all(isfinite(value(:))) && ...
                        all(value(:) >= 0 & value(:) <= 1), ...
                        "yamada:AxesInspectorEdits:Colormap","Choose a colormap with RGB values between zero and one.");
                case {"Exponent","TickLabelRotation"}
                    assert(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value), ...
                        "yamada:AxesInspectorEdits:RulerNumber", "Enter a finite number.");
                    if member == "Exponent"
                        assert(value == fix(value), "yamada:AxesInspectorEdits:RulerExponent", "Enter an integer exponent.");
                    end
                case "SecondaryLabel.String"
                    value = string(value);
                    assert(isscalar(value) && ~ismissing(value), ...
                        "yamada:AxesInspectorEdits:RulerSecondaryLabel", "Enter one secondary label.");
                    if ~isempty(original) && ischar(original.LiteralValue), value = char(value); end
                case "TickLabelFormat"
                    if path == "TickLabelFormat"
                        value = string(validatestring(value,yamada.model.AxesInspectorProperties.formats()));
                    else
                        value = string(value);
                        assert(isscalar(value) && ~ismissing(value) && strlength(value)>0, ...
                            "yamada:AxesInspectorEdits:RulerFormat", "Enter one tick label format.");
                        if ~isempty(original) && ischar(original.LiteralValue), value = char(value); end
                    end
            end
            result = value;
        end

        function [edit, placement] = insert(document,component,path,encoded,value,original)
            % insert Emit one setting beside a proven initialization statement.
            arguments (Input)
                document (1,1) yamada.model.DocumentModel
                component (1,1) yamada.model.ComponentRecord
                path (1,1) string
                encoded (1,1) string
                value
                original yamada.model.PropertySetting
            end
            arguments (Output)
                edit (1,1) struct
                placement (1,1) struct
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
            analysis = document.sourceAnalysis();
            index = analysis.statementIndices(span);
            assert(isscalar(index));
            owner = analysis.Layout.Owner(index);
            method = analysis.Layout.Methods(string({analysis.Layout.Methods.Name}) == owner);
            assert(isscalar(method));
            receiver = "app." + component.Name;
            suffix = "";
            syntax = "assignment";
            if isempty(original) && any(path == ["Title.String","Subtitle.String","XLabel.String","YLabel.String","ZLabel.String","TickLabelFormat"])
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
                assert(~any(string({analysis.Layout.Methods.Name}) == name), ...
                    "yamada:AxesInspectorEdits:ShadowedFunction", "A local method shadows this axes function.");
                prefix = name + "(" + receiver + ", ";
                suffix = ")";
                syntax = "functionCall";
            else
                prefix = receiver + "." + path + " = ";
            end

            raw = prefix + encoded + suffix;
            statement = raw + ";";
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
            first = offset + strlength(statement) - strlength(raw);
            sourceSpan = yamada.model.SourceSpan(first,first + strlength(raw));
            indexed = yamada.source.SourceStatement(raw,sourceSpan,first + (0:strlength(raw)-1));
            snapshot = "";
            if isfield(document.Metadata,"SourceSnapshotId"), snapshot = document.Metadata.SourceSnapshotId; end
            if syntax == "assignment"
                setting = yamada.source.PropertySettingSyntax.assignment(indexed,snapshot,0);
            else
                valueFirst = first + strlength(prefix);
                location = struct("Method","functionCall","Syntax","call","SourceSpan",sourceSpan, ...
                    "ValueSpan",yamada.model.SourceSpan(valueFirst,valueFirst+strlength(encoded)-1), ...
                    "SourceSnapshotId",snapshot,"IsEditable",false);
                setting = yamada.model.PropertySetting(path,value,location);
            end
            batch = yamada.source.SourcePatchBatch(source,edit);
            [scope, valid] = batch.mapSpan(method.Span);
            assert(valid);
            placement = struct("Statement",indexed,"Setting",setting.withScope(owner,scope),"Offset",offset);
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
