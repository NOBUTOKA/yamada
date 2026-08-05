classdef ControlGalleryApp < matlab.apps.AppBase

    properties (Access = public)
        UIFigure matlab.ui.Figure
        MainGrid matlab.ui.container.GridLayout
        FormPanel matlab.ui.container.Panel
        FormGrid matlab.ui.container.GridLayout
        SubscribeCheckBox matlab.ui.control.CheckBox
        AccentColorPicker matlab.ui.control.ColorPicker
        DueDatePicker matlab.ui.control.DatePicker
        ThemeDropDown matlab.ui.control.DropDown
        PrioritySpinner matlab.ui.control.Spinner
        IntensitySlider matlab.ui.control.RangeSlider
        NotesTextArea matlab.ui.control.TextArea
        ReadinessGauge matlab.ui.control.LinearGauge
        GainKnob matlab.ui.control.DiscreteKnob
        StatusLamp matlab.ui.control.Lamp
        ModeSwitch matlab.ui.control.RockerSwitch
        SaveButton matlab.ui.control.Button
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure("Visible", "off");
            app.UIFigure.Position = [100 100 580 460];
            app.UIFigure.Name = "Control Gallery";

            app.MainGrid = uigridlayout(app.UIFigure);
            app.MainGrid.ColumnWidth = {'1x'};
            app.MainGrid.RowHeight = {'1x'};

            app.FormPanel = uipanel(app.MainGrid);
            app.FormPanel.Title = "Preferences";
            app.FormPanel.Layout.Row = 1;
            app.FormPanel.Layout.Column = 1;

            app.FormGrid = uigridlayout(app.FormPanel);
            app.FormGrid.ColumnWidth = {'1x', '1x'};
            app.FormGrid.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit'};

            app.SubscribeCheckBox = uicheckbox(app.FormGrid);
            app.SubscribeCheckBox.Text = "Subscribe to updates";
            app.SubscribeCheckBox.Value = true;
            app.SubscribeCheckBox.Layout.Row = 1;
            app.SubscribeCheckBox.Layout.Column = [1 2];

            app.AccentColorPicker = uicolorpicker(app.FormGrid);
            app.AccentColorPicker.Value = [0.2 0.5 0.8];
            app.AccentColorPicker.Layout.Row = 2;
            app.AccentColorPicker.Layout.Column = 1;

            app.DueDatePicker = uidatepicker(app.FormGrid);
            app.DueDatePicker.DisplayFormat = "yyyy-MM-dd";
            app.DueDatePicker.Layout.Row = 2;
            app.DueDatePicker.Layout.Column = 2;

            app.ThemeDropDown = uidropdown(app.FormGrid);
            app.ThemeDropDown.Items = ["Light", "Dark", "System"];
            app.ThemeDropDown.Value = "System";
            app.ThemeDropDown.Layout.Row = 3;
            app.ThemeDropDown.Layout.Column = 1;

            app.PrioritySpinner = uispinner(app.FormGrid);
            app.PrioritySpinner.Limits = [1 10];
            app.PrioritySpinner.Value = 5;
            app.PrioritySpinner.Step = 1;
            app.PrioritySpinner.Layout.Row = 3;
            app.PrioritySpinner.Layout.Column = 2;

            app.IntensitySlider = uislider(app.FormGrid, "range");
            app.IntensitySlider.Limits = [0 100];
            app.IntensitySlider.Value = [25 75];
            app.IntensitySlider.Layout.Row = 4;
            app.IntensitySlider.Layout.Column = [1 2];

            app.NotesTextArea = uitextarea(app.FormGrid);
            app.NotesTextArea.Value = ["A multi-line"; "notes field"];
            app.NotesTextArea.Layout.Row = 5;
            app.NotesTextArea.Layout.Column = [1 2];

            app.ReadinessGauge = uigauge(app.FormGrid, "linear");
            app.ReadinessGauge.Limits = [0 100];
            app.ReadinessGauge.Value = 60;
            app.ReadinessGauge.Layout.Row = 6;
            app.ReadinessGauge.Layout.Column = 1;

            app.GainKnob = uiknob(app.FormGrid, "discrete");
            app.GainKnob.Items = ["0", "2", "4", "6", "8", "10"];
            app.GainKnob.Value = "4";
            app.GainKnob.Layout.Row = 6;
            app.GainKnob.Layout.Column = 2;

            app.StatusLamp = uilamp(app.FormGrid);
            app.StatusLamp.Color = [0 0.7 0];
            app.StatusLamp.Layout.Row = 7;
            app.StatusLamp.Layout.Column = 1;

            app.ModeSwitch = uiswitch(app.FormGrid, "rocker");
            app.ModeSwitch.Items = ["Manual", "Auto"];
            app.ModeSwitch.Value = "Auto";
            app.ModeSwitch.Layout.Row = 7;
            app.ModeSwitch.Layout.Column = 2;

            app.SaveButton = uibutton(app.FormGrid, "push");
            app.SaveButton.Text = "Save settings";
            app.SaveButton.Layout.Row = 8;
            app.SaveButton.Layout.Column = [1 2];

            app.UIFigure.Visible = "on";
        end
    end

    methods (Access = public)
        function app = ControlGalleryApp
            createComponents(app);
            registerApp(app, app.UIFigure);

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end
end
