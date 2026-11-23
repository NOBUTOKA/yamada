classdef (TestTags = {'fast', 'generation'}) GenerationTest < matlab.unittest.TestCase
    % GenerationTest Verify canonical new-app generation and source writing.
    %   This test class covers generated handle-based structure, safe literal output,
    %   blocking diagnostics, UTF-8 encoding, CRLF lines, and license isolation.

    methods (Test)

        function generatesMinimalRunnableClass(testCase)
            % generatesMinimalRunnableClass Verify the canonical handle-based skeleton.
            % Guarantee: a new app generates the canonical handle-class skeleton.
            % Failure mode: the skeleton drifts from the contract in SPECIFICATION.md and no longer runs or reparses.

            % Generate from the same empty model used by the future editor.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("GeneratedApp", registry);
            generator = yamada.source.NewAppGenerator(registry);

            [source, diagnostics] = generator.generate(document);

            % Check required runtime structure, formatting, and license isolation.
            testCase.verifyGreaterThan(strlength(source), 0);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(source, ...
                "classdef GeneratedApp < handle");
            testCase.verifySubstring(source, ...
                "app.UIFigure = uifigure(""Visible"", ""off"");");
            testCase.verifySubstring(source, "properties (Access = private)");
            testCase.verifySubstring(source, ...
                "arguments (Input)");
            testCase.verifySubstring(source, ...
                "arguments (Output)");
            testCase.verifySubstring(source, "addlistener(app.UIFigure, ""ObjectBeingDestroyed"", @app.figureDeleted);");
            testCase.verifySubstring(source, "delete(app.UIFigure);");
            testCase.verifySubstring(source, "% " + document.ClassName + " ");
            testCase.verifySubstring(source, "% createComponents ");

            % MATLAB recognizes cleanup only when the destructor has no arguments block.
            destructor = extractAfter(source, "function delete(app)");
            testCase.assertNotEmpty(destructor);
            testCase.verifyFalse(contains(destructor, "arguments"));
            testCase.verifySubstring(destructor, "delete(app.UIFigure);");
            if ispc
                testCase.verifyEmpty(regexp(source, "(?<!\r)\n", "once"));
            else
                testCase.verifyEmpty(regexp(source, "\r", "once"));
            end
            testCase.verifyEmpty(regexp(source, "GNU General Public License", "once"));
        end

        function omitsCatalogReadOnlyPropertiesFromGeneratedSource(testCase)
            % omitsCatalogReadOnlyPropertiesFromGeneratedSource Honor setter capabilities across components.
            % Guarantee: generation never writes properties that the catalog marks read-only.
            % Failure mode: generated source assigns a read-only property and errors at run time.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("GridOutputApp", registry);
            outer = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            inner = document.insertComponent(registry, "uigridlayout", outer.Id);
            testCase.verifyEmpty(outer.getProperty("Position"));
            testCase.verifyEmpty(inner.getProperty("Position"));

            % Simulate legacy model values created before read-only insertion was fixed.
            outer.setProperty("Position", [1 1 640 480]);
            inner.setProperty("Position", [1 1 300 200]);
            outer.setProperty("InnerPosition", [1 1 300 200]);
            outer.setProperty("OuterPosition", [1 1 640 480]);
            root = document.getComponent(document.RootComponentId);
            root.setProperty("Number", 1);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            label.setProperty("OuterPosition", [1 1 100 22]);
            table = document.insertComponent(registry, "uitable", document.RootComponentId);
            table.setProperty("DisplayData", {});
            document.setProperty(outer.Id, "RowHeight", {"fit", "1x"});
            generator = yamada.source.NewAppGenerator(registry);
            [source, diagnostics] = generator.generate(document);

            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyFalse(contains(source, "app." + outer.Name + ".Position ="));
            testCase.verifyFalse(contains(source, "app." + inner.Name + ".Position ="));
            testCase.verifyEmpty(regexp(source, ...
                'app\.\w+\.(InnerPosition|OuterPosition|Number|DisplayData)\s*=', "once"));
            testCase.verifySubstring(source, "app.UIFigure.Position =");
            testCase.verifySubstring(source, "app." + outer.Name + ".RowHeight = {""fit"", ""1x""};");
        end

        function classIdentityRewriteUpdatesArgumentsWithoutChangingLiterals(testCase)
            % classIdentityRewriteUpdatesArgumentsWithoutChangingLiterals Rename only class identity syntax.
            % Guarantee: class renaming rewrites identity syntax only.
            % Failure mode: rewriting also changes string literals or comments that contain the class name.
            source = join([ ...
                "classdef OldApp < handle", ...
                "    % OldApp Describe the application.", ...
                "    %       app = OldApp();", ...
                "    methods", ...
                "        function app = OldApp", ...
                "            % OldApp Construct the application.", ...
                "            arguments (Output)", ...
                "                app (1, 1) OldApp", ...
                "            end", ...
                "            app.UIFigure.Name = ""OldApp"";", ...
                "        end", ...
                "        function accept(app, other)", ...
                "            % The OldApp wording in this comment is preserved.", ...
                "            arguments (Input)", ...
                "                app (1, 1) OldApp", ...
                "                other (1, 1) OldApp", ...
                "            end", ...
                "        end", ...
                "    end", ...
                "end"], newline);

            [rewritten, diagnostics] = yamada.source.AppClassIdentityRewriter.rewrite( ...
                source, "SavedApp");

            testCase.verifyEmpty(diagnostics);
            testCase.verifySubstring(rewritten, "classdef SavedApp < handle");
            testCase.verifySubstring(rewritten, "function app = SavedApp");
            testCase.verifyEqual(count(rewritten, "(1, 1) SavedApp"), 3);
            testCase.verifySubstring(rewritten, "% SavedApp Describe the application.");
            testCase.verifySubstring(rewritten, "%       app = SavedApp();");
            testCase.verifySubstring(rewritten, "app.UIFigure.Name = ""OldApp"";");
            testCase.verifySubstring(rewritten, "The OldApp wording in this comment");
        end

        function generatesAndParsesDateOnlyProperties(testCase)
            % generatesAndParsesDateOnlyProperties Round-trip allowlisted native date values.
            % Guarantee: generated date values reparse to the same values.
            % Failure mode: generation emits a datetime form that the safe parser rejects.

            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("DateApp", registry);
            definition = registry.getById("uidatepicker");
            picker = yamada.model.ComponentRecord("date-1", "DatePicker", ...
                definition.Factory, definition.DeclaredType, "generated");
            picker.setProperty("Value", datetime(2024, 2, 29));
            picker.setProperty("Limits", [datetime(2024, 1, 1) datetime(2024, 12, 31)]);
            picker.setProperty("DisabledDates", datetime(2024, 3, 1));
            document.addComponent(picker, document.RootComponentId);

            [source, diagnostics] = yamada.source.NewAppGenerator(registry).generate(document);
            [parsed, parseDiagnostics] = yamada.source.AppSourceParser.parseText(source, registry);
            parsedPicker = parsed.getComponentByName("DatePicker");

            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(source, ...
                "app.DatePicker.Value = datetime(2024, 2, 29);");
            testCase.verifyEqual(parsedPicker.getProperty("Value").LiteralValue, ...
                datetime(2024, 2, 29));
            testCase.verifyEqual(parsedPicker.getProperty("Limits").LiteralValue, ...
                [datetime(2024, 1, 1) datetime(2024, 12, 31)]);
            testCase.verifyEqual(parsedPicker.getProperty("DisabledDates").LiteralValue, ...
                datetime(2024, 3, 1));
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(parseDiagnostics));
        end

        % Guarantee: generation fails with a diagnostic instead of producing invalid or incomplete source.
        % Failure mode: an invalid class name or a source expression is written as empty or broken source.
        function invalidClassNameBlocksGeneration(testCase)
            % invalidClassNameBlocksGeneration Verify fatal name validation.

            % Attempt generation from an intentionally invalid class identity.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("not valid", registry);

            [source, diagnostics] = yamada.source.NewAppGenerator(registry).generate(document);

            testCase.verifyEqual(source, "");
            testCase.verifyTrue(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(diagnostics(1).Code, "invalid-class-name");
        end

        function sourceExpressionIsNeverSilentlyGeneratedAsEmpty(testCase)
            % sourceExpressionIsNeverSilentlyGeneratedAsEmpty Verify safe failure.

            % Replace a safe literal with an unevaluated source expression.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ExpressionApp", registry);
            root = document.getComponent(document.RootComponentId);
            entry = root.getProperty("Name");
            entry.setSourceExpression("getAppName()");

            % Require an explicit diagnostic instead of destructive coercion.
            [source, diagnostics] = yamada.source.NewAppGenerator(registry).generate(document);

            testCase.verifyEqual(source, "");
            testCase.verifyEqual(diagnostics(end).Code, ...
                "nonliteral-new-app-property");
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
