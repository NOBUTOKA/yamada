classdef (TestTags = {'fast', 'parser', 'catalog', 'model', 'generation'}) AxisModeSourceTest < matlab.unittest.TestCase
    % AxisModeSourceTest Preserve mode effects through source editing, copying, and saving.
    %   Owned UIAxes fixtures retain original argument order and explicit input
    %   values even when the audited effective value is runtime-computed.

    methods (Test)
        function readsAxesCallsInInitializationOrder(testCase)
            % readsAxesCallsInInitializationOrder Preserve function source and resolve literal effects in order.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", ...
                "app.Control.XLim = [0 3];", "xlim(app.Control, [1 4]);", ...
                "app.Other = uiaxes(app.UIFigure);", "xticks([1 2]);", ...
                "grid(app.Control, 'off');", "xlabel(app.Control, 'a,b');", ...
                "xticklabels(app.Control, {'A','B'});", ...
                "app.Control.XLimMode = 'auto';"]);
            other = document.getComponentByName("Other");
            limits = control.getSettings("XLim");
            testCase.verifyEqual([limits.Method], ["assignment","functionCall"]);
            testCase.verifyEqual(limits(2).LiteralValue, [1 4]);
            testCase.verifyFalse(limits(2).IsEditable);
            testCase.verifyEqual(control.getSettings("XLabel.String").LiteralValue, 'a,b');
            testCase.verifyEqual(other.getSettings("XTick").LiteralValue, [1 2]);
            testCase.verifyEmpty(control.getSettings("XTick"));
            testCase.verifyEqual(control.getSettings("XTickMode").LiteralValue, "manual");
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyFalse(testCase.state(states,"XLim").IsKnown);
            testCase.verifyEqual(string(testCase.state(states,"ZGrid").EffectiveValue), "off");
            codes = string({document.Diagnostics.Code});
            testCase.verifyEqual(nnz(codes == "implicit-axes-target"), 1);
            document.insertComponent(registry, "uibutton", document.RootComponentId);
            testCase.verifyEqual(other.getSettings("XTick").LiteralValue, [1 2]);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end

        function selectsAxesCallFormsFromRegistryRelease(testCase)
            % selectsAxesCallFormsFromRegistryRelease Retain newer calls on older catalog surfaces.
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
            [document, registry, component] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", "xtickformat(app.Control, '%.1f'); % keep"]);
            testCase.verifyEqual(string(component.getSettings("XAxis.TickLabelFormat").LiteralValue),"%.1f");
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
            % editsSecondaryLabelWithTheAvailableSourceForm Keep new assignments and existing calls distinct.
            [document, registry, component] = testCase.fixture("app.Control = uiaxes(app.UIFigure);");
            path = "XAxis.SecondaryLabel.String";
            document.editAxesInspector(component.Id,path,"units","set",registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source,'app.Control.XAxis.SecondaryLabel.String = "units";');
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

        function readsGeographicSettingsThroughOtherEdits(testCase)
            % readsGeographicSettingsThroughOtherEdits Keep multi-effect calls through local source publication.
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

        function pendingModeIsAddedAfterExistingConstructorValue(testCase)
            % pendingModeIsAddedAfterExistingConstructorValue Keep the constructor syntax while preserving a requested final auto mode.
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
                    testCase.verifyEqual(setting.Method, "nameValue");
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

        function assignmentModePreservesInputAndSavedPositions(testCase)
            % assignmentModePreservesInputAndSavedPositions Save a new assignment without inventing computed tick values.
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
            testCase.verifyEqual(mode.Location.Method, "assignment");
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

        function insertedWidthFollowsAnExistingManualHoldPoint(testCase)
            % insertedWidthFollowsAnExistingManualHoldPoint Keep a previously held default minor width during assignment insertion.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure);", ...
                "app.Control.MinorGridLineWidthMode = 'manual'; % hold default"]);
            document.setProperty(control.Id, "GridLineWidth", 4, registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            reopened = yamada.source.AppSourceParser.parseText(source, registry);
            other = reopened.getComponentByName("Control");
            states = reopened.getEffectivePropertyStates(registry, other.Id);
            testCase.verifyEqual(testCase.state(states, "GridLineWidth").EffectiveValue, 4);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 0.5);
            testCase.verifyGreaterThan(other.getSettings("GridLineWidth").Sequence, ...
                other.getSettings("MinorGridLineWidthMode").Sequence);
            testCase.verifySubstring(source, "'manual'; % hold default");
        end

        function constructorInsertionPreservesAnExistingManualHoldPoint(testCase)
            % constructorInsertionPreservesAnExistingManualHoldPoint Insert verified name-value widths after a protected manual mode.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, MinorGridLineWidthMode='manual', Units='pixels', Position=[10 20 200 100]);");
            document.setProperty(control.Id, "GridLineWidth", 4, registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            reopened = yamada.source.AppSourceParser.parseText(source, registry);
            other = reopened.getComponentByName("Control");
            setting = other.getSettings("GridLineWidth");
            testCase.verifyEqual(setting.Method, "nameValue");
            testCase.verifyGreaterThan(setting.ValueSpan.StartOffset, other.getSettings("MinorGridLineWidthMode").ValueSpan.StartOffset);
            states = reopened.getEffectivePropertyStates(registry, other.Id);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 0.5);
        end

        function implicitWidthsRemainSeparateThroughEditCopyAndSave(testCase)
            % implicitWidthsRemainSeparateThroughEditCopyAndSave Update the bound upstream token while retaining earlier receiver inputs.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100]);", ...
                "app.Control.LineWidth = 1;", "app.Control.GridLineWidth = 4;", ...
                "app.Control.MinorGridLineWidth = 3;", "app.Control.MinorGridLineWidthMode = 'auto';"]);
            original = control.settingSnapshot();
            document.setProperty(control.Id, "GridLineWidth", 6, registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source, "app.Control.MinorGridLineWidth = 3;");
            states = document.getEffectivePropertyStates(registry, control.Id);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 6);
            checkpoint = yamada.model.SavedSourceCheckpoint(document, source, "AxisModeFixture.m", registry);
            document.confirmSavedSource(checkpoint, registry);
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), document.RootComponentId, registry);
            testCase.verifyEqual(copy.getProperty("MinorGridLineWidth").LiteralValue, 6);
            testCase.verifyEqual([control.Settings.Id], arrayfun(@(record) record.Location.Id, original));
            testCase.verifyEqual(control.getSettings("GridLineWidth").LiteralValue, 6);
            testCase.verifyEqual(control.getSettings("MinorGridLineWidth").LiteralValue, 3);
            document.undo();
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            document.redo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
        end

        function copyPreservesDefaultAutoFollowersAndConstructorHolds(testCase)
            % copyPreservesDefaultAutoFollowersAndConstructorHolds Avoid setters that would silently change a copied automatic mode.
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100], LineWidth=2);");
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), document.RootComponentId, registry);
            testCase.verifyEmpty(copy.getProperty("GridLineWidth"));
            testCase.verifyEmpty(copy.getProperty("MinorGridLineWidth"));
            states = document.getEffectivePropertyStates(registry, copy.Id);
            testCase.verifyEqual(testCase.state(states, "GridLineWidth").EffectiveValue, 2);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 2);
            testCase.verifyEqual(string(testCase.state(states, "GridLineWidthMode").EffectiveValue), "auto");
            testCase.verifyEqual(string(testCase.state(states, "MinorGridLineWidthMode").EffectiveValue), "auto");
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiaxes(app.UIFigure, Units='pixels', Position=[10 20 200 100], GridLineWidth=4, MinorGridLineWidthMode='manual');");
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), document.RootComponentId, registry);
            testCase.verifyEqual(copy.getProperty("MinorGridLineWidth").LiteralValue, 0.5);
            states = document.getEffectivePropertyStates(registry, copy.Id);
            testCase.verifyEqual(testCase.state(states, "MinorGridLineWidth").EffectiveValue, 0.5);
            testCase.verifyEqual(string(testCase.state(states, "MinorGridLineWidthMode").EffectiveValue), "manual");
        end

        function storedColorCanBeEditedUnderAFinalAutomaticRenderingMode(testCase)
            % storedColorCanBeEditedUnderAFinalAutomaticRenderingMode Keep getter data known without claiming a rendered grid color.
            %   A constructor that restores auto last keeps the stored color
            %   only under a plain mode flag; other catalog policies leave it
            %   to the runtime, so the edit cannot be confirmed.
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
