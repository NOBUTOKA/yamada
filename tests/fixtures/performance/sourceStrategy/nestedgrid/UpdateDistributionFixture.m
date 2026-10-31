classdef UpdateDistributionFixture < handle
properties
UIFigure matlab.ui.Figure
ComparisonButton matlab.ui.control.Button
Outer1 matlab.ui.container.GridLayout
Outer2 matlab.ui.container.GridLayout
Outer3 matlab.ui.container.GridLayout
Outer4 matlab.ui.container.GridLayout
Outer5 matlab.ui.container.GridLayout
Outer6 matlab.ui.container.GridLayout
Outer7 matlab.ui.container.GridLayout
Panel1 matlab.ui.container.Panel
Grid1 matlab.ui.container.GridLayout
Field1 matlab.ui.control.NumericEditField
Field2 matlab.ui.control.NumericEditField
Field3 matlab.ui.control.NumericEditField
Field4 matlab.ui.control.NumericEditField
Field5 matlab.ui.control.NumericEditField
Field6 matlab.ui.control.NumericEditField
Field7 matlab.ui.control.NumericEditField
Field8 matlab.ui.control.NumericEditField
Field9 matlab.ui.control.NumericEditField
Field10 matlab.ui.control.NumericEditField
Field11 matlab.ui.control.NumericEditField
Field12 matlab.ui.control.NumericEditField
Field13 matlab.ui.control.NumericEditField
Field14 matlab.ui.control.NumericEditField
Field15 matlab.ui.control.NumericEditField
Field16 matlab.ui.control.NumericEditField
Field17 matlab.ui.control.NumericEditField
Field18 matlab.ui.control.NumericEditField
Field19 matlab.ui.control.NumericEditField
Field20 matlab.ui.control.NumericEditField
Field21 matlab.ui.control.NumericEditField
Field22 matlab.ui.control.NumericEditField
Field23 matlab.ui.control.NumericEditField
Field24 matlab.ui.control.NumericEditField
Field25 matlab.ui.control.NumericEditField
Field26 matlab.ui.control.NumericEditField
Field27 matlab.ui.control.NumericEditField
Field28 matlab.ui.control.NumericEditField
Field29 matlab.ui.control.NumericEditField
Field30 matlab.ui.control.NumericEditField
Field31 matlab.ui.control.NumericEditField
Field32 matlab.ui.control.NumericEditField
Field33 matlab.ui.control.NumericEditField
Field34 matlab.ui.control.NumericEditField
Field35 matlab.ui.control.NumericEditField
Field36 matlab.ui.control.NumericEditField
Field37 matlab.ui.control.NumericEditField
Field38 matlab.ui.control.NumericEditField
Field39 matlab.ui.control.NumericEditField
Field40 matlab.ui.control.NumericEditField
Field41 matlab.ui.control.NumericEditField
Field42 matlab.ui.control.NumericEditField
Field43 matlab.ui.control.NumericEditField
Field44 matlab.ui.control.NumericEditField
Field45 matlab.ui.control.NumericEditField
Field46 matlab.ui.control.NumericEditField
Field47 matlab.ui.control.NumericEditField
Field48 matlab.ui.control.NumericEditField
Field49 matlab.ui.control.NumericEditField
Field50 matlab.ui.control.NumericEditField
Field51 matlab.ui.control.NumericEditField
Field52 matlab.ui.control.NumericEditField
Field53 matlab.ui.control.NumericEditField
Field54 matlab.ui.control.NumericEditField
Field55 matlab.ui.control.NumericEditField
Field56 matlab.ui.control.NumericEditField
Field57 matlab.ui.control.NumericEditField
Field58 matlab.ui.control.NumericEditField
Field59 matlab.ui.control.NumericEditField
Field60 matlab.ui.control.NumericEditField
Field61 matlab.ui.control.NumericEditField
Field62 matlab.ui.control.NumericEditField
Field63 matlab.ui.control.NumericEditField
Field64 matlab.ui.control.NumericEditField
Field65 matlab.ui.control.NumericEditField
Field66 matlab.ui.control.NumericEditField
Field67 matlab.ui.control.NumericEditField
Panel2 matlab.ui.container.Panel
Grid2 matlab.ui.container.GridLayout
Field68 matlab.ui.control.NumericEditField
Field69 matlab.ui.control.NumericEditField
Field70 matlab.ui.control.NumericEditField
Field71 matlab.ui.control.NumericEditField
Field72 matlab.ui.control.NumericEditField
Field73 matlab.ui.control.NumericEditField
Field74 matlab.ui.control.NumericEditField
Field75 matlab.ui.control.NumericEditField
Field76 matlab.ui.control.NumericEditField
Field77 matlab.ui.control.NumericEditField
Field78 matlab.ui.control.NumericEditField
Field79 matlab.ui.control.NumericEditField
Field80 matlab.ui.control.NumericEditField
Field81 matlab.ui.control.NumericEditField
Field82 matlab.ui.control.NumericEditField
Field83 matlab.ui.control.NumericEditField
Field84 matlab.ui.control.NumericEditField
Field85 matlab.ui.control.NumericEditField
Field86 matlab.ui.control.NumericEditField
Field87 matlab.ui.control.NumericEditField
Field88 matlab.ui.control.NumericEditField
Field89 matlab.ui.control.NumericEditField
Field90 matlab.ui.control.NumericEditField
Field91 matlab.ui.control.NumericEditField
Field92 matlab.ui.control.NumericEditField
Field93 matlab.ui.control.NumericEditField
Field94 matlab.ui.control.NumericEditField
Field95 matlab.ui.control.NumericEditField
Field96 matlab.ui.control.NumericEditField
Field97 matlab.ui.control.NumericEditField
Field98 matlab.ui.control.NumericEditField
Field99 matlab.ui.control.NumericEditField
Field100 matlab.ui.control.NumericEditField
Field101 matlab.ui.control.NumericEditField
Field102 matlab.ui.control.NumericEditField
Field103 matlab.ui.control.NumericEditField
Field104 matlab.ui.control.NumericEditField
Field105 matlab.ui.control.NumericEditField
Field106 matlab.ui.control.NumericEditField
Field107 matlab.ui.control.NumericEditField
Field108 matlab.ui.control.NumericEditField
Field109 matlab.ui.control.NumericEditField
Field110 matlab.ui.control.NumericEditField
Field111 matlab.ui.control.NumericEditField
Field112 matlab.ui.control.NumericEditField
Field113 matlab.ui.control.NumericEditField
Field114 matlab.ui.control.NumericEditField
Field115 matlab.ui.control.NumericEditField
Field116 matlab.ui.control.NumericEditField
Field117 matlab.ui.control.NumericEditField
Field118 matlab.ui.control.NumericEditField
Field119 matlab.ui.control.NumericEditField
Field120 matlab.ui.control.NumericEditField
Field121 matlab.ui.control.NumericEditField
Field122 matlab.ui.control.NumericEditField
Field123 matlab.ui.control.NumericEditField
Field124 matlab.ui.control.NumericEditField
Field125 matlab.ui.control.NumericEditField
Field126 matlab.ui.control.NumericEditField
Field127 matlab.ui.control.NumericEditField
Field128 matlab.ui.control.NumericEditField
Field129 matlab.ui.control.NumericEditField
Field130 matlab.ui.control.NumericEditField
Field131 matlab.ui.control.NumericEditField
Field132 matlab.ui.control.NumericEditField
Field133 matlab.ui.control.NumericEditField
Field134 matlab.ui.control.NumericEditField
Panel3 matlab.ui.container.Panel
Grid3 matlab.ui.container.GridLayout
Field135 matlab.ui.control.NumericEditField
Field136 matlab.ui.control.NumericEditField
Field137 matlab.ui.control.NumericEditField
Field138 matlab.ui.control.NumericEditField
Field139 matlab.ui.control.NumericEditField
Field140 matlab.ui.control.NumericEditField
Field141 matlab.ui.control.NumericEditField
Field142 matlab.ui.control.NumericEditField
Field143 matlab.ui.control.NumericEditField
Field144 matlab.ui.control.NumericEditField
Field145 matlab.ui.control.NumericEditField
Field146 matlab.ui.control.NumericEditField
Field147 matlab.ui.control.NumericEditField
Field148 matlab.ui.control.NumericEditField
Field149 matlab.ui.control.NumericEditField
Field150 matlab.ui.control.NumericEditField
Field151 matlab.ui.control.NumericEditField
Field152 matlab.ui.control.NumericEditField
Field153 matlab.ui.control.NumericEditField
Field154 matlab.ui.control.NumericEditField
Field155 matlab.ui.control.NumericEditField
Field156 matlab.ui.control.NumericEditField
Field157 matlab.ui.control.NumericEditField
Field158 matlab.ui.control.NumericEditField
Field159 matlab.ui.control.NumericEditField
Field160 matlab.ui.control.NumericEditField
Field161 matlab.ui.control.NumericEditField
Field162 matlab.ui.control.NumericEditField
Field163 matlab.ui.control.NumericEditField
Field164 matlab.ui.control.NumericEditField
Field165 matlab.ui.control.NumericEditField
Field166 matlab.ui.control.NumericEditField
Field167 matlab.ui.control.NumericEditField
Field168 matlab.ui.control.NumericEditField
Field169 matlab.ui.control.NumericEditField
Field170 matlab.ui.control.NumericEditField
Field171 matlab.ui.control.NumericEditField
Field172 matlab.ui.control.NumericEditField
Field173 matlab.ui.control.NumericEditField
Field174 matlab.ui.control.NumericEditField
Field175 matlab.ui.control.NumericEditField
Field176 matlab.ui.control.NumericEditField
Field177 matlab.ui.control.NumericEditField
Field178 matlab.ui.control.NumericEditField
Field179 matlab.ui.control.NumericEditField
Field180 matlab.ui.control.NumericEditField
Field181 matlab.ui.control.NumericEditField
Field182 matlab.ui.control.NumericEditField
Field183 matlab.ui.control.NumericEditField
Field184 matlab.ui.control.NumericEditField
Field185 matlab.ui.control.NumericEditField
Field186 matlab.ui.control.NumericEditField
Field187 matlab.ui.control.NumericEditField
Field188 matlab.ui.control.NumericEditField
Field189 matlab.ui.control.NumericEditField
Field190 matlab.ui.control.NumericEditField
Field191 matlab.ui.control.NumericEditField
Field192 matlab.ui.control.NumericEditField
Field193 matlab.ui.control.NumericEditField
Field194 matlab.ui.control.NumericEditField
Field195 matlab.ui.control.NumericEditField
Field196 matlab.ui.control.NumericEditField
Field197 matlab.ui.control.NumericEditField
Field198 matlab.ui.control.NumericEditField
Field199 matlab.ui.control.NumericEditField
Field200 matlab.ui.control.NumericEditField
end
methods
function app = UpdateDistributionFixture
createComponents(app);
end
function createComponents(app)
app.UIFigure = uifigure('Visible','off');
app.UIFigure.Position = [100 100 1000 1400];
app.Outer1 = uigridlayout(app.UIFigure,[1 1]);
app.Outer1.RowHeight = {'1x'};
app.Outer1.ColumnWidth = {'1x'};
app.Outer2 = uigridlayout(app.Outer1,[1 1]);
app.Outer2.RowHeight = {'1x'};
app.Outer2.ColumnWidth = {'1x'};
app.Outer3 = uigridlayout(app.Outer2,[1 1]);
app.Outer3.RowHeight = {'1x'};
app.Outer3.ColumnWidth = {'1x'};
app.Outer4 = uigridlayout(app.Outer3,[1 1]);
app.Outer4.RowHeight = {'1x'};
app.Outer4.ColumnWidth = {'1x'};
app.Outer5 = uigridlayout(app.Outer4,[1 1]);
app.Outer5.RowHeight = {'1x'};
app.Outer5.ColumnWidth = {'1x'};
app.Outer6 = uigridlayout(app.Outer5,[1 1]);
app.Outer6.RowHeight = {'1x'};
app.Outer6.ColumnWidth = {'1x'};
app.Outer7 = uigridlayout(app.Outer6,[1 1]);
app.Outer7.RowHeight = {'1x'};
app.Outer7.ColumnWidth = {'1x'};
app.Outer7.ColumnWidth = {'1x','1x','1x'};
app.Panel1 = uipanel(app.Outer7);
app.Panel1.Layout.Row = 1;
app.Panel1.Layout.Column = 1;
app.Grid1 = uigridlayout(app.Panel1,[35 2]);
app.Grid1.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','1x'};
app.Grid1.ColumnWidth = {'fit','1x'};
app.Field1 = uieditfield(app.Grid1,'numeric');
app.Field1.Layout.Row = 1;
app.Field1.Layout.Column = 1;
app.Field2 = uieditfield(app.Grid1,'numeric');
app.Field2.Layout.Row = 1;
app.Field2.Layout.Column = 2;
app.Field3 = uieditfield(app.Grid1,'numeric');
app.Field3.Layout.Row = 2;
app.Field3.Layout.Column = 1;
app.Field4 = uieditfield(app.Grid1,'numeric');
app.Field4.Layout.Row = 2;
app.Field4.Layout.Column = 2;
app.Field5 = uieditfield(app.Grid1,'numeric');
app.Field5.Layout.Row = 3;
app.Field5.Layout.Column = 1;
app.Field6 = uieditfield(app.Grid1,'numeric');
app.Field6.Layout.Row = 3;
app.Field6.Layout.Column = 2;
app.Field7 = uieditfield(app.Grid1,'numeric');
app.Field7.Layout.Row = 4;
app.Field7.Layout.Column = 1;
app.Field8 = uieditfield(app.Grid1,'numeric');
app.Field8.Layout.Row = 4;
app.Field8.Layout.Column = 2;
app.Field9 = uieditfield(app.Grid1,'numeric');
app.Field9.Layout.Row = 5;
app.Field9.Layout.Column = 1;
app.Field10 = uieditfield(app.Grid1,'numeric');
app.Field10.Layout.Row = 5;
app.Field10.Layout.Column = 2;
app.Field11 = uieditfield(app.Grid1,'numeric');
app.Field11.Layout.Row = 6;
app.Field11.Layout.Column = 1;
app.Field12 = uieditfield(app.Grid1,'numeric');
app.Field12.Layout.Row = 6;
app.Field12.Layout.Column = 2;
app.Field13 = uieditfield(app.Grid1,'numeric');
app.Field13.Layout.Row = 7;
app.Field13.Layout.Column = 1;
app.Field14 = uieditfield(app.Grid1,'numeric');
app.Field14.Layout.Row = 7;
app.Field14.Layout.Column = 2;
app.Field15 = uieditfield(app.Grid1,'numeric');
app.Field15.Layout.Row = 8;
app.Field15.Layout.Column = 1;
app.Field16 = uieditfield(app.Grid1,'numeric');
app.Field16.Layout.Row = 8;
app.Field16.Layout.Column = 2;
app.Field17 = uieditfield(app.Grid1,'numeric');
app.Field17.Layout.Row = 9;
app.Field17.Layout.Column = 1;
app.Field18 = uieditfield(app.Grid1,'numeric');
app.Field18.Layout.Row = 9;
app.Field18.Layout.Column = 2;
app.Field19 = uieditfield(app.Grid1,'numeric');
app.Field19.Layout.Row = 10;
app.Field19.Layout.Column = 1;
app.Field20 = uieditfield(app.Grid1,'numeric');
app.Field20.Layout.Row = 10;
app.Field20.Layout.Column = 2;
app.Field21 = uieditfield(app.Grid1,'numeric');
app.Field21.Layout.Row = 11;
app.Field21.Layout.Column = 1;
app.Field22 = uieditfield(app.Grid1,'numeric');
app.Field22.Layout.Row = 11;
app.Field22.Layout.Column = 2;
app.Field23 = uieditfield(app.Grid1,'numeric');
app.Field23.Layout.Row = 12;
app.Field23.Layout.Column = 1;
app.Field24 = uieditfield(app.Grid1,'numeric');
app.Field24.Layout.Row = 12;
app.Field24.Layout.Column = 2;
app.Field25 = uieditfield(app.Grid1,'numeric');
app.Field25.Layout.Row = 13;
app.Field25.Layout.Column = 1;
app.Field26 = uieditfield(app.Grid1,'numeric');
app.Field26.Layout.Row = 13;
app.Field26.Layout.Column = 2;
app.Field27 = uieditfield(app.Grid1,'numeric');
app.Field27.Layout.Row = 14;
app.Field27.Layout.Column = 1;
app.Field28 = uieditfield(app.Grid1,'numeric');
app.Field28.Layout.Row = 14;
app.Field28.Layout.Column = 2;
app.Field29 = uieditfield(app.Grid1,'numeric');
app.Field29.Layout.Row = 15;
app.Field29.Layout.Column = 1;
app.Field30 = uieditfield(app.Grid1,'numeric');
app.Field30.Layout.Row = 15;
app.Field30.Layout.Column = 2;
app.Field31 = uieditfield(app.Grid1,'numeric');
app.Field31.Layout.Row = 16;
app.Field31.Layout.Column = 1;
app.Field32 = uieditfield(app.Grid1,'numeric');
app.Field32.Layout.Row = 16;
app.Field32.Layout.Column = 2;
app.Field33 = uieditfield(app.Grid1,'numeric');
app.Field33.Layout.Row = 17;
app.Field33.Layout.Column = 1;
app.Field34 = uieditfield(app.Grid1,'numeric');
app.Field34.Layout.Row = 17;
app.Field34.Layout.Column = 2;
app.Field35 = uieditfield(app.Grid1,'numeric');
app.Field35.Layout.Row = 18;
app.Field35.Layout.Column = 1;
app.Field36 = uieditfield(app.Grid1,'numeric');
app.Field36.Layout.Row = 18;
app.Field36.Layout.Column = 2;
app.Field37 = uieditfield(app.Grid1,'numeric');
app.Field37.Layout.Row = 19;
app.Field37.Layout.Column = 1;
app.Field38 = uieditfield(app.Grid1,'numeric');
app.Field38.Layout.Row = 19;
app.Field38.Layout.Column = 2;
app.Field39 = uieditfield(app.Grid1,'numeric');
app.Field39.Layout.Row = 20;
app.Field39.Layout.Column = 1;
app.Field40 = uieditfield(app.Grid1,'numeric');
app.Field40.Layout.Row = 20;
app.Field40.Layout.Column = 2;
app.Field41 = uieditfield(app.Grid1,'numeric');
app.Field41.Layout.Row = 21;
app.Field41.Layout.Column = 1;
app.Field42 = uieditfield(app.Grid1,'numeric');
app.Field42.Layout.Row = 21;
app.Field42.Layout.Column = 2;
app.Field43 = uieditfield(app.Grid1,'numeric');
app.Field43.Layout.Row = 22;
app.Field43.Layout.Column = 1;
app.Field44 = uieditfield(app.Grid1,'numeric');
app.Field44.Layout.Row = 22;
app.Field44.Layout.Column = 2;
app.Field45 = uieditfield(app.Grid1,'numeric');
app.Field45.Layout.Row = 23;
app.Field45.Layout.Column = 1;
app.Field46 = uieditfield(app.Grid1,'numeric');
app.Field46.Layout.Row = 23;
app.Field46.Layout.Column = 2;
app.Field47 = uieditfield(app.Grid1,'numeric');
app.Field47.Layout.Row = 24;
app.Field47.Layout.Column = 1;
app.Field48 = uieditfield(app.Grid1,'numeric');
app.Field48.Layout.Row = 24;
app.Field48.Layout.Column = 2;
app.Field49 = uieditfield(app.Grid1,'numeric');
app.Field49.Layout.Row = 25;
app.Field49.Layout.Column = 1;
app.Field50 = uieditfield(app.Grid1,'numeric');
app.Field50.Layout.Row = 25;
app.Field50.Layout.Column = 2;
app.Field51 = uieditfield(app.Grid1,'numeric');
app.Field51.Layout.Row = 26;
app.Field51.Layout.Column = 1;
app.Field52 = uieditfield(app.Grid1,'numeric');
app.Field52.Layout.Row = 26;
app.Field52.Layout.Column = 2;
app.Field53 = uieditfield(app.Grid1,'numeric');
app.Field53.Layout.Row = 27;
app.Field53.Layout.Column = 1;
app.Field54 = uieditfield(app.Grid1,'numeric');
app.Field54.Layout.Row = 27;
app.Field54.Layout.Column = 2;
app.Field55 = uieditfield(app.Grid1,'numeric');
app.Field55.Layout.Row = 28;
app.Field55.Layout.Column = 1;
app.Field56 = uieditfield(app.Grid1,'numeric');
app.Field56.Layout.Row = 28;
app.Field56.Layout.Column = 2;
app.Field57 = uieditfield(app.Grid1,'numeric');
app.Field57.Layout.Row = 29;
app.Field57.Layout.Column = 1;
app.Field58 = uieditfield(app.Grid1,'numeric');
app.Field58.Layout.Row = 29;
app.Field58.Layout.Column = 2;
app.Field59 = uieditfield(app.Grid1,'numeric');
app.Field59.Layout.Row = 30;
app.Field59.Layout.Column = 1;
app.Field60 = uieditfield(app.Grid1,'numeric');
app.Field60.Layout.Row = 30;
app.Field60.Layout.Column = 2;
app.Field61 = uieditfield(app.Grid1,'numeric');
app.Field61.Layout.Row = 31;
app.Field61.Layout.Column = 1;
app.Field62 = uieditfield(app.Grid1,'numeric');
app.Field62.Layout.Row = 31;
app.Field62.Layout.Column = 2;
app.Field63 = uieditfield(app.Grid1,'numeric');
app.Field63.Layout.Row = 32;
app.Field63.Layout.Column = 1;
app.Field64 = uieditfield(app.Grid1,'numeric');
app.Field64.Layout.Row = 32;
app.Field64.Layout.Column = 2;
app.Field65 = uieditfield(app.Grid1,'numeric');
app.Field65.Layout.Row = 33;
app.Field65.Layout.Column = 1;
app.Field66 = uieditfield(app.Grid1,'numeric');
app.Field66.Layout.Row = 33;
app.Field66.Layout.Column = 2;
app.Field67 = uieditfield(app.Grid1,'numeric');
app.Field67.Layout.Row = 34;
app.Field67.Layout.Column = 1;
app.ComparisonButton = uibutton(app.Grid1);
app.ComparisonButton.Text = 'Comparison';
app.ComparisonButton.Layout.Row = 35;
app.ComparisonButton.Layout.Column = [1 2];
app.Panel2 = uipanel(app.Outer7);
app.Panel2.Layout.Row = 1;
app.Panel2.Layout.Column = 2;
app.Grid2 = uigridlayout(app.Panel2,[35 2]);
app.Grid2.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','1x'};
app.Grid2.ColumnWidth = {'fit','1x'};
app.Field68 = uieditfield(app.Grid2,'numeric');
app.Field68.Layout.Row = 1;
app.Field68.Layout.Column = 1;
app.Field69 = uieditfield(app.Grid2,'numeric');
app.Field69.Layout.Row = 1;
app.Field69.Layout.Column = 2;
app.Field70 = uieditfield(app.Grid2,'numeric');
app.Field70.Layout.Row = 2;
app.Field70.Layout.Column = 1;
app.Field71 = uieditfield(app.Grid2,'numeric');
app.Field71.Layout.Row = 2;
app.Field71.Layout.Column = 2;
app.Field72 = uieditfield(app.Grid2,'numeric');
app.Field72.Layout.Row = 3;
app.Field72.Layout.Column = 1;
app.Field73 = uieditfield(app.Grid2,'numeric');
app.Field73.Layout.Row = 3;
app.Field73.Layout.Column = 2;
app.Field74 = uieditfield(app.Grid2,'numeric');
app.Field74.Layout.Row = 4;
app.Field74.Layout.Column = 1;
app.Field75 = uieditfield(app.Grid2,'numeric');
app.Field75.Layout.Row = 4;
app.Field75.Layout.Column = 2;
app.Field76 = uieditfield(app.Grid2,'numeric');
app.Field76.Layout.Row = 5;
app.Field76.Layout.Column = 1;
app.Field77 = uieditfield(app.Grid2,'numeric');
app.Field77.Layout.Row = 5;
app.Field77.Layout.Column = 2;
app.Field78 = uieditfield(app.Grid2,'numeric');
app.Field78.Layout.Row = 6;
app.Field78.Layout.Column = 1;
app.Field79 = uieditfield(app.Grid2,'numeric');
app.Field79.Layout.Row = 6;
app.Field79.Layout.Column = 2;
app.Field80 = uieditfield(app.Grid2,'numeric');
app.Field80.Layout.Row = 7;
app.Field80.Layout.Column = 1;
app.Field81 = uieditfield(app.Grid2,'numeric');
app.Field81.Layout.Row = 7;
app.Field81.Layout.Column = 2;
app.Field82 = uieditfield(app.Grid2,'numeric');
app.Field82.Layout.Row = 8;
app.Field82.Layout.Column = 1;
app.Field83 = uieditfield(app.Grid2,'numeric');
app.Field83.Layout.Row = 8;
app.Field83.Layout.Column = 2;
app.Field84 = uieditfield(app.Grid2,'numeric');
app.Field84.Layout.Row = 9;
app.Field84.Layout.Column = 1;
app.Field85 = uieditfield(app.Grid2,'numeric');
app.Field85.Layout.Row = 9;
app.Field85.Layout.Column = 2;
app.Field86 = uieditfield(app.Grid2,'numeric');
app.Field86.Layout.Row = 10;
app.Field86.Layout.Column = 1;
app.Field87 = uieditfield(app.Grid2,'numeric');
app.Field87.Layout.Row = 10;
app.Field87.Layout.Column = 2;
app.Field88 = uieditfield(app.Grid2,'numeric');
app.Field88.Layout.Row = 11;
app.Field88.Layout.Column = 1;
app.Field89 = uieditfield(app.Grid2,'numeric');
app.Field89.Layout.Row = 11;
app.Field89.Layout.Column = 2;
app.Field90 = uieditfield(app.Grid2,'numeric');
app.Field90.Layout.Row = 12;
app.Field90.Layout.Column = 1;
app.Field91 = uieditfield(app.Grid2,'numeric');
app.Field91.Layout.Row = 12;
app.Field91.Layout.Column = 2;
app.Field92 = uieditfield(app.Grid2,'numeric');
app.Field92.Layout.Row = 13;
app.Field92.Layout.Column = 1;
app.Field93 = uieditfield(app.Grid2,'numeric');
app.Field93.Layout.Row = 13;
app.Field93.Layout.Column = 2;
app.Field94 = uieditfield(app.Grid2,'numeric');
app.Field94.Layout.Row = 14;
app.Field94.Layout.Column = 1;
app.Field95 = uieditfield(app.Grid2,'numeric');
app.Field95.Layout.Row = 14;
app.Field95.Layout.Column = 2;
app.Field96 = uieditfield(app.Grid2,'numeric');
app.Field96.Layout.Row = 15;
app.Field96.Layout.Column = 1;
app.Field97 = uieditfield(app.Grid2,'numeric');
app.Field97.Layout.Row = 15;
app.Field97.Layout.Column = 2;
app.Field98 = uieditfield(app.Grid2,'numeric');
app.Field98.Layout.Row = 16;
app.Field98.Layout.Column = 1;
app.Field99 = uieditfield(app.Grid2,'numeric');
app.Field99.Layout.Row = 16;
app.Field99.Layout.Column = 2;
app.Field100 = uieditfield(app.Grid2,'numeric');
app.Field100.Layout.Row = 17;
app.Field100.Layout.Column = 1;
app.Field101 = uieditfield(app.Grid2,'numeric');
app.Field101.Layout.Row = 17;
app.Field101.Layout.Column = 2;
app.Field102 = uieditfield(app.Grid2,'numeric');
app.Field102.Layout.Row = 18;
app.Field102.Layout.Column = 1;
app.Field103 = uieditfield(app.Grid2,'numeric');
app.Field103.Layout.Row = 18;
app.Field103.Layout.Column = 2;
app.Field104 = uieditfield(app.Grid2,'numeric');
app.Field104.Layout.Row = 19;
app.Field104.Layout.Column = 1;
app.Field105 = uieditfield(app.Grid2,'numeric');
app.Field105.Layout.Row = 19;
app.Field105.Layout.Column = 2;
app.Field106 = uieditfield(app.Grid2,'numeric');
app.Field106.Layout.Row = 20;
app.Field106.Layout.Column = 1;
app.Field107 = uieditfield(app.Grid2,'numeric');
app.Field107.Layout.Row = 20;
app.Field107.Layout.Column = 2;
app.Field108 = uieditfield(app.Grid2,'numeric');
app.Field108.Layout.Row = 21;
app.Field108.Layout.Column = 1;
app.Field109 = uieditfield(app.Grid2,'numeric');
app.Field109.Layout.Row = 21;
app.Field109.Layout.Column = 2;
app.Field110 = uieditfield(app.Grid2,'numeric');
app.Field110.Layout.Row = 22;
app.Field110.Layout.Column = 1;
app.Field111 = uieditfield(app.Grid2,'numeric');
app.Field111.Layout.Row = 22;
app.Field111.Layout.Column = 2;
app.Field112 = uieditfield(app.Grid2,'numeric');
app.Field112.Layout.Row = 23;
app.Field112.Layout.Column = 1;
app.Field113 = uieditfield(app.Grid2,'numeric');
app.Field113.Layout.Row = 23;
app.Field113.Layout.Column = 2;
app.Field114 = uieditfield(app.Grid2,'numeric');
app.Field114.Layout.Row = 24;
app.Field114.Layout.Column = 1;
app.Field115 = uieditfield(app.Grid2,'numeric');
app.Field115.Layout.Row = 24;
app.Field115.Layout.Column = 2;
app.Field116 = uieditfield(app.Grid2,'numeric');
app.Field116.Layout.Row = 25;
app.Field116.Layout.Column = 1;
app.Field117 = uieditfield(app.Grid2,'numeric');
app.Field117.Layout.Row = 25;
app.Field117.Layout.Column = 2;
app.Field118 = uieditfield(app.Grid2,'numeric');
app.Field118.Layout.Row = 26;
app.Field118.Layout.Column = 1;
app.Field119 = uieditfield(app.Grid2,'numeric');
app.Field119.Layout.Row = 26;
app.Field119.Layout.Column = 2;
app.Field120 = uieditfield(app.Grid2,'numeric');
app.Field120.Layout.Row = 27;
app.Field120.Layout.Column = 1;
app.Field121 = uieditfield(app.Grid2,'numeric');
app.Field121.Layout.Row = 27;
app.Field121.Layout.Column = 2;
app.Field122 = uieditfield(app.Grid2,'numeric');
app.Field122.Layout.Row = 28;
app.Field122.Layout.Column = 1;
app.Field123 = uieditfield(app.Grid2,'numeric');
app.Field123.Layout.Row = 28;
app.Field123.Layout.Column = 2;
app.Field124 = uieditfield(app.Grid2,'numeric');
app.Field124.Layout.Row = 29;
app.Field124.Layout.Column = 1;
app.Field125 = uieditfield(app.Grid2,'numeric');
app.Field125.Layout.Row = 29;
app.Field125.Layout.Column = 2;
app.Field126 = uieditfield(app.Grid2,'numeric');
app.Field126.Layout.Row = 30;
app.Field126.Layout.Column = 1;
app.Field127 = uieditfield(app.Grid2,'numeric');
app.Field127.Layout.Row = 30;
app.Field127.Layout.Column = 2;
app.Field128 = uieditfield(app.Grid2,'numeric');
app.Field128.Layout.Row = 31;
app.Field128.Layout.Column = 1;
app.Field129 = uieditfield(app.Grid2,'numeric');
app.Field129.Layout.Row = 31;
app.Field129.Layout.Column = 2;
app.Field130 = uieditfield(app.Grid2,'numeric');
app.Field130.Layout.Row = 32;
app.Field130.Layout.Column = 1;
app.Field131 = uieditfield(app.Grid2,'numeric');
app.Field131.Layout.Row = 32;
app.Field131.Layout.Column = 2;
app.Field132 = uieditfield(app.Grid2,'numeric');
app.Field132.Layout.Row = 33;
app.Field132.Layout.Column = 1;
app.Field133 = uieditfield(app.Grid2,'numeric');
app.Field133.Layout.Row = 33;
app.Field133.Layout.Column = 2;
app.Field134 = uieditfield(app.Grid2,'numeric');
app.Field134.Layout.Row = 34;
app.Field134.Layout.Column = 1;
app.Panel3 = uipanel(app.Outer7);
app.Panel3.Layout.Row = 1;
app.Panel3.Layout.Column = 3;
app.Grid3 = uigridlayout(app.Panel3,[35 2]);
app.Grid3.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','1x'};
app.Grid3.ColumnWidth = {'fit','1x'};
app.Field135 = uieditfield(app.Grid3,'numeric');
app.Field135.Layout.Row = 1;
app.Field135.Layout.Column = 1;
app.Field136 = uieditfield(app.Grid3,'numeric');
app.Field136.Layout.Row = 1;
app.Field136.Layout.Column = 2;
app.Field137 = uieditfield(app.Grid3,'numeric');
app.Field137.Layout.Row = 2;
app.Field137.Layout.Column = 1;
app.Field138 = uieditfield(app.Grid3,'numeric');
app.Field138.Layout.Row = 2;
app.Field138.Layout.Column = 2;
app.Field139 = uieditfield(app.Grid3,'numeric');
app.Field139.Layout.Row = 3;
app.Field139.Layout.Column = 1;
app.Field140 = uieditfield(app.Grid3,'numeric');
app.Field140.Layout.Row = 3;
app.Field140.Layout.Column = 2;
app.Field141 = uieditfield(app.Grid3,'numeric');
app.Field141.Layout.Row = 4;
app.Field141.Layout.Column = 1;
app.Field142 = uieditfield(app.Grid3,'numeric');
app.Field142.Layout.Row = 4;
app.Field142.Layout.Column = 2;
app.Field143 = uieditfield(app.Grid3,'numeric');
app.Field143.Layout.Row = 5;
app.Field143.Layout.Column = 1;
app.Field144 = uieditfield(app.Grid3,'numeric');
app.Field144.Layout.Row = 5;
app.Field144.Layout.Column = 2;
app.Field145 = uieditfield(app.Grid3,'numeric');
app.Field145.Layout.Row = 6;
app.Field145.Layout.Column = 1;
app.Field146 = uieditfield(app.Grid3,'numeric');
app.Field146.Layout.Row = 6;
app.Field146.Layout.Column = 2;
app.Field147 = uieditfield(app.Grid3,'numeric');
app.Field147.Layout.Row = 7;
app.Field147.Layout.Column = 1;
app.Field148 = uieditfield(app.Grid3,'numeric');
app.Field148.Layout.Row = 7;
app.Field148.Layout.Column = 2;
app.Field149 = uieditfield(app.Grid3,'numeric');
app.Field149.Layout.Row = 8;
app.Field149.Layout.Column = 1;
app.Field150 = uieditfield(app.Grid3,'numeric');
app.Field150.Layout.Row = 8;
app.Field150.Layout.Column = 2;
app.Field151 = uieditfield(app.Grid3,'numeric');
app.Field151.Layout.Row = 9;
app.Field151.Layout.Column = 1;
app.Field152 = uieditfield(app.Grid3,'numeric');
app.Field152.Layout.Row = 9;
app.Field152.Layout.Column = 2;
app.Field153 = uieditfield(app.Grid3,'numeric');
app.Field153.Layout.Row = 10;
app.Field153.Layout.Column = 1;
app.Field154 = uieditfield(app.Grid3,'numeric');
app.Field154.Layout.Row = 10;
app.Field154.Layout.Column = 2;
app.Field155 = uieditfield(app.Grid3,'numeric');
app.Field155.Layout.Row = 11;
app.Field155.Layout.Column = 1;
app.Field156 = uieditfield(app.Grid3,'numeric');
app.Field156.Layout.Row = 11;
app.Field156.Layout.Column = 2;
app.Field157 = uieditfield(app.Grid3,'numeric');
app.Field157.Layout.Row = 12;
app.Field157.Layout.Column = 1;
app.Field158 = uieditfield(app.Grid3,'numeric');
app.Field158.Layout.Row = 12;
app.Field158.Layout.Column = 2;
app.Field159 = uieditfield(app.Grid3,'numeric');
app.Field159.Layout.Row = 13;
app.Field159.Layout.Column = 1;
app.Field160 = uieditfield(app.Grid3,'numeric');
app.Field160.Layout.Row = 13;
app.Field160.Layout.Column = 2;
app.Field161 = uieditfield(app.Grid3,'numeric');
app.Field161.Layout.Row = 14;
app.Field161.Layout.Column = 1;
app.Field162 = uieditfield(app.Grid3,'numeric');
app.Field162.Layout.Row = 14;
app.Field162.Layout.Column = 2;
app.Field163 = uieditfield(app.Grid3,'numeric');
app.Field163.Layout.Row = 15;
app.Field163.Layout.Column = 1;
app.Field164 = uieditfield(app.Grid3,'numeric');
app.Field164.Layout.Row = 15;
app.Field164.Layout.Column = 2;
app.Field165 = uieditfield(app.Grid3,'numeric');
app.Field165.Layout.Row = 16;
app.Field165.Layout.Column = 1;
app.Field166 = uieditfield(app.Grid3,'numeric');
app.Field166.Layout.Row = 16;
app.Field166.Layout.Column = 2;
app.Field167 = uieditfield(app.Grid3,'numeric');
app.Field167.Layout.Row = 17;
app.Field167.Layout.Column = 1;
app.Field168 = uieditfield(app.Grid3,'numeric');
app.Field168.Layout.Row = 17;
app.Field168.Layout.Column = 2;
app.Field169 = uieditfield(app.Grid3,'numeric');
app.Field169.Layout.Row = 18;
app.Field169.Layout.Column = 1;
app.Field170 = uieditfield(app.Grid3,'numeric');
app.Field170.Layout.Row = 18;
app.Field170.Layout.Column = 2;
app.Field171 = uieditfield(app.Grid3,'numeric');
app.Field171.Layout.Row = 19;
app.Field171.Layout.Column = 1;
app.Field172 = uieditfield(app.Grid3,'numeric');
app.Field172.Layout.Row = 19;
app.Field172.Layout.Column = 2;
app.Field173 = uieditfield(app.Grid3,'numeric');
app.Field173.Layout.Row = 20;
app.Field173.Layout.Column = 1;
app.Field174 = uieditfield(app.Grid3,'numeric');
app.Field174.Layout.Row = 20;
app.Field174.Layout.Column = 2;
app.Field175 = uieditfield(app.Grid3,'numeric');
app.Field175.Layout.Row = 21;
app.Field175.Layout.Column = 1;
app.Field176 = uieditfield(app.Grid3,'numeric');
app.Field176.Layout.Row = 21;
app.Field176.Layout.Column = 2;
app.Field177 = uieditfield(app.Grid3,'numeric');
app.Field177.Layout.Row = 22;
app.Field177.Layout.Column = 1;
app.Field178 = uieditfield(app.Grid3,'numeric');
app.Field178.Layout.Row = 22;
app.Field178.Layout.Column = 2;
app.Field179 = uieditfield(app.Grid3,'numeric');
app.Field179.Layout.Row = 23;
app.Field179.Layout.Column = 1;
app.Field180 = uieditfield(app.Grid3,'numeric');
app.Field180.Layout.Row = 23;
app.Field180.Layout.Column = 2;
app.Field181 = uieditfield(app.Grid3,'numeric');
app.Field181.Layout.Row = 24;
app.Field181.Layout.Column = 1;
app.Field182 = uieditfield(app.Grid3,'numeric');
app.Field182.Layout.Row = 24;
app.Field182.Layout.Column = 2;
app.Field183 = uieditfield(app.Grid3,'numeric');
app.Field183.Layout.Row = 25;
app.Field183.Layout.Column = 1;
app.Field184 = uieditfield(app.Grid3,'numeric');
app.Field184.Layout.Row = 25;
app.Field184.Layout.Column = 2;
app.Field185 = uieditfield(app.Grid3,'numeric');
app.Field185.Layout.Row = 26;
app.Field185.Layout.Column = 1;
app.Field186 = uieditfield(app.Grid3,'numeric');
app.Field186.Layout.Row = 26;
app.Field186.Layout.Column = 2;
app.Field187 = uieditfield(app.Grid3,'numeric');
app.Field187.Layout.Row = 27;
app.Field187.Layout.Column = 1;
app.Field188 = uieditfield(app.Grid3,'numeric');
app.Field188.Layout.Row = 27;
app.Field188.Layout.Column = 2;
app.Field189 = uieditfield(app.Grid3,'numeric');
app.Field189.Layout.Row = 28;
app.Field189.Layout.Column = 1;
app.Field190 = uieditfield(app.Grid3,'numeric');
app.Field190.Layout.Row = 28;
app.Field190.Layout.Column = 2;
app.Field191 = uieditfield(app.Grid3,'numeric');
app.Field191.Layout.Row = 29;
app.Field191.Layout.Column = 1;
app.Field192 = uieditfield(app.Grid3,'numeric');
app.Field192.Layout.Row = 29;
app.Field192.Layout.Column = 2;
app.Field193 = uieditfield(app.Grid3,'numeric');
app.Field193.Layout.Row = 30;
app.Field193.Layout.Column = 1;
app.Field194 = uieditfield(app.Grid3,'numeric');
app.Field194.Layout.Row = 30;
app.Field194.Layout.Column = 2;
app.Field195 = uieditfield(app.Grid3,'numeric');
app.Field195.Layout.Row = 31;
app.Field195.Layout.Column = 1;
app.Field196 = uieditfield(app.Grid3,'numeric');
app.Field196.Layout.Row = 31;
app.Field196.Layout.Column = 2;
app.Field197 = uieditfield(app.Grid3,'numeric');
app.Field197.Layout.Row = 32;
app.Field197.Layout.Column = 1;
app.Field198 = uieditfield(app.Grid3,'numeric');
app.Field198.Layout.Row = 32;
app.Field198.Layout.Column = 2;
app.Field199 = uieditfield(app.Grid3,'numeric');
app.Field199.Layout.Row = 33;
app.Field199.Layout.Column = 1;
app.Field200 = uieditfield(app.Grid3,'numeric');
app.Field200.Layout.Row = 33;
app.Field200.Layout.Column = 2;
end
end
end