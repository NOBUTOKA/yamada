classdef SourceEffectSummary
    % SourceEffectSummary Derive document-wide execution flags from already bound settings.
    %   This summary inspects model values and catalog metadata only. It neither
    %   parses source text nor evaluates application expressions or callbacks.
    methods (Static)
        function refresh(document, registry)
            % refresh Update execution-effect flags after loading or a proven structural edit.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            % Construction callbacks can mutate any previously created object.
            document.Metadata.HasUnresolvedLifecycleEffects = false;
            document.Metadata.HasUnresolvedExecutableEffects = false;
            document.Metadata.HasUnrecognizedSetter = false;
            for member = document.Components
                concrete = registry.get(member.Factory, member.CreationArguments);
                for setting = member.Settings
                    if setting.ValueKind == "expression"
                        expression = strtrim(string(yamada.source.ComponentNameRewriter.codeMask(setting.SourceExpression)));
                        deferred = startsWith(expression, "@");
                        blocked = string({document.Metadata.InitializationContext.Layout.Methods.Name});
                        inert = yamada.source.InitializationSourceAnalyzer.isLiteralDataCall(setting.SourceExpression, blocked);
                        if ~deferred && ~inert && ~isempty(regexp(expression, '(?<![\w.@])(?:\w+\.)*\w+\s*\(', 'once'))
                            document.Metadata.HasUnresolvedExecutableEffects = true;
                        end
                    end
                    % Audited execution triggers can mutate other components, not only this setter's receiver.
                    if any(setting.Path == ["Parent", "Children"]) || ...
                            (member.Factory == "uitoggletool" && setting.Path == "State") || ...
                            (member.Factory == "uihtml" && any(setting.Path == ["HTMLSource", "Data"]))
                        document.Metadata.HasUnresolvedExecutableEffects = true;
                    end
                    if setting.Path == "CreateFcn" && setting.Method == "nameValue" && ...
                            ~(setting.ValueKind == "literal" && isempty(setting.LiteralValue))
                        document.Metadata.HasUnresolvedLifecycleEffects = true;
                    end
                    if ~any(string({concrete.Properties.Path}) == setting.Path) && ...
                            ~any(setting.Path == ["Layout.Row", "Layout.Column"])
                        document.Metadata.HasUnrecognizedSetter = true;
                    end
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
