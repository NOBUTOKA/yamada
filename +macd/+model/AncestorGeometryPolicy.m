classdef AncestorGeometryPolicy
    % AncestorGeometryPolicy Bound geometry affected by later ancestor resizing.
    %   It preserves explicit inputs while leaving native child reflow unresolved.

    methods (Static)
        function result = requiresCombinedPlan(component, document)
            % requiresCombinedPlan Use emitted ordering for pending ancestor geometry.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            parent = document.getComponent(component.ParentId);
            while ~isempty(parent)
                result = result || macd.source.PropertySourcePlan.needsPlan(document, parent);
                parent = document.getComponent(parent.ParentId);
            end
        end

        function states = resolve(states, component, document)
            % resolve Invalidate positions when a later ancestor may reflow children.
            arguments (Input)
                states macd.model.PropertyState
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                states macd.model.PropertyState
            end
            if component.Origin ~= "parsed", return, end
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
