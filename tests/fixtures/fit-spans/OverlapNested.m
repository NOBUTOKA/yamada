classdef OverlapNested < handle
properties
UIFigure matlab.ui.Figure
Grid matlab.ui.container.GridLayout
Item1 matlab.ui.control.TextArea
Item2 matlab.ui.control.Button
Item3 matlab.ui.control.Label
end
methods
function app = OverlapNested
createComponents(app);
end
function createComponents(app)
app.UIFigure = uifigure("Visible","off");
app.UIFigure.Position = [100 100 640 390];
app.Grid = uigridlayout(app.UIFigure,[5 3]);
app.Grid.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit'};
app.Grid.ColumnWidth = {'1x','1x','1x'};
app.Item1 = uitextarea(app.Grid);
app.Item1.Layout.Row = [1 5];
app.Item1.Layout.Column = 1;
app.Item1.Value = {"Text area / rows 1-5"; "Second line"; "Third line"};
app.Item2 = uibutton(app.Grid);
app.Item2.Layout.Row = [2 4];
app.Item2.Layout.Column = 2;
app.Item2.Text = "Button / rows 2-4";
app.Item3 = uilabel(app.Grid);
app.Item3.Layout.Row = [3 4];
app.Item3.Layout.Column = 3;
app.Item3.Text = "Label / rows 3-4";
end
end
end
