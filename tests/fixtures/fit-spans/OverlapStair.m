classdef OverlapStair < handle
properties
UIFigure matlab.ui.Figure
Grid matlab.ui.container.GridLayout
Item1 matlab.ui.control.Label
Item2 matlab.ui.control.Button
Item3 matlab.ui.control.TextArea
end
methods
function app = OverlapStair
createComponents(app);
end
function createComponents(app)
app.UIFigure = uifigure("Visible","off");
app.UIFigure.Position = [100 100 640 390];
app.Grid = uigridlayout(app.UIFigure,[4 3]);
app.Grid.RowHeight = {'fit', 'fit', 'fit', 'fit'};
app.Grid.ColumnWidth = {'1x','1x','1x'};
app.Item1 = uilabel(app.Grid);
app.Item1.Layout.Row = [1 2];
app.Item1.Layout.Column = 1;
app.Item1.Text = "Label / rows 1-2";
app.Item2 = uibutton(app.Grid);
app.Item2.Layout.Row = [2 3];
app.Item2.Layout.Column = 2;
app.Item2.Text = "Button / rows 2-3";
app.Item3 = uitextarea(app.Grid);
app.Item3.Layout.Row = [3 4];
app.Item3.Layout.Column = 3;
app.Item3.Value = {"Text area / rows 3-4"; "Second line"; "Third line"};
end
end
end
