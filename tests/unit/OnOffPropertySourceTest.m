classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) OnOffPropertySourceTest < matlab.unittest.TestCase
    % OnOffPropertySourceTest Read and edit on/off property values in every source form MATLAB accepts.
    %   MATLAB accepts text in any letter case, a logical or numeric scalar, and an
    %   OnOffSwitchState member for an on/off property; yamada reads them alike
    %   and keeps a logical, numeric, or enumeration form on edit.

    methods (Test)
        % Guarantee: An on/off property written as text in any letter case, a logical, a number, or a matlab.lang.OnOffSwitchState member is read as its native state; an edit of its owned value keeps a logical, numeric, or enumeration form, and text or a new setting is written as "on" or "off".
        % Failure mode: Multiselect = 1 is read as off so a multiple selection is rejected, an enumeration member is kept as unrecognized source, an edit turns Enable = 0 into "on" text or writes a number as a logical, or a new setting is written as true.
        function onOffValuesKeepTheirSourceForm(testCase)
            % onOffValuesKeepTheirSourceForm Read native on/off forms and edit them in place.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.source.AppSourceParser.parseText(testCase.source(registry), registry);
            list = document.getComponentByName("List");
            button = document.getComponentByName("Button");

            % A numeric Multiselect state allows a multiple selection.
            document.setProperty(list.Id, "Value", {'A', 'B'}, registry);
            testCase.verifyEqual(list.getProperty("Value").LiteralValue, {'A', 'B'});

            % Owned values keep their logical, numeric, or enumeration form; text follows the text convention.
            document.setProperty(button.Id, "Enable", true, registry);
            document.setProperty(button.Id, "Visible", "on", registry);
            document.setProperty(list.Id, "Visible", "off", registry);
            document.setProperty(list.Id, "Enable", false, registry);
            document.setProperty(button.Id, "WordWrap", true, registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(source, "uibutton(app.UIFigure, Enable=1);");
            testCase.verifySubstring(source, "app.Button.Visible = matlab.lang.OnOffSwitchState.on;");
            testCase.verifySubstring(source, "app.List.Visible = false;");
            testCase.verifySubstring(source, "app.List.Enable = ""off"";");
            testCase.verifyMatches(source, "WordWrap['""]?[ =,]*""on""");
            reloaded = yamada.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(reloaded.getComponentByName("Button").getProperty("Enable").LiteralValue, 1);
            while document.HistoryIndex > 0, document.undo(); end
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
        end
    end

    methods (Static, Access = private)
        function text = source(registry)
            % source Build an owned initializer with on/off values in several forms.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                text (1, 1) string
            end
            text = strjoin(["classdef OnOffFixture < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Button " + registry.get("uibutton").DeclaredType, ...
                "List " + registry.get("uilistbox").DeclaredType, "end", "methods", ...
                "function app = OnOffFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Button = uibutton(app.UIFigure, Enable=0);", "app.Button.Visible = matlab.lang.OnOffSwitchState.off;", ...
                "app.List = uilistbox(app.UIFigure);", "app.List.Items = {'A', 'B'};", ...
                "app.List.Multiselect = 1;", "app.List.Enable = 'On';", "app.List.Visible = true;", ...
                "end", "end", "end"], sprintf('\r\n'));
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
