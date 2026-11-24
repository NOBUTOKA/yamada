classdef (TestTags = {'fast', 'parser', 'catalog', 'model', 'generation'}) AxisModeSourceTest < matlab.unittest.TestCase
    % AxisModeSourceTest Preserve mode effects through source editing, copying, and saving.
    %   Owned UIAxes fixtures retain original argument order and explicit input
    %   values even when the audited effective value is runtime-computed.

    methods (Test)
        % Guarantee: recognized axes function calls are read in execution order for the right target.
        % Failure mode: a call after opaque code is attributed to the wrong axes, or a shared call's options get the wrong ranges.
        function readsAxesCallsInInitializationOrder(testCase)
            % readsAxesCallsInInitializationOrder Preserve function source and resolve literal effects in order.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", ...
                "app.Control.XLim = [0 3];", "xlim(app.Control, [1 4]);", ...
                "app.Other = uiaxes(app.UIFigure);", "xticks([1 2]);", "box on", ...
                "grid(app.Control, 'off');", "xlabel(app.Control, 'a,b');", ...
                "xticklabels(app.Control, {'A','B'});", ...
                "app.Control.XLimMode = 'auto';"]);
            other = document.getComponentByName("Other");
            limits = control.getSettings("XLim");
            testCase.verifyEqual([limits.Method], ["assignment","functionCall"]);
            testCase.verifyEqual(limits(2).LiteralValue, [1 4]);
            testCase.verifyTrue(limits(2).IsEditable);
            testCase.verifyEqual(control.getSettings("XLabel.String").LiteralValue, 'a,b');
            testCase.verifyEqual(other.getSettings("XTick").LiteralValue, [1 2]);
            testCase.verifyEmpty(control.getSettings("XTick"));
            testCase.verifyEqual(control.getSettings("XTickMode").LiteralValue, "manual");
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyFalse(testCase.state(states,"XLim").IsKnown);
            testCase.verifyEqual(string(testCase.state(states,"ZGrid").EffectiveValue), "off");
            % Both the implicit function call and the command-syntax call are reported.
            codes = string({document.Diagnostics.Code});
            testCase.verifyEqual(nnz(codes == "implicit-axes-target"), 2);
            document.insertComponent(registry, "uibutton", document.RootComponentId);
            testCase.verifyEqual(other.getSettings("XTick").LiteralValue, [1 2]);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        % Guarantee: axes edits keep the existing function-call form and edit paired values together.
        % Failure mode: an edit replaces a function call with assignments, splits geolimits into two steps, or a copy keeps the original target.
        function copyRetargetsRecognizedAxesCalls(testCase)
            % copyRetargetsRecognizedAxesCalls Keep a recognized call with its copied component.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "xlabel(app.Control, 'original');"]);
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), document.RootComponentId, registry);
            testCase.verifySubstring(document.CurrentText, "xlabel(app." + copy.Name + ", 'original');");
            testCase.verifyEqual(copy.getSettings("XLabel.String").LiteralValue, 'original');
            source = document.CurrentText;
            document.undo();
            testCase.verifyEqual(document.CurrentText, document.OriginalText);
            document.redo();
            testCase.verifyEqual(document.CurrentText, source);
        end

        function selectsAxesCallFormsFromRegistryRelease(testCase)
            % selectsAxesCallFormsFromRegistryRelease Retain newer calls on older catalog surfaces.
            % Guarantee and failure mode: shared with readsAxesCallsInInitializationOrder.
            [fixtureDocument, registry] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "xscale(app.Control, 'log');"]);
            catalogs = fileparts(registry.CatalogRoot);
            for release = ["R2023a","R2023b"]
                projected = yamada.catalog.ComponentCatalogLoader.load(fullfile(catalogs,release));
                document = yamada.source.AppSourceParser.parseText(fixtureDocument.OriginalText,projected);
                control = document.getComponentByName("Control");
                settings = control.getSettings("XScale");
                if release == "R2023a"
                    testCase.verifyEmpty(settings);
                else
                    testCase.assertNumElements(settings,1);
                    testCase.verifyEqual(settings.Method,"functionCall");
                    testCase.verifyEqual(string(settings.LiteralValue),"log");
                end
                testCase.verifyEqual(yamada.source.RoundTripGenerator(projected).generate(document),fixtureDocument.OriginalText);
            end
        end

        function editsNumericRulerTickFormats(testCase)
            % editsNumericRulerTickFormats Preserve function syntax and emit direct new assignments.
            % Guarantee and failure mode: shared with copyRetargetsRecognizedAxesCalls.
            [document, registry, component] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "xtickformat(app.Control, '%.1f'); % keep"]);
            testCase.verifyEqual(string(component.getSettings("XAxis.TickLabelFormat").LiteralValue),"%.1f");
            % xtickformat also returns manual tick labels to automatic labels.
            testCase.verifyEqual(string(component.getSettings("XTickLabelMode").LiteralValue),"auto");
            document.editAxesInspector(component.Id,"XAxis.TickLabelFormat","%.2f","set",registry);
            document.editAxesInspector(component.Id,"YAxis.TickLabelFormat","%.3f","set",registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source,"xtickformat(app.Control, '%.2f'); % keep");
            testCase.verifySubstring(source,'app.Control.YAxis.TickLabelFormat = "%.3f";');
            reloaded = yamada.source.AppSourceParser.parseText(source,registry);
            owner = reloaded.getComponentByName("Control");
            testCase.verifyEqual(string(owner.getSettings("YAxis.TickLabelFormat").LiteralValue),"%.3f");
            document.undo();
            testCase.verifyEmpty(component.getSettings("YAxis.TickLabelFormat"));
        end

        function savesNumericRulerExponentAndThetaRotation(testCase)
            % savesNumericRulerExponentAndThetaRotation Preserve validated nested numeric assignments.
            fixtures = ["uiaxes","XAxis.Exponent", "2"; "polaraxes","ThetaAxis.TickLabelRotation","25"];
            for index = 1:size(fixtures,1)
                factory = fixtures(index,1);
                path = fixtures(index,2);
                value = str2double(fixtures(index,3));
                [document, registry, component] = testCase.fixture( ...
                    "app.Control = " + factory + "(app.UIFigure);", factory);
                document.editAxesInspector(component.Id,path,value,"set",registry);
                source = yamada.source.RoundTripGenerator(registry).generate(document);
                testCase.verifySubstring(source,"app.Control." + path + " = " + fixtures(index,3) + ";");
                reloaded = yamada.source.AppSourceParser.parseText(source,registry);
                owner = reloaded.getComponentByName("Control");
                testCase.verifyEqual(owner.getSettings(path).LiteralValue,value);
                document.undo();
                testCase.verifyEmpty(component.getSettings(path));
            end
        end

        function editsSecondaryLabelWithTheAvailableSourceForm(testCase)
            % editsSecondaryLabelWithTheAvailableSourceForm Use the release's call form when one exists.
            [document, registry, component] = testCase.fixture("app.Control = uiaxes(app.UIFigure);");
            path = "XAxis.SecondaryLabel.String";
            document.editAxesInspector(component.Id,path,"units","set",registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            if isempty(yamada.catalog.AxesSettingFunctionCatalog.forName("xsecondarylabel",registry.CatalogRoot))
                testCase.verifySubstring(source,'app.Control.XAxis.SecondaryLabel.String = "units";');
            else
                testCase.verifySubstring(source,'xsecondarylabel(app.Control, "units");');
            end
            [calls, registry, component] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "xsecondarylabel(app.Control, 'units');"]);
            if isempty(yamada.catalog.AxesSettingFunctionCatalog.forName("xsecondarylabel",registry.CatalogRoot))
                testCase.verifyEmpty(component.getSettings(path));
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(calls),calls.OriginalText);
            else
                calls.editAxesInspector(component.Id,path,"new units","set",registry);
                testCase.verifySubstring(yamada.source.RoundTripGenerator(registry).generate(calls), ...
                    "xsecondarylabel(app.Control, 'new units');");
            end
        end

        function readsPolarCallsAndWarnsWhenTargetIsLost(testCase)
            % readsPolarCallsAndWarnsWhenTargetIsLost Stop inference after opaque code and accept explicit targets.
            % Guarantee and failure mode: shared with readsAxesCallsInInitializationOrder.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = polaraxes(app.UIFigure);", "rlim([0 5]);", ...
                "opaque();", "thetalim([0 90]);", "thetaticks(app.Control, [0 90]);", ...
                "rticklabels(app.Control, 'auto');"], "polaraxes");
            testCase.verifyEqual(control.getSettings("RLim").LiteralValue, [0 5]);
            testCase.verifyEmpty(control.getSettings("ThetaLim"));
            testCase.verifyEqual(control.getSettings("ThetaTick").LiteralValue, [0 90]);
            testCase.verifyEqual(string(control.getSettings("RTickLabelMode").LiteralValue), "auto");
            testCase.verifyTrue(any(string({document.Diagnostics.Code}) == "unresolved-axes-target"));
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        function retainsRequestedGeographicLimitsInSourceOrder(testCase)
            % retainsRequestedGeographicLimitsInSourceOrder Replay one pair without inventing display values.
            % Guarantee and failure mode: shared with copyRetargetsRecognizedAxesCalls.
            [document, registry, component] = testCase.fixture([ ...
                "app.Control = geoaxes(app.UIFigure, Basemap='none');", ...
                "geolimits(app.Control, [-15 15], [170 -170]); % crosses the antimeridian", ...
                "app.Control.MapCenter = [5 180];", ...
                "geolimits(app.Control, 'manual');", "geolimits('auto');"],"geoaxes");
            testCase.verifyEqual(component.getSettings("RequestedLatitudeLimits").LiteralValue,[-15 15]);
            testCase.verifyEqual(component.getSettings("RequestedLongitudeLimits").LiteralValue,[170 -170]);
            testCase.verifyEmpty(component.getSettings("LatitudeLimits"));
            testCase.verifyEmpty(component.getSettings("LongitudeLimits"));
            modes = component.getSettings("GeographicLimitsMode");
            testCase.verifyEqual(string({modes.LiteralValue}),["manual","auto"]);
            entries = yamada.model.PropertyApplicationPlanner.forPreview(component,document,registry);
            paths = string({entries.Path});
            geographic = find(paths == "GeographicLimits");
            testCase.assertNumElements(geographic,3);
            testCase.verifyEqual(entries(geographic(1)).LiteralValue,{[-15 15],[170 -170]});
            center = find(paths == "MapCenter");
            testCase.assertNumElements(center,1);
            testCase.verifyGreaterThan(center,geographic(1));
            testCase.verifyLessThan(center,geographic(2));
            testCase.verifyTrue(any(string({document.Diagnostics.Code}) == "implicit-axes-target"));
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document),document.OriginalText);
        end

        function editsGeographicLimitsAsOneSourceTransaction(testCase)
            % editsGeographicLimitsAsOneSourceTransaction Save both limits and undo them together.
            [document,registry,component] = testCase.fixture( ...
                "app.Control = geoaxes(app.UIFigure, Basemap='none'); % keep","geoaxes");
            original = document.CurrentText;
            document.editAxesInspector(component.Id,"GeographicLimits",[-15 15;170 -170],"set",registry);
            inserted = document.CurrentText;
            testCase.verifySubstring(inserted,"geolimits(app.Control, [-15 15], [170 -170]);");
            testCase.verifySubstring(inserted,"% keep");
            document.editAxesInspector(component.Id,"GeographicLimits",[-10 20;170 190],"set",registry);
            edited = document.CurrentText;
            testCase.verifySubstring(edited,"geolimits(app.Control, [-10 20], [170 190]);");
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document),edited);
            document.undo();
            testCase.verifyEqual(document.CurrentText,inserted);
            document.undo();
            testCase.verifyEqual(document.CurrentText,original);
            testCase.verifyEmpty(component.getSettings("RequestedLatitudeLimits"));
            document.redo();
            document.redo();
            testCase.verifyEqual(document.CurrentText,edited);
        end

        function readsGeographicSettingsThroughOtherEdits(testCase)
            % readsGeographicSettingsThroughOtherEdits Keep multi-effect calls through local source publication.
            % Guarantee and failure mode: shared with readsAxesCallsInInitializationOrder.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = geoaxes(app.UIFigure, Basemap='none');", ...
                "geotickformat(app.Control, 'dd');", "grid(app.Control, 'off');", ...
                "clim(app.Control, [1 3]);", "app.Control.FontSize = 12;"], "geoaxes");
            testCase.verifyEqual(string(control.getSettings("TickLabelFormat").LiteralValue), "dd");
            testCase.verifyEqual(control.getSettings("CLim").LiteralValue, [1 3]);
            testCase.verifyEqual(string(control.getSettings("Grid").LiteralValue), "off");
            before = [control.Settings.Sequence];
            document.setProperty(control.Id, "FontSize", 15, registry);
            testCase.verifyEqual([control.Settings.Sequence], before);
            testCase.verifyEqual(control.getSettings("CLim").LiteralValue, [1 3]);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        function readsRotationForTheApplicableAxes(testCase)
            % readsRotationForTheApplicableAxes Read radial rotation and preserve an inapplicable Cartesian call.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = polaraxes(app.UIFigure);", ...
                "rtickangle(app.Control, 25);", ...
                "xtickangle(app.Control, 35);"], "polaraxes");
            testCase.verifyEqual(control.getSettings("RTickLabelRotation").LiteralValue,25);
            testCase.verifyEmpty(control.getSettings("XTickLabelRotation"));
            testCase.verifyEqual(nnz(string({document.Diagnostics.Code}) == "unresolved-initialization-call"),1);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document),document.OriginalText);
        end

        function readsSharedTitleOptionsWithIndependentTextRanges(testCase)
            % readsSharedTitleOptionsWithIndependentTextRanges Keep multiline text and shared style ownership.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", ...
                "title(app.Control, {'First','Second'}, ""Subtitle"", Color=[1 0 0]);"]);
            title = control.getSettings("Title.String");
            subtitle = control.getSettings("Subtitle.String");
            titleColor = control.getSettings("Title.Color");
            subtitleColor = control.getSettings("Subtitle.Color");
            testCase.verifyEqual(title.LiteralValue,{'First','Second'});
            testCase.verifyEqual(subtitle.LiteralValue,"Subtitle");
            testCase.verifyNotEqual(title.ValueSpan,subtitle.ValueSpan);
            testCase.verifyEqual(titleColor.ValueSpan,subtitleColor.ValueSpan);
            testCase.verifyEqual(titleColor.LiteralValue,[1 0 0]);
            testCase.verifyEqual(extractBetween(document.OriginalText,titleColor.ValueSpan.StartOffset, ...
                titleColor.ValueSpan.EndOffset),"[1 0 0]");
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document),document.OriginalText);
        end

        function editsAxesTextAndSubtitleLink(testCase)
            % editsAxesTextAndSubtitleLink Preserve a shared call and undo independent Subtitle settings.
            % Guarantee and failure mode: shared with copyRetargetsRecognizedAxesCalls.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", ...
                "title('Before', 'Sub', Color=[1 0 0]);"]);
            id = control.Id;
            document.editAxesInspector(id,"Title.String",["First","Second"],"set",registry);
            testCase.verifySubstring(document.CurrentText,"title({'First', 'Second'}, 'Sub', Color=[1 0 0]);");
            testCase.verifyTrue(any(string({document.Diagnostics.Code}) == "implicit-axes-target"));
            document.editAxesInspector(id,"Title.Color",[0 0 1],"set",registry);
            testCase.verifyEqual(control.getSettings("Subtitle.Color").LiteralValue,[0 0 1]);
            document.undo();
            testCase.verifyEqual(control.getSettings("Subtitle.Color").LiteralValue,[1 0 0]);
            testCase.verifyTrue(yamada.model.AxesInspectorProperties.subtitleLink(control,"Subtitle.Color"));
            document.editAxesInspector(id,"Subtitle.Color",[],"override",registry);
            testCase.verifyFalse(yamada.model.AxesInspectorProperties.subtitleLink(control,"Subtitle.Color"));
            document.editAxesInspector(id,"Subtitle.Color",[0 1 0],"set",registry);
            testCase.verifyEqual(control.getSettings("Title.Color").LiteralValue,[1 0 0]);
            testCase.verifyEqual(control.getProperty("Subtitle.Color").LiteralValue,[0 1 0]);
            document.editAxesInspector(id,"Subtitle.Color",[],"share",registry);
            testCase.verifyTrue(yamada.model.AxesInspectorProperties.subtitleLink(control,"Subtitle.Color"));
            reopened = yamada.source.AppSourceParser.parseText(document.CurrentText,registry);
            testCase.verifyTrue(yamada.model.AxesInspectorProperties.subtitleLink( ...
                reopened.getComponentByName("Control"),"Subtitle.Color"));
            document.undo();
            testCase.verifyEqual(control.getProperty("Subtitle.Color").LiteralValue,[0 1 0]);
            document.redo();
            testCase.verifyTrue(yamada.model.AxesInspectorProperties.subtitleLink(control,"Subtitle.Color"));
        end

        function insertsAndEditsGeographicFormat(testCase)
            % insertsAndEditsGeographicFormat Generate the explicit target form and update its value locally.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = geoaxes(app.UIFigure, Basemap='none');","geoaxes");
            original = document.CurrentText;
            document.editAxesInspector(control.Id,"TickLabelFormat","dd","set",registry);
            testCase.verifySubstring(document.CurrentText,'geotickformat(app.Control, "dd");');
            document.editAxesInspector(control.Id,"TickLabelFormat","-dm","set",registry);
            testCase.verifySubstring(document.CurrentText,'geotickformat(app.Control, "-dm");');
            testCase.verifyEqual(string(control.getSettings("TickLabelFormat").LiteralValue),"-dm");
            document.undo();
            document.undo();
            testCase.verifyEqual(document.CurrentText,original);
            testCase.verifyEmpty(control.getSettings("TickLabelFormat"));
            document.redo();
            document.redo();
            testCase.verifyEqual(string(control.getSettings("TickLabelFormat").LiteralValue),"-dm");
        end

        % Guarantee: mode and value edits produce the requested final mode without inventing computed values.
        % Failure mode: an added value silently switches a final auto mode to manual, or computed ticks are written as literals.
        function pendingModeIsAddedAfterExistingConstructorValue(testCase)
            % pendingModeIsAddedAfterExistingConstructorValue Prefer the reviewed call after constructor values while preserving a requested final auto mode.
            for factory = ["uiaxes", "axes"]
                for syntax = ["equals", "quoted"]
                    if syntax == "equals"
                        creation = "app.Control = " + factory + "(app.UIFigure, Units='pixels', Position=[10 20 200 100], XTick=[0 1]);";
                    else
                        creation = "app.Control = " + factory + "(app.UIFigure, 'Units', 'pixels', 'Position', [10 20 200 100], 'XTick', [0 1]);";
                    end
                    [document, registry, control] = testCase.fixture(creation, factory);
                    original = control.settingSnapshot();
                    document.setProperty(control.Id, "XTickMode", "auto", registry);
                    source = yamada.source.RoundTripGenerator(registry).generate(document);
                    saved = yamada.source.AppSourceParser.parseText(source, registry);
                    other = saved.getComponentByName("Control");
                    setting = other.getSettings("XTickMode");
                    testCase.verifyNumElements(setting, 1);
                    testCase.verifyEqual(setting.Method, "functionCall");
                    testCase.verifyGreaterThan(setting.ValueSpan.StartOffset, other.getSettings("XTick").ValueSpan.StartOffset);
                    states = saved.getEffectivePropertyStates(registry, other.Id);
                    testCase.verifyEqual(testCase.state(states, "XTickMode").EffectiveValue, "auto");
                    testCase.verifyFalse(testCase.state(states, "XTick").IsKnown);
                    after = control.settingSnapshot();
                    testCase.verifyEqual(SourceAssertions.retained(after, original), SourceAssertions.semantics(original));
                    testCase.verifyNumElements(after, numel(original) + 1);
                    document.undo();
                    testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
                    document.redo();
                    testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
                end
            end
        end

        % Guarantee: A value implied by a call, which owns no token, is changed by a new setting after that call.
        % Failure mode: Rewriting the call discards its own argument, a miscounted call statement shifts the execution order of every later setting, or the edit overwrites the call's implied value so Undo keeps the new mode.
        function impliedModeIsSupersededAfterItsCall(testCase)
            % impliedModeIsSupersededAfterItsCall Keep the implying call and order the new mode after it.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "xlim(app.Control, [1 4]);", ...
                "app.Control.YLim = [0 2];"]);
            document.setPropertyBatch(control.Id, struct("Path", "XLimMode", "Value", "auto"), registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source, "xlim(app.Control, [1 4]);");
            testCase.verifyLessThan(strfind(source, "xlim(app.Control, [1 4]);"), ...
                regexp(source, "xlim\(app\.Control, [""']auto[""']\);"));
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(string(testCase.state(states, "XLimMode").EffectiveValue), "auto");
            testCase.verifyEqual(testCase.state(states, "YLim").EffectiveValue, [0 2]);
            reloaded = yamada.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual([control.Settings.Sequence], [reloaded.getComponentByName("Control").Settings.Sequence]);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            % The implying call keeps its implied value, so Undo restores the manual mode.
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(string(testCase.state(states, "XLimMode").EffectiveValue), "manual");
        end

        % Guarantee: Editing one axis limit of an axis limits vector rewrites only its elements, and slice edits in one batch compose.
        % Failure mode: Treating a slice as the whole token overwrites the other axes, two slice edits produce overlapping patches, or a stale span misplaces later edits.
        function axisLimitSlicesShareOneVectorToken(testCase)
            % axisLimitSlicesShareOneVectorToken Rewrite only the edited limits and keep the vector reloadable.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "axis(app.Control, [0 1 2 3]);"]);
            document.setPropertyBatch(control.Id, struct("Path", "XLim", "Value", [5 9]), registry);
            document.setPropertyBatch(control.Id, struct("Path", {"XLim", "YLim"}, "Value", {[1 2], [7 8]}), registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source, "axis(app.Control, [1 2 7 8]);");
            reloaded = yamada.source.AppSourceParser.parseText(source, registry).getComponentByName("Control");
            testCase.verifyEqual([reloaded.getSettings("XLim").LiteralValue, reloaded.getSettings("YLim").LiteralValue], [1 2 7 8]);
            document.undo(); document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        % Guarantee: A value whose call token also sets other paths, such as XLimitMethod of axis tight, is changed by a new setting after the call, and Undo and Redo restore both states.
        % Failure mode: Rewriting the shared token changes the other axes, the coupled edit is rejected as read-only, or Undo leaves an ordinary value in place of the call binding.
        function sharedCallTokenIsSupersededAfterItsCall(testCase)
            % sharedCallTokenIsSupersededAfterItsCall Keep axis tight and add the requested method after it.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "axis(app.Control, ""tight"");"]);
            document.setPropertyBatch(control.Id, struct("Path", "XLimitMethod", "Value", "padded"), registry);
            edited = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(edited, "axis(app.Control, ""tight"");" + sprintf('\r\n') + ...
                "app.Control.XLimitMethod = ""padded"";");
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(string(testCase.state(states, "YLimitMethod").EffectiveValue), "tight");
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            testCase.verifyFalse(control.getProperty("XLimitMethod").IsEditable);
            document.redo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), edited);
        end

        % Guarantee: Choosing an axis style rewrites only the keyword of the last axis call, rebuilds that call's implied ratio and limit settings, leaves later overriding settings in place, writes a new call after every setting when none exists, and Undo restores the original call and its effects.
        % Failure mode: The edit adds a second call, drops or duplicates the later assignment, keeps the old keyword's effects, changes the quote style, or Undo leaves the new effects recorded.
        % sharedCallTokenIsSupersededAfterItsCall edits one effect after a call; this test detects a change of the call's own keyword and the effects it implies.
        function axisStyleKeywordIsReplacedInPlace(testCase)
            % axisStyleKeywordIsReplacedInPlace Switch equal to square and insert image where no call exists.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "axis(app.Control, 'equal');", ...
                "app.Control.DataAspectRatio = [1 2 1];"]);
            callPaths = @(component) string({component.Settings(arrayfun(@(setting) ...
                isequal(setting.SourceSpan, component.getSettings("AxisStyle").SourceSpan), component.Settings)).Path});
            document.editAxesInspector(control.Id, "AxisStyle", "square", "set", registry);
            edited = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(edited, "axis(app.Control, 'square');" + sprintf('\r\n') + ...
                "app.Control.DataAspectRatio = [1 2 1];");
            testCase.verifyEqual(count(edited, "axis("), 1);
            testCase.verifyEqual(sort(callPaths(control)), formPaths(registry,"axis.square"));
            testCase.verifyEqual(control.getSettings("DataAspectRatio").Method, "assignment");
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            testCase.verifyEqual(sort(callPaths(control)), formPaths(registry,"axis.equal"));
            document.redo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), edited);

            % Without a call, the chosen keyword is written after every certain setting.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "app.Control.Box = 'on';"]);
            document.editAxesInspector(control.Id, "AxisStyle", "image", "set", registry);
            testCase.verifySubstring(document.CurrentText, "app.Control.Box = 'on';" + sprintf('\r\n') + ...
                "axis(app.Control, ""image"");");
            testCase.verifyEqual(sort(callPaths(control)), formPaths(registry,"axis.image"));
        end

        % Guarantee: An axis call of several aspect-ratio keywords, such as axis(ax, 'equal', 'vis3d'), is read as each keyword's catalog effects in order; the style and the vis3d toggle edit the keyword list of that one call in its quote style, a call left without keywords is removed, and Undo restores the call.
        % Failure mode: The combined call is kept as unrecognized source, a later normal still shows vis3d in effect, the style edit drops vis3d, the toggle writes a second call or leaves an empty call, or Undo leaves the edited keywords.
        % axisStyleKeywordIsReplacedInPlace edits a call of one keyword; this test detects the keyword list of a combined call.
        function combinedAxisKeywordsAreReadAndEdited(testCase)
            % combinedAxisKeywordsAreReadAndEdited Read equal with vis3d, then change the style and remove vis3d.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "axis(app.Control, 'equal', 'vis3d');"]);
            call = control.getSettings("AxisStyle");
            testCase.verifyNumElements(call, 2);
            callPaths = string({control.Settings(arrayfun(@(setting) ...
                isequal(setting.SourceSpan, call(1).SourceSpan), control.Settings)).Path});
            testCase.verifyEqual(sort(callPaths), sort([formPaths(registry,"axis.equal") formPaths(registry,"axis.vis3d")]));
            [style, vis3d] = yamada.model.AxesInspectorProperties.axisKeywordState(call);
            testCase.verifyEqual([style string(vis3d)], ["equal" "true"]);

            % The style keeps vis3d, and turning vis3d off removes only its keyword.
            document.editAxesInspector(control.Id, "AxisStyle", "square", "set", registry);
            testCase.verifySubstring(document.CurrentText, "axis(app.Control, 'square', 'vis3d');");
            document.editAxesInspector(control.Id, "AxisVis3d", false, "set", registry);
            edited = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(edited, "axis(app.Control, 'square');");
            testCase.verifyEqual(count(edited, "axis("), 1);
            [~, vis3d] = yamada.model.AxesInspectorProperties.axisKeywordState(control.getSettings("AxisStyle"));
            testCase.verifyFalse(vis3d);
            document.undo();
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);

            % A later normal returns the vis3d Modes to auto; turning vis3d on appends it after normal.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "axis(app.Control, ""vis3d"", ""normal"");"]);
            [style, vis3d] = yamada.model.AxesInspectorProperties.axisKeywordState(control.getSettings("AxisStyle"));
            testCase.verifyEqual([style string(vis3d)], ["normal" "false"]);
            document.editAxesInspector(control.Id, "AxisVis3d", true, "set", registry);
            testCase.verifySubstring(document.CurrentText, "axis(app.Control, ""vis3d"", ""normal"", ""vis3d"");");

            % Without a call, vis3d writes a new call that turning it off removes again.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "app.Control.Box = 'on';"]);
            document.editAxesInspector(control.Id, "AxisVis3d", true, "set", registry);
            testCase.verifySubstring(document.CurrentText, "app.Control.Box = 'on';" + sprintf('\r\n') + ...
                "axis(app.Control, ""vis3d"");");
            document.editAxesInspector(control.Id, "AxisVis3d", false, "set", registry);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            testCase.verifyEmpty(control.getSettings("AxisStyle"));
        end

        % Guarantee: Command syntax such as axis equal vis3d or grid on is read as a read-only call on the current axes.
        % Failure mode: Command syntax effects are dropped, attributed to no axes or the wrong one, rewritten by an edit, or words that MATLAB passes differently, such as [0 1], are modeled.
        function commandSyntaxIsReadForCurrentAxes(testCase)
            % commandSyntaxIsReadForCurrentAxes Read command words as character-vector arguments of the implicit target.
            [document, registry, control] = testCase.fixture([ ...
                "app.Other = uiaxes(app.UIFigure);", "app.Control = uiaxes(app.UIFigure);", ...
                "axis equal vis3d", "grid on", "xlim [0 1]"]);
            other = document.getComponentByName("Other");
            call = control.getSettings("AxisStyle");
            testCase.verifyNumElements(call, 2);
            testCase.verifyFalse(any([call.IsEditable]));
            [style, vis3d] = yamada.model.AxesInspectorProperties.axisKeywordState(call);
            testCase.verifyEqual([style string(vis3d)], ["equal" "true"]);
            testCase.verifyEqual(string(control.getSettings("XGrid").LiteralValue), "on");
            testCase.verifyEmpty(control.getSettings("XLim"));
            testCase.verifyEmpty(other.getSettings("AxisStyle"));
            messages = string({document.Diagnostics.Message});
            testCase.verifyEqual(nnz(contains(messages, "inferred as Control")), 2);
            testCase.verifyEqual(nnz(contains(messages, """xlim"" has no explicit target")), 1);

            % The command is never rewritten as if it owned an explicit target.
            testCase.verifyError(@() document.editAxesInspector(control.Id, "AxisStyle", "square", "set", registry), ...
                "yamada:AxesInspectorEdits:Ownership");
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        % Guarantee: Editing a setting that only shapes an automatic value, such as XLimitMethod or a tick label format, also turns that value's Auto on with one call placed after the manual setting, and Undo restores both.
        % Failure mode: The edit keeps the manual Mode so the choice has no visible effect, writes a separate Mode statement or a call before the manual setting that the setting then overrides, or Undo leaves the Mode changed.
        % pendingModeIsAddedAfterExistingConstructorValue edits a Mode directly; this test detects a parameter edit that must request the Mode itself.
        function automaticParametersSelectAutomaticValues(testCase)
            % automaticParametersSelectAutomaticValues Write one companion call after manual limits and labels.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "xlim(app.Control, [0 4]);", ...
                "app.Control.XTickLabel = {'a','b'};"]);
            document.setPropertyBatch(control.Id, struct("Path", "XLimitMethod", "Value", "padded"), registry);
            document.editAxesInspector(control.Id, "XAxis.TickLabelFormat", "%.2f", "set", registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            ending = sprintf('\r\n');
            testCase.verifySubstring(source, "xlim(app.Control, [0 4]);" + ending + ...
                "app.Control.XTickLabel = {'a','b'};" + ending + "xlim(app.Control, ""padded"");" + ending + ...
                "xtickformat(app.Control, ""%.2f"");");
            testCase.verifyEqual(count(source, "XLimMode"), 0);
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(string(testCase.state(states, "XLimMode").EffectiveValue), "auto");
            testCase.verifyEqual(string(testCase.state(states, "XTickLabelMode").EffectiveValue), "auto");
            document.undo(); document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(string(testCase.state(states, "XLimMode").EffectiveValue), "manual");
        end

        % Guarantee: An explicit text size that a later axes FontSize or label call returns to automatic is not reported as effective, a new size is written after that setting, and a title weight parameter is read-only while the Title weight is explicit.
        % Failure mode: The resolver keeps the earlier explicit size, an in-place edit stays overridden by the later FontSize, or TitleFontWeight accepts edits that cannot change the displayed weight.
        % editsAxesTextAndSubtitleLink edits text that no later setting overrides; this test detects text values that later settings return to automatic.
        function explicitTextValuesFollowTheirAutomaticRules(testCase)
            % explicitTextValuesFollowTheirAutomaticRules Resolve text resets and ineffective weight edits.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "title(app.Control, 'T', 'FontWeight', 'bold');", ...
                "app.Control.Title.FontSize = 9;", "app.Control.XLabel.FontSize = 7;", ...
                "app.Control.FontSize = 20;", "app.Control.YLabel.FontSize = 7;", "ylabel(app.Control, 'Y');"]);
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(testCase.state(states, "Title.FontSize").ReasonCode, "automatic-text");
            testCase.verifyEqual(testCase.state(states, "XLabel.FontSize").ReasonCode, "automatic-text");
            testCase.verifyEqual(testCase.state(states, "YLabel.FontSize").ReasonCode, "automatic-text");
            weight = testCase.state(states, "TitleFontWeight");
            testCase.verifyFalse(weight.IsEditable);
            testCase.verifySubstring(weight.ReadOnlyReason, "Title.FontWeight");
            document.editAxesInspector(control.Id, "Title.FontSize", 14, "set", registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyLessThan(strfind(source, "app.Control.FontSize = 20;"), ...
                strfind(source, "app.Control.Title.FontSize = 14;"));
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(testCase.state(states, "Title.FontSize").EffectiveValue, 14);
        end

        % Guarantee: Undoing an option added to an existing call removes only that option.
        % Failure mode: The option shares the call's statement, so dropping the statement also deletes the main text.
        function undoingAnAddedOptionKeepsItsCall(testCase)
            % undoingAnAddedOptionKeepsItsCall Restore the original call and its main value.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "title(app.Control, 'A');"]);
            document.editAxesInspector(control.Id, "Title.Color", [1 0 0], "set", registry);
            testCase.verifySubstring(document.CurrentText, "title(app.Control, 'A', ""Color"", [1 0 0]);");
            document.undo();
            testCase.verifyEqual(document.CurrentText, document.OriginalText);
            testCase.verifyEqual(control.getSettings("Title.String").LiteralValue, 'A');
            document.editAxesInspector(control.Id, "Title.FontSize", 14, "set", registry);
            testCase.verifySubstring(document.CurrentText, "title(app.Control, 'A', ""FontSize"", 14);");
        end

        function assignmentModePreservesInputAndSavedPositions(testCase)
            % assignmentModePreservesInputAndSavedPositions Save a new mode call without inventing computed tick values.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "app.Control.XTick = [0 1];"]);
            original = document.OriginalText;
            document.setProperty(control.Id, "XTickMode", "auto", registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            checkpoint = yamada.model.SavedSourceCheckpoint(document, source, "AxisModeFixture.m", registry);
            document.confirmSavedSource(checkpoint, registry);
            record = checkpoint.Snapshot.Records(string({checkpoint.Snapshot.Records.Name}) == "Control");
            tick = record.Settings(string({record.Settings.Path}) == "XTick");
            mode = record.Settings(string({record.Settings.Path}) == "XTickMode");
            testCase.verifyEqual(tick.Value, [0 1]);
            testCase.verifyEqual(mode.Location.Method, "functionCall");
            testCase.verifyGreaterThan(mode.Location.Sequence, tick.Location.Sequence);
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEqual(document.OriginalText, original);
        end

        function originalModeBeforeValueCannotBeMovedToHideAnOverride(testCase)
            % originalModeBeforeValueCannotBeMovedToHideAnOverride Reject an unachievable replacement without adding shadow assignments.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, XTickMode='manual', XTick=[0 1]);");
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(testCase.state(states, "XTickMode").EffectiveValue, "manual");
            testCase.verifyError(@() document.setProperty(control.Id, "XTickMode", "auto", registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        function automaticModeCopiesRetainedInputsWithFreshOwnership(testCase)
            % automaticModeCopiesRetainedInputsWithFreshOwnership Preserve explicit inputs and auto intent without claiming computed equality.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100], XTick=[0 1], XTickMode='auto');");
            snapshot = document.copySubtree(control.Id, registry);
            copy = document.pasteSubtree(snapshot, document.RootComponentId, registry);
            testCase.verifyEqual(copy.getProperty("XTick").LiteralValue, [0 1]);
            testCase.verifyEqual(copy.getProperty("XTickMode").LiteralValue, 'auto');
            testCase.verifyFalse(any(ismember(string({copy.Settings.Id}), string({control.Settings.Id}))));
            states = document.getEffectivePropertyStates(registry, copy.Id);
            testCase.verifyFalse(testCase.state(states, "XTick").IsKnown);
            testCase.verifyEqual(string(testCase.state(states, "XTickMode").EffectiveValue), "auto");
            testCase.verifyEqual(control.getSettings("XTick").LiteralValue, [0 1]);
        end

        % Guarantee: width follower and hold semantics survive insertion, Copy, and Save.
        % Failure mode: inserting or copying a width setter changes which value a manual hold keeps.
        function storedColorCanBeEditedUnderAFinalAutomaticRenderingMode(testCase)
            % storedColorCanBeEditedUnderAFinalAutomaticRenderingMode Keep getter data known without claiming a rendered grid color.
            %   A constructor that restores auto last keeps the stored color
            %   only under a plain mode flag; other catalog policies leave it
            %   to the runtime, so the edit cannot be confirmed.
            % Guarantee and failure mode: shared with pendingModeIsAddedAfterExistingConstructorValue.
            for factory = ["uiaxes", "axes"]
                [document, registry, control] = testCase.fixture("app.Control = " + factory + ...
                    "(app.UIFigure, GridColor=[0.3 0.5 0.7], GridColorMode='auto');", factory);
                definition = registry.get(factory);
                policy = definition.Properties([definition.Properties.Path] == "GridColor").Application.EffectPolicy;
                if policy ~= "modeFlag"
                    testCase.verifyError(@() document.setProperty(control.Id, "GridColor", [0.6 0.2 0.1], registry), ...
                        "yamada:DocumentModel:UnsafePropertyEdit", factory);
                    continue
                end
                document.setProperty(control.Id, "GridColor", [0.6 0.2 0.1], registry);
                source = yamada.source.RoundTripGenerator(registry).generate(document);
                reopened = yamada.source.AppSourceParser.parseText(source, registry);
                other = reopened.getComponentByName("Control");
                states = reopened.getEffectivePropertyStates(registry, other.Id);
                testCase.verifyEqual(testCase.state(states, "GridColor").EffectiveValue, [0.6 0.2 0.1], factory);
                testCase.verifyEqual(string(testCase.state(states, "GridColorMode").EffectiveValue), "auto", factory);
                testCase.verifyNumElements(other.getSettings("GridColor"), 1, factory);
                testCase.verifyEqual(other.getSettings("GridColor").Method, "nameValue", factory);
            end
        end

        function laterAutomaticModePreventsPretendedLiteralEdits(testCase)
            % laterAutomaticModePreventsPretendedLiteralEdits Keep the original target when a later auto mode makes the requested value uncertain.
            % Guarantee and failure mode: shared with pendingModeIsAddedAfterExistingConstructorValue.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "app.Control.XTick = [0 1];", "app.Control.XTickMode = 'auto';"]);
            before = control.settingSnapshot();
            testCase.verifyError(@() document.setProperty(control.Id, "XTick", [0.2 0.8], registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(control.settingSnapshot(), before);
            testCase.verifyEqual(control.getProperty("XTick").LiteralValue, [0 1]);
            testCase.verifyEqual(document.HistoryIndex, 0);
        end
    end

    methods (Static, Access = private)
        function [document, registry, control] = fixture(body, factory)
            % fixture Build a complete owned initializer without executing its source.
            arguments (Input)
                body (1, :) string
                factory (1, 1) string = "uiaxes"
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                control (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            definition = registry.get(factory);
            source = strjoin(["classdef AxisModeFixture < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Control " + definition.DeclaredType, "end", "methods", ...
                "function app = AxisModeFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                body, "end", "end", "end"], sprintf('\r\n'));
            document = yamada.source.AppSourceParser.parseText(source, registry);
            control = document.getComponentByName("Control");
        end

        function value = state(states, path)
            % state Select one independent effective result by property path.
            arguments (Input)
                states (1, :) struct
                path (1, 1) string
            end
            arguments (Output)
                value (1, 1) yamada.model.PropertyState
            end
            value = states(arrayfun(@(item) item.Definition.Path == path, states)).Resolution;
        end
    end
end

function paths = formPaths(registry, id)
% formPaths Return the sorted effect paths that the loaded catalog records for one call form.
arguments (Input)
    registry (1,1) yamada.model.ComponentRegistry
    id (1,1) string
end
arguments (Output)
    paths (1,:) string
end

form = yamada.catalog.AxesSettingFunctionCatalog.formById(id, registry.CatalogRoot);
effects = form.effects;
if ~iscell(effects), effects = num2cell(effects); end
paths = sort(string(cellfun(@(effect) effect.path, effects, "UniformOutput", false)));
paths = reshape(paths, 1, []);
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
