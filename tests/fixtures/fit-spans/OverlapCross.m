classdef OverlapCross < handle
properties
UIFigure matlab.ui.Figure
Grid matlab.ui.container.GridLayout
Item1 matlab.ui.control.Label
Item2 matlab.ui.control.TextArea
Item3 matlab.ui.control.Button
end
methods
function app = OverlapCross
createComponents(app);
end
function createComponents(app)
app.UIFigure = uifigure("Visible","off");
app.UIFigure.Position = [100 100 640 390];
app.Grid = uigridlayout(app.UIFigure,[5 3]);
app.Grid.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit'};
app.Grid.RowSpacing = 0;
app.Grid.ColumnWidth = {'1x','1x','1x'};
app.Item1 = uilabel(app.Grid);
app.Item1.Layout.Row = [1 3];
app.Item1.Layout.Column = 1;
app.Item1.Text = "Label / rows 1-3";
app.Item2 = uitextarea(app.Grid);
app.Item2.Layout.Row = [2 4];
app.Item2.Layout.Column = 2;
app.Item2.Value = {"Text area / rows 2-4"; "Second line"; "Third line"};
app.Item3 = uibutton(app.Grid);
app.Item3.Layout.Row = [3 5];
app.Item3.Layout.Column = 3;
app.Item3.Text = "Button / rows 3-5";
end
end
end
