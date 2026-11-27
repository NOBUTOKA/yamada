classdef (TestTags = {'ui', 'catalog', 'inspector', 'exhaustive'}) CatalogDefaultProbeTest < matlab.unittest.TestCase
    % CatalogDefaultProbeTest Verify every in-scope catalog variant can read its editable defaults.
    %   The Inspector makes a row read-only when MATLAB defines its value but the
    %   default probe could not read it. This sweep places each variant under its
    %   first allowed parent and requires the probe to read every editable
    %   property, so such rows appear only through a catalog or probe defect.

    properties (TestParameter)
        % Variant - Catalog variant identifiers outside the figure tools.
        Variant = inScopeVariants()
    end

    methods (Test)
        % Guarantee: the default probe reads every editable property of every in-scope variant under its first allowed parent.
        % Failure mode: a new component, parent, or release makes the probe fail, so its Inspector rows become read-only.
        function probeReadsEveryEditableDefault(testCase, Variant)
            % probeReadsEveryEditableDefault Probe one variant without source settings.
            registry = yamada.model.ComponentRegistry.createDefault();
            definition = registry.getById(string(Variant));
            document = yamada.model.NewAppFactory.createEmpty("CatalogDefaultProbe", registry);
            if definition.IsRoot
                component = document.getComponent(document.RootComponentId);
            else
                parentId = fixtureParent(document, registry, definition);
                component = fixtureComponent(document, definition, parentId, "Subject");
            end
            parentFactory = "";
            if strlength(component.ParentId) > 0
                parentFactory = document.getComponent(component.ParentId).Factory;
            end

            % Select the editable properties the Inspector would show for this style.
            properties = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
            style = definition.styleFor(component.CreationArguments);
            editable = arrayfun(@(property) property.IsEditable && property.Editor ~= "readOnly" && ...
                property.AuditDisposition ~= "omitted" && ...
                (isempty(property.ApplicableStyles) || any(property.ApplicableStyles == style)), properties);
            properties = properties(editable);

            results = yamada.ui.inspector.DefaultValueProvider(registry).resolveAll( ...
                component, parentFactory, properties);
            testCase.verifyEmpty(results.Paths(~results.Found), ...
                string(Variant) + " under " + parentFactory);
        end
    end
end

function values = inScopeVariants()
% inScopeVariants Return every catalog variant that Safe Preview renders.
arguments (Output)
    values cell
end
registry = yamada.model.ComponentRegistry.createDefault();
ids = registry.listVariantIds();
inScope = arrayfun(@(id) ~registry.getById(id).IsFigureTool, ids);
values = cellstr(ids(inScope));
end

function component = fixtureComponent(document, definition, parentId, name)
% fixtureComponent Add one catalog record without source settings.
arguments (Input)
    document (1, 1) yamada.model.DocumentModel
    definition (1, 1) yamada.model.ComponentDefinition
    parentId (1, 1) string
    name (1, 1) string
end
arguments (Output)
    component (1, 1) yamada.model.ComponentRecord
end
component = yamada.model.ComponentRecord("probe-" + name, name, definition.Factory, ...
    definition.DeclaredType, "generated");
component.CreationArguments = definition.CreationArguments;
document.addComponent(component, parentId);
end

function id = fixtureParent(document, registry, definition)
% fixtureParent Build the first catalog-allowed parent chain under the root.
arguments (Input)
    document (1, 1) yamada.model.DocumentModel
    registry (1, 1) yamada.model.ComponentRegistry
    definition (1, 1) yamada.model.ComponentDefinition
end
arguments (Output)
    id (1, 1) string
end
if any(definition.AllowedParentFactories == "uifigure"), id = document.RootComponentId; return, end
parent = registry.get(definition.AllowedParentFactories(1));
parentId = fixtureParent(document, registry, parent);
record = fixtureComponent(document, parent, parentId, "Parent" + numel(document.Components));
id = record.Id;
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
