classdef AncestorGeometryPolicy
    % AncestorGeometryPolicy Bound geometry affected by later ancestor resizing.
    %   It preserves explicit inputs while leaving native child reflow unresolved.

    methods (Static)
        function paths = inputPropertyPaths()
            % inputPropertyPaths Declare source settings that can change this policy's document-dependent result.
            arguments (Output)
                paths (1, :) string
            end
            paths = ["Position", "InnerPosition", "OuterPosition", "AutoResizeChildren"];
        end

        function [offset, sequence] = creationAnchor(document)
            % creationAnchor Place new blocks after proven geometry of existing ancestors.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                offset (1, 1) double
                sequence (1, 1) double
            end
            parsed = document.Components(arrayfun(@yamada.model.SourceOwnership.hasSource, document.Components));
            visits = arrayfun(@(item) item.Metadata.InitializationCreationSequence, parsed);
            [~, last] = max(visits);
            anchor = parsed(last);
            offset = anchor.SourceSpans.Creation.EndOffset;
            if ~isfield(anchor.Metadata, "InitializationCreationSequence") || ...
                    ~anchor.Metadata.InitializationCreationCertain
                error("yamada:AncestorGeometryPolicy:UnsafeAnchor", "New component creation requires a certain initialization anchor.");
            end
            sequence = anchor.Metadata.InitializationCreationSequence;
            named = anchor.Settings(string({anchor.Settings.Method}) == "nameValue");
            if ~isempty(named), sequence = max(sequence, max([named.Sequence])); end
            methods = document.Metadata.InitializationContext.Layout.Methods;
            containing = arrayfun(@(item) item.Span.StartOffset <= offset && item.Span.EndOffset >= offset, methods);
            if nnz(containing) ~= 1
                error("yamada:AncestorGeometryPolicy:UnsafeAnchor", "The creation method is ambiguous.");
            end
            scope = methods(containing).Name;
            % Keep the final existing component's settings together before adding another block.
            for setting = anchor.Settings
                if setting.Method == "generated" || ~setting.IsCertain || ...
                        setting.OwnerMethod ~= scope || isempty(setting.SourceSpan) || ...
                        setting.Sequence <= sequence || setting.SourceSpan.EndOffset < offset
                    continue
                end
                offset = setting.SourceSpan.EndOffset;
                sequence = setting.Sequence;
            end
            generated = document.Components(~arrayfun(@yamada.model.SourceOwnership.hasSource, document.Components));
            for member = generated
                parent = document.getComponent(member.ParentId);
                while ~isempty(parent)
                    for setting = parent.Settings
                        if ~any(setting.Path == ["Position", "InnerPosition", "OuterPosition"]) || ...
                                setting.Method == "generated" || setting.Sequence <= sequence, continue, end
                        if ~setting.IsCertain || setting.OwnerMethod ~= scope || ...
                                isempty(setting.SourceSpan) || setting.SourceSpan.EndOffset < offset
                            error("yamada:AncestorGeometryPolicy:UnsafeAnchor", ...
                                "Later ancestor geometry has no proven insertion point in the creation method.");
                        end
                        offset = setting.SourceSpan.EndOffset;
                        sequence = setting.Sequence;
                    end
                    parent = document.getComponent(parent.ParentId);
                end
            end
            % Keep an inline comment attached to its original source statement.
            tail = extractAfter(document.CurrentText, offset);
            lineEnd = regexp(char(tail), '\r?\n', 'start', 'once');
            if isempty(lineEnd), lineEnd = strlength(tail) + 1; end
            suffix = extractBefore(tail, lineEnd);
            if ~isempty(regexp(suffix, '^\s*(%[^\r\n]*)?$', 'once')), offset = offset + strlength(suffix); end
        end

        function result = requiresCombinedPlan(component, document)
            % requiresCombinedPlan Use emitted ordering for pending ancestor geometry.
            arguments (Input)
                component (1, 1) yamada.model.ComponentRecord
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            parent = document.getComponent(component.ParentId);
            while ~isempty(parent)
                result = result || yamada.source.PropertySourcePlan.needsPlan(document, parent);
                parent = document.getComponent(parent.ParentId);
            end
        end

        function states = resolve(states, component, document)
            % resolve Invalidate positions when a later ancestor may reflow children.
            arguments (Input)
                states yamada.model.PropertyState
                component (1, 1) yamada.model.ComponentRecord
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                states yamada.model.PropertyState
            end
            if ~yamada.model.SourceOwnership.hasSource(component), return, end
            paths = ["Position", "InnerPosition", "OuterPosition"];
            sequence = 0;
            if isfield(component.Metadata, "InitializationCreationSequence")
                sequence = component.Metadata.InitializationCreationSequence;
            end
            % A later definite local position supplies its own native input rectangle.
            for setting = component.Settings
                if any(setting.Path == paths) && setting.IsCertain
                    sequence = max(sequence, setting.Sequence);
                end
            end
            parent = document.getComponent(component.ParentId);
            while ~isempty(parent)
                for setting = parent.Settings
                    if ~any(setting.Path == paths) || setting.Sequence <= sequence, continue, end
                    auto = parent.Settings(string({parent.Settings.Path}) == "AutoResizeChildren" & ...
                        [parent.Settings.Sequence] < setting.Sequence);
                    if ~isempty(auto) && auto(end).IsCertain && auto(end).ValueKind == "literal" && ...
                            isequal(string(auto(end).LiteralValue), "off")
                        continue
                    end
                    for index = 1:numel(states)
                        if ~any(states(index).Path == paths), continue, end
                        states(index) = states(index).withEffective([], false, setting.Id, ...
                            "A later ancestor geometry setter may reflow this component; native layout is not modeled.", ...
                            "ancestor-geometry");
                    end
                end
                parent = document.getComponent(parent.ParentId);
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
