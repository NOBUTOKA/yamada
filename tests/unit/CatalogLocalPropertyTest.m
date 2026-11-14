classdef (TestTags = {'ui', 'model', 'generation', 'exhaustive'}) CatalogLocalPropertyTest < matlab.unittest.TestCase
    % CatalogLocalPropertyTest Compare generic local literal edits with full parsed source across the catalog.
    %   Native getters supply valid inert seeds; source applications and their
    %   callbacks are never instantiated or executed.
    properties (TestParameter)
        % Variant - Registered factory variant exercised by one independently selectable test.
        Variant = catalogVariants()
    end
    methods (Test)
        function provesIndependentLiteralsAcrossAllVariants(testCase, Variant)
            % provesIndependentLiteralsAcrossAllVariants Exercise every eligible source-owned independent contract.
            registry = yamada.model.ComponentRegistry.createDefault();
            variants = string(Variant);
            total = 0; exercisedVariants = 0;
            for variant = reshape(variants, 1, [])
                definition = registry.getById(variant);
                document = yamada.model.NewAppFactory.createEmpty("CatalogLocalFixture", registry);
                if definition.IsRoot
                    component = document.getComponent(document.RootComponentId);
                else
                    parentId = fixtureParent(document, registry, definition);
                    component = fixtureComponent(document, definition, parentId, "Subject");
                end
                figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
                renderer = yamada.ui.PreviewRenderer(registry); handles = renderer.render(document, figure);
                native = [];
                if definition.IsRoot, native = figure;
                elseif isKey(handles, char(component.Id)), native = handles(char(component.Id)); end
                parentFactory = "";
                parent = document.getComponent(component.ParentId);
                if ~isempty(parent), parentFactory = parent.Factory; end
                definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
                paths = strings(1, 0); values = cell(1, 0); eligible = 0;
                for property = reshape(definitions, 1, [])
                    policy = property.Application;
                    schema = property.ValueSchema;
                    if ~property.IsEditable || policy.EffectStatus ~= "independent" || ...
                            policy.EffectPolicy ~= "none" || ~isempty(policy.ApplyAfter) || ~isempty(policy.AffectedPaths) || ...
                            (isfield(schema, "constraints") && ~isempty(schema.constraints))
                        continue
                    end
                    if any(arrayfun(@(other) any(other.Application.ApplyAfter == property.Path), definitions)), continue, end
                    eligible = eligible + 1;
                    [valid, seed, replacement] = catalogLiteralPair(property, native, definition.IsRoot);
                    if ~valid, continue, end
                    component.setProperty(property.Path, seed);
                    paths(end + 1) = property.Path; values{end + 1} = replacement; %#ok<AGROW>
                end
                [source, diagnostics] = yamada.source.NewAppGenerator(registry).generate(document);
                testCase.assertFalse(yamada.validation.ModelValidator.hasErrors(diagnostics), variant + ": " + strjoin(string({diagnostics.Message}), "; ") + "; Paths=" + strjoin(paths, ","));
                testCase.assertGreaterThan(strlength(source), 0, variant);
                parsed = yamada.source.AppSourceParser.parseText(source, registry);
                subject = parsed.getComponentByName(component.Name);
                earlier = yamada.source.PropertySourcePlan.combined(parsed, subject, registry);
                before = parsed.OriginalText;
                count = 0;
                for index = 1:numel(paths)
                    entry = subject.getProperty(paths(index));
                    if isempty(entry) || ~entry.IsEditable || isempty(entry.SourceSpan), continue, end
                    parsed.setProperty(subject.Id, paths(index), values{index}, registry);
                    parsed.validatePropertyCommit(registry);
                    count = count + 1;
                end
                emitted = yamada.source.RoundTripGenerator(registry).generate(parsed);
                reference = yamada.source.AppSourceParser.parseText(emitted, registry);
                referenceSubject = reference.getComponentByName(component.Name);
                for index = 1:numel(paths)
                    actual = subject.getProperty(paths(index));
                    expected = referenceSubject.getProperty(paths(index));
                    if isempty(actual) || isempty(expected), continue, end
                    testCase.verifyEqual(actual.LiteralValue, expected.LiteralValue, variant + "." + paths(index));
                end
                testCase.verifyEqual(parsed.OriginalText, before);
                testCase.verifyEqual(earlier.Document.CurrentText, source);
                if eligible == 0
                    testCase.verifyEmpty(paths, variant);
                    fprintf("CATALOG_LOCAL_NOT_APPLICABLE %s NoIndependentEditableContracts\n", variant);
                else
                    testCase.verifyGreaterThan(count, 0, variant);
                end
                fprintf("CATALOG_LOCAL_VARIANT %s Changes=%d\n", variant, count);
                exercisedVariants = exercisedVariants + (count > 0); total = total + count;
                clear cleanup
            end
            fprintf("CATALOG_LOCAL_COVERAGE Variants=%d Changes=%d\n", exercisedVariants, total);
            testCase.verifyEqual(exercisedVariants, double(eligible > 0));
        end
    end
end

function values = catalogVariants()
% catalogVariants Make each registered variant independently selectable by MATLAB unittest.
arguments (Output)
    values cell
end
registry = yamada.model.ComponentRegistry.createDefault();
values = cellstr(registry.listVariantIds());
end

function component = fixtureComponent(document, definition, parentId, name)
% fixtureComponent Add one catalog record without broadening the product insertion UI.
arguments (Input)
    document (1, 1) yamada.model.DocumentModel
    definition (1, 1) yamada.model.ComponentDefinition
    parentId (1, 1) string
    name (1, 1) string
end
arguments (Output)
    component (1, 1) yamada.model.ComponentRecord
end
component = yamada.model.ComponentRecord("test-" + name, name, definition.Factory, definition.DeclaredType, "generated");
component.CreationArguments = definition.CreationArguments;
document.addComponent(component, parentId);
end

function id = fixtureParent(document, registry, definition)
% fixtureParent Recursively construct the minimal catalog-allowed native parent hierarchy.
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

function [valid, seed, replacement] = catalogLiteralPair(property, native, root)
% catalogLiteralPair Derive two exact serializable values from the native and catalog contracts.
arguments (Input)
    property (1, 1) yamada.model.PropertyDefinition
    native
    root (1, 1) logical
end
arguments (Output)
    valid (1, 1) logical
    seed
    replacement
end
valid = false; seed = []; replacement = [];
schema = property.ValueSchema;
if ~isfield(schema, "kind") || contains(property.Path, "."), return, end
kind = string(schema.kind);
hasNative = ~isempty(native) && isprop(native, property.Path);
if hasNative
    try
        seed = native.(property.Path);
    catch
        return
    end
    if isa(seed, "matlab.lang.OnOffSwitchState"), seed = string(seed); end
    if isa(seed, "handle") || isa(seed, "function_handle"), return, end
end
if kind == "color"
    if ~hasNative, seed = [0 0 0]; end
    replacement = [0.15 0.35 0.55];
elseif any(kind == ["text", "multilineText"])
    if ~hasNative, seed = "Seed"; end
    replacement = "Updated inert literal";
elseif kind == "onOff"
    if ~hasNative, seed = "on"; end
    replacement = "off";
    if string(seed) == "off", replacement = "on"; end
elseif kind == "logical"
    if ~hasNative, seed = false; end
    if ~islogical(seed) || ~isscalar(seed), return, end
    replacement = ~seed;
elseif kind == "enum" && isfield(schema, "values") && numel(schema.values) > 1
    choices = string(schema.values);
    if ~hasNative, seed = choices(1); end
    different = choices(choices ~= string(seed));
    if isempty(different), return, end
    replacement = different(end);
elseif kind == "number" && hasNative && isnumeric(seed) && isscalar(seed) && isfinite(seed)
    replacement = seed + max(1, abs(seed) * 0.1);
elseif kind == "numericArray" && hasNative && isnumeric(seed) && ~isempty(seed) && all(isfinite(seed), "all")
    replacement = seed; replacement(1) = replacement(1) + 0.1;
else
    return
end
% Check schema and native setter acceptance before generating source fixtures.
for value = {seed, replacement}
    transaction = yamada.model.PropertyTransaction(property.Path, value);
    transaction.stage(property.Path, value{1});
    if strlength(yamada.validation.PropertyBatchValidator.validate(property, transaction)) > 0, return, end
    try
        encoded = yamada.source.LiteralEncoder.encode(value{1});
        [decoded, literal] = yamada.source.MatlabLiteralParser.parse(encoded);
        if ~literal || ~isequaln(decoded, value{1}) || contains(encoded, string(newline)), return, end
    catch
        return
    end
end
if hasNative && ~root
    try
        native.(property.Path) = replacement;
        native.(property.Path) = seed;
    catch
        try
            native.(property.Path) = seed;
        catch
            % Invalid proposals do not become source fixtures.
        end
        return
    end
end
valid = ~isequaln(seed, replacement);
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
