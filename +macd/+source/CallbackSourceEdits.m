classdef CallbackSourceEdits
    % CallbackSourceEdits Generate owned callback source replacements without executing code.
    %   This adapter emits original-offset edits and canonical method stubs.
    %   Generators combine its edits with property and component operations.

    methods (Static)
        function [edits, diagnostics] = build(document)
            % build Emit bindings and complete-method removals for pending callback intentions.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                edits struct
                diagnostics macd.model.Diagnostic
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            diagnostics = macd.model.Diagnostic.empty;
            ending = string(newline);
            if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end

            % Validate snapshots and preserve removed handler bodies outside component spans.
            for edit = document.CallbackEdits(:)'
                if edit.OriginalSource ~= document.OriginalText
                    diagnostics(end + 1) = macd.model.Diagnostic("stale-callback-source", "error", ...
                        "Callback ownership belongs to a different source snapshot."); %#ok<AGROW>
                    return
                end
                component = document.getComponent(edit.ComponentId);
                if ~isempty(edit.MethodSpan)
                    edits(end + 1) = struct("Start", edit.MethodSpan.StartOffset, ...
                        "End", edit.MethodSpan.EndOffset, "Text", ""); %#ok<AGROW>
                end
                if isempty(component), continue, end
                binding = "";
                if edit.Action == "Add"
                    binding = "app." + component.Name + "." + edit.Name + ...
                        " = createCallbackFcn(app, @" + edit.HandlerName + ", true);";
                    if edit.MethodAnchor <= 0
                        diagnostics(end + 1) = macd.model.Diagnostic("unsafe-callback-anchor", "error", ...
                            "The callback method insertion anchor is unavailable."); %#ok<AGROW>
                        return
                    end
                    edits(end + 1) = struct("Start", edit.MethodAnchor + 1, "End", edit.MethodAnchor, ...
                        "Text", ending + macd.source.CallbackSourceEdits.methodText(edit, document.ClassName) + ending); %#ok<AGROW>
                end
                if ~isempty(edit.BindingSpan)
                    edits(end + 1) = struct("Start", edit.BindingSpan.StartOffset, ...
                        "End", edit.BindingSpan.EndOffset, "Text", binding); %#ok<AGROW>
                elseif edit.Action == "Add" && component.Origin == "parsed"
                    if edit.BindingAnchor <= 0
                        diagnostics(end + 1) = macd.model.Diagnostic("unsafe-callback-anchor", "error", ...
                            "The callback binding insertion anchor is unavailable."); %#ok<AGROW>
                        return
                    end
                    edits(end + 1) = struct("Start", edit.BindingAnchor + 1, "End", edit.BindingAnchor, ...
                        "Text", ending + "            " + binding); %#ok<AGROW>
                end
            end
        end

        function text = methodText(edit, className)
            % methodText Update generated app argument validation for the current class identity.
            arguments (Input)
                edit (1, 1) macd.model.CallbackEdit
                className (1, 1) string
            end
            arguments (Output)
                text (1, 1) string
            end
            text = regexprep(edit.MethodText, 'app \(1, 1\) [A-Za-z]\w*', "app (1, 1) " + className);
        end

        function edits = combineInsertions(edits)
            % combineInsertions Combine shared insertion anchors before applying source edits.
            arguments (Input)
                edits struct
            end
            arguments (Output)
                edits struct
            end
            % Preserve production order and prevent duplicate identical deletion ranges.
            index = 1;
            while index <= numel(edits)
                other = index + 1;
                while other <= numel(edits)
                    same = edits(index).Start == edits(other).Start && edits(index).End == edits(other).End;
                    if same && edits(index).Start > edits(index).End
                        edits(index).Text = edits(index).Text + edits(other).Text;
                        edits(other) = [];
                    elseif same && edits(index).Text == "" && edits(other).Text == ""
                        edits(other) = [];
                    else
                        other = other + 1;
                    end
                end
                index = index + 1;
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
