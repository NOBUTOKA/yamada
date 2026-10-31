classdef UpdateDistributionFixture < handle
properties
UIFigure matlab.ui.Figure
ComparisonButton matlab.ui.control.Button
Panel1 matlab.ui.container.Panel
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
app.Panel1 = uipanel(app.UIFigure);
app.Panel1.Position = [10 10 315 1360];
app.Field1 = uieditfield(app.Panel1,'numeric');
app.Field1.Position = [5 1320 140 22];
app.Field2 = uieditfield(app.Panel1,'numeric');
app.Field2.Position = [155 1320 140 22];
app.Field3 = uieditfield(app.Panel1,'numeric');
app.Field3.Position = [5 1295 140 22];
app.Field4 = uieditfield(app.Panel1,'numeric');
app.Field4.Position = [155 1295 140 22];
app.Field5 = uieditfield(app.Panel1,'numeric');
app.Field5.Position = [5 1270 140 22];
app.Field6 = uieditfield(app.Panel1,'numeric');
app.Field6.Position = [155 1270 140 22];
app.Field7 = uieditfield(app.Panel1,'numeric');
app.Field7.Position = [5 1245 140 22];
app.Field8 = uieditfield(app.Panel1,'numeric');
app.Field8.Position = [155 1245 140 22];
app.Field9 = uieditfield(app.Panel1,'numeric');
app.Field9.Position = [5 1220 140 22];
app.Field10 = uieditfield(app.Panel1,'numeric');
app.Field10.Position = [155 1220 140 22];
app.Field11 = uieditfield(app.Panel1,'numeric');
app.Field11.Position = [5 1195 140 22];
app.Field12 = uieditfield(app.Panel1,'numeric');
app.Field12.Position = [155 1195 140 22];
app.Field13 = uieditfield(app.Panel1,'numeric');
app.Field13.Position = [5 1170 140 22];
app.Field14 = uieditfield(app.Panel1,'numeric');
app.Field14.Position = [155 1170 140 22];
app.Field15 = uieditfield(app.Panel1,'numeric');
app.Field15.Position = [5 1145 140 22];
app.Field16 = uieditfield(app.Panel1,'numeric');
app.Field16.Position = [155 1145 140 22];
app.Field17 = uieditfield(app.Panel1,'numeric');
app.Field17.Position = [5 1120 140 22];
app.Field18 = uieditfield(app.Panel1,'numeric');
app.Field18.Position = [155 1120 140 22];
app.Field19 = uieditfield(app.Panel1,'numeric');
app.Field19.Position = [5 1095 140 22];
app.Field20 = uieditfield(app.Panel1,'numeric');
app.Field20.Position = [155 1095 140 22];
app.Field21 = uieditfield(app.Panel1,'numeric');
app.Field21.Position = [5 1070 140 22];
app.Field22 = uieditfield(app.Panel1,'numeric');
app.Field22.Position = [155 1070 140 22];
app.Field23 = uieditfield(app.Panel1,'numeric');
app.Field23.Position = [5 1045 140 22];
app.Field24 = uieditfield(app.Panel1,'numeric');
app.Field24.Position = [155 1045 140 22];
app.Field25 = uieditfield(app.Panel1,'numeric');
app.Field25.Position = [5 1020 140 22];
app.Field26 = uieditfield(app.Panel1,'numeric');
app.Field26.Position = [155 1020 140 22];
app.Field27 = uieditfield(app.Panel1,'numeric');
app.Field27.Position = [5 995 140 22];
app.Field28 = uieditfield(app.Panel1,'numeric');
app.Field28.Position = [155 995 140 22];
app.Field29 = uieditfield(app.Panel1,'numeric');
app.Field29.Position = [5 970 140 22];
app.Field30 = uieditfield(app.Panel1,'numeric');
app.Field30.Position = [155 970 140 22];
app.Field31 = uieditfield(app.Panel1,'numeric');
app.Field31.Position = [5 945 140 22];
app.Field32 = uieditfield(app.Panel1,'numeric');
app.Field32.Position = [155 945 140 22];
app.Field33 = uieditfield(app.Panel1,'numeric');
app.Field33.Position = [5 920 140 22];
app.Field34 = uieditfield(app.Panel1,'numeric');
app.Field34.Position = [155 920 140 22];
app.Field35 = uieditfield(app.Panel1,'numeric');
app.Field35.Position = [5 895 140 22];
app.Field36 = uieditfield(app.Panel1,'numeric');
app.Field36.Position = [155 895 140 22];
app.Field37 = uieditfield(app.Panel1,'numeric');
app.Field37.Position = [5 870 140 22];
app.Field38 = uieditfield(app.Panel1,'numeric');
app.Field38.Position = [155 870 140 22];
app.Field39 = uieditfield(app.Panel1,'numeric');
app.Field39.Position = [5 845 140 22];
app.Field40 = uieditfield(app.Panel1,'numeric');
app.Field40.Position = [155 845 140 22];
app.Field41 = uieditfield(app.Panel1,'numeric');
app.Field41.Position = [5 820 140 22];
app.Field42 = uieditfield(app.Panel1,'numeric');
app.Field42.Position = [155 820 140 22];
app.Field43 = uieditfield(app.Panel1,'numeric');
app.Field43.Position = [5 795 140 22];
app.Field44 = uieditfield(app.Panel1,'numeric');
app.Field44.Position = [155 795 140 22];
app.Field45 = uieditfield(app.Panel1,'numeric');
app.Field45.Position = [5 770 140 22];
app.Field46 = uieditfield(app.Panel1,'numeric');
app.Field46.Position = [155 770 140 22];
app.Field47 = uieditfield(app.Panel1,'numeric');
app.Field47.Position = [5 745 140 22];
app.Field48 = uieditfield(app.Panel1,'numeric');
app.Field48.Position = [155 745 140 22];
app.Field49 = uieditfield(app.Panel1,'numeric');
app.Field49.Position = [5 720 140 22];
app.Field50 = uieditfield(app.Panel1,'numeric');
app.Field50.Position = [155 720 140 22];
app.Field51 = uieditfield(app.Panel1,'numeric');
app.Field51.Position = [5 695 140 22];
app.Field52 = uieditfield(app.Panel1,'numeric');
app.Field52.Position = [155 695 140 22];
app.Field53 = uieditfield(app.Panel1,'numeric');
app.Field53.Position = [5 670 140 22];
app.Field54 = uieditfield(app.Panel1,'numeric');
app.Field54.Position = [155 670 140 22];
app.Field55 = uieditfield(app.Panel1,'numeric');
app.Field55.Position = [5 645 140 22];
app.Field56 = uieditfield(app.Panel1,'numeric');
app.Field56.Position = [155 645 140 22];
app.Field57 = uieditfield(app.Panel1,'numeric');
app.Field57.Position = [5 620 140 22];
app.Field58 = uieditfield(app.Panel1,'numeric');
app.Field58.Position = [155 620 140 22];
app.Field59 = uieditfield(app.Panel1,'numeric');
app.Field59.Position = [5 595 140 22];
app.Field60 = uieditfield(app.Panel1,'numeric');
app.Field60.Position = [155 595 140 22];
app.Field61 = uieditfield(app.Panel1,'numeric');
app.Field61.Position = [5 570 140 22];
app.Field62 = uieditfield(app.Panel1,'numeric');
app.Field62.Position = [155 570 140 22];
app.Field63 = uieditfield(app.Panel1,'numeric');
app.Field63.Position = [5 545 140 22];
app.Field64 = uieditfield(app.Panel1,'numeric');
app.Field64.Position = [155 545 140 22];
app.Field65 = uieditfield(app.Panel1,'numeric');
app.Field65.Position = [5 520 140 22];
app.Field66 = uieditfield(app.Panel1,'numeric');
app.Field66.Position = [155 520 140 22];
app.Field67 = uieditfield(app.Panel1,'numeric');
app.Field67.Position = [5 495 140 22];
app.ComparisonButton = uibutton(app.Panel1);
app.ComparisonButton.Text = 'Comparison';
app.Panel2 = uipanel(app.UIFigure);
app.Panel2.Position = [335 10 315 1360];
app.Field68 = uieditfield(app.Panel2,'numeric');
app.Field68.Position = [5 1320 140 22];
app.Field69 = uieditfield(app.Panel2,'numeric');
app.Field69.Position = [155 1320 140 22];
app.Field70 = uieditfield(app.Panel2,'numeric');
app.Field70.Position = [5 1295 140 22];
app.Field71 = uieditfield(app.Panel2,'numeric');
app.Field71.Position = [155 1295 140 22];
app.Field72 = uieditfield(app.Panel2,'numeric');
app.Field72.Position = [5 1270 140 22];
app.Field73 = uieditfield(app.Panel2,'numeric');
app.Field73.Position = [155 1270 140 22];
app.Field74 = uieditfield(app.Panel2,'numeric');
app.Field74.Position = [5 1245 140 22];
app.Field75 = uieditfield(app.Panel2,'numeric');
app.Field75.Position = [155 1245 140 22];
app.Field76 = uieditfield(app.Panel2,'numeric');
app.Field76.Position = [5 1220 140 22];
app.Field77 = uieditfield(app.Panel2,'numeric');
app.Field77.Position = [155 1220 140 22];
app.Field78 = uieditfield(app.Panel2,'numeric');
app.Field78.Position = [5 1195 140 22];
app.Field79 = uieditfield(app.Panel2,'numeric');
app.Field79.Position = [155 1195 140 22];
app.Field80 = uieditfield(app.Panel2,'numeric');
app.Field80.Position = [5 1170 140 22];
app.Field81 = uieditfield(app.Panel2,'numeric');
app.Field81.Position = [155 1170 140 22];
app.Field82 = uieditfield(app.Panel2,'numeric');
app.Field82.Position = [5 1145 140 22];
app.Field83 = uieditfield(app.Panel2,'numeric');
app.Field83.Position = [155 1145 140 22];
app.Field84 = uieditfield(app.Panel2,'numeric');
app.Field84.Position = [5 1120 140 22];
app.Field85 = uieditfield(app.Panel2,'numeric');
app.Field85.Position = [155 1120 140 22];
app.Field86 = uieditfield(app.Panel2,'numeric');
app.Field86.Position = [5 1095 140 22];
app.Field87 = uieditfield(app.Panel2,'numeric');
app.Field87.Position = [155 1095 140 22];
app.Field88 = uieditfield(app.Panel2,'numeric');
app.Field88.Position = [5 1070 140 22];
app.Field89 = uieditfield(app.Panel2,'numeric');
app.Field89.Position = [155 1070 140 22];
app.Field90 = uieditfield(app.Panel2,'numeric');
app.Field90.Position = [5 1045 140 22];
app.Field91 = uieditfield(app.Panel2,'numeric');
app.Field91.Position = [155 1045 140 22];
app.Field92 = uieditfield(app.Panel2,'numeric');
app.Field92.Position = [5 1020 140 22];
app.Field93 = uieditfield(app.Panel2,'numeric');
app.Field93.Position = [155 1020 140 22];
app.Field94 = uieditfield(app.Panel2,'numeric');
app.Field94.Position = [5 995 140 22];
app.Field95 = uieditfield(app.Panel2,'numeric');
app.Field95.Position = [155 995 140 22];
app.Field96 = uieditfield(app.Panel2,'numeric');
app.Field96.Position = [5 970 140 22];
app.Field97 = uieditfield(app.Panel2,'numeric');
app.Field97.Position = [155 970 140 22];
app.Field98 = uieditfield(app.Panel2,'numeric');
app.Field98.Position = [5 945 140 22];
app.Field99 = uieditfield(app.Panel2,'numeric');
app.Field99.Position = [155 945 140 22];
app.Field100 = uieditfield(app.Panel2,'numeric');
app.Field100.Position = [5 920 140 22];
app.Field101 = uieditfield(app.Panel2,'numeric');
app.Field101.Position = [155 920 140 22];
app.Field102 = uieditfield(app.Panel2,'numeric');
app.Field102.Position = [5 895 140 22];
app.Field103 = uieditfield(app.Panel2,'numeric');
app.Field103.Position = [155 895 140 22];
app.Field104 = uieditfield(app.Panel2,'numeric');
app.Field104.Position = [5 870 140 22];
app.Field105 = uieditfield(app.Panel2,'numeric');
app.Field105.Position = [155 870 140 22];
app.Field106 = uieditfield(app.Panel2,'numeric');
app.Field106.Position = [5 845 140 22];
app.Field107 = uieditfield(app.Panel2,'numeric');
app.Field107.Position = [155 845 140 22];
app.Field108 = uieditfield(app.Panel2,'numeric');
app.Field108.Position = [5 820 140 22];
app.Field109 = uieditfield(app.Panel2,'numeric');
app.Field109.Position = [155 820 140 22];
app.Field110 = uieditfield(app.Panel2,'numeric');
app.Field110.Position = [5 795 140 22];
app.Field111 = uieditfield(app.Panel2,'numeric');
app.Field111.Position = [155 795 140 22];
app.Field112 = uieditfield(app.Panel2,'numeric');
app.Field112.Position = [5 770 140 22];
app.Field113 = uieditfield(app.Panel2,'numeric');
app.Field113.Position = [155 770 140 22];
app.Field114 = uieditfield(app.Panel2,'numeric');
app.Field114.Position = [5 745 140 22];
app.Field115 = uieditfield(app.Panel2,'numeric');
app.Field115.Position = [155 745 140 22];
app.Field116 = uieditfield(app.Panel2,'numeric');
app.Field116.Position = [5 720 140 22];
app.Field117 = uieditfield(app.Panel2,'numeric');
app.Field117.Position = [155 720 140 22];
app.Field118 = uieditfield(app.Panel2,'numeric');
app.Field118.Position = [5 695 140 22];
app.Field119 = uieditfield(app.Panel2,'numeric');
app.Field119.Position = [155 695 140 22];
app.Field120 = uieditfield(app.Panel2,'numeric');
app.Field120.Position = [5 670 140 22];
app.Field121 = uieditfield(app.Panel2,'numeric');
app.Field121.Position = [155 670 140 22];
app.Field122 = uieditfield(app.Panel2,'numeric');
app.Field122.Position = [5 645 140 22];
app.Field123 = uieditfield(app.Panel2,'numeric');
app.Field123.Position = [155 645 140 22];
app.Field124 = uieditfield(app.Panel2,'numeric');
app.Field124.Position = [5 620 140 22];
app.Field125 = uieditfield(app.Panel2,'numeric');
app.Field125.Position = [155 620 140 22];
app.Field126 = uieditfield(app.Panel2,'numeric');
app.Field126.Position = [5 595 140 22];
app.Field127 = uieditfield(app.Panel2,'numeric');
app.Field127.Position = [155 595 140 22];
app.Field128 = uieditfield(app.Panel2,'numeric');
app.Field128.Position = [5 570 140 22];
app.Field129 = uieditfield(app.Panel2,'numeric');
app.Field129.Position = [155 570 140 22];
app.Field130 = uieditfield(app.Panel2,'numeric');
app.Field130.Position = [5 545 140 22];
app.Field131 = uieditfield(app.Panel2,'numeric');
app.Field131.Position = [155 545 140 22];
app.Field132 = uieditfield(app.Panel2,'numeric');
app.Field132.Position = [5 520 140 22];
app.Field133 = uieditfield(app.Panel2,'numeric');
app.Field133.Position = [155 520 140 22];
app.Field134 = uieditfield(app.Panel2,'numeric');
app.Field134.Position = [5 495 140 22];
app.Panel3 = uipanel(app.UIFigure);
app.Panel3.Position = [660 10 315 1360];
app.Field135 = uieditfield(app.Panel3,'numeric');
app.Field135.Position = [5 1320 140 22];
app.Field136 = uieditfield(app.Panel3,'numeric');
app.Field136.Position = [155 1320 140 22];
app.Field137 = uieditfield(app.Panel3,'numeric');
app.Field137.Position = [5 1295 140 22];
app.Field138 = uieditfield(app.Panel3,'numeric');
app.Field138.Position = [155 1295 140 22];
app.Field139 = uieditfield(app.Panel3,'numeric');
app.Field139.Position = [5 1270 140 22];
app.Field140 = uieditfield(app.Panel3,'numeric');
app.Field140.Position = [155 1270 140 22];
app.Field141 = uieditfield(app.Panel3,'numeric');
app.Field141.Position = [5 1245 140 22];
app.Field142 = uieditfield(app.Panel3,'numeric');
app.Field142.Position = [155 1245 140 22];
app.Field143 = uieditfield(app.Panel3,'numeric');
app.Field143.Position = [5 1220 140 22];
app.Field144 = uieditfield(app.Panel3,'numeric');
app.Field144.Position = [155 1220 140 22];
app.Field145 = uieditfield(app.Panel3,'numeric');
app.Field145.Position = [5 1195 140 22];
app.Field146 = uieditfield(app.Panel3,'numeric');
app.Field146.Position = [155 1195 140 22];
app.Field147 = uieditfield(app.Panel3,'numeric');
app.Field147.Position = [5 1170 140 22];
app.Field148 = uieditfield(app.Panel3,'numeric');
app.Field148.Position = [155 1170 140 22];
app.Field149 = uieditfield(app.Panel3,'numeric');
app.Field149.Position = [5 1145 140 22];
app.Field150 = uieditfield(app.Panel3,'numeric');
app.Field150.Position = [155 1145 140 22];
app.Field151 = uieditfield(app.Panel3,'numeric');
app.Field151.Position = [5 1120 140 22];
app.Field152 = uieditfield(app.Panel3,'numeric');
app.Field152.Position = [155 1120 140 22];
app.Field153 = uieditfield(app.Panel3,'numeric');
app.Field153.Position = [5 1095 140 22];
app.Field154 = uieditfield(app.Panel3,'numeric');
app.Field154.Position = [155 1095 140 22];
app.Field155 = uieditfield(app.Panel3,'numeric');
app.Field155.Position = [5 1070 140 22];
app.Field156 = uieditfield(app.Panel3,'numeric');
app.Field156.Position = [155 1070 140 22];
app.Field157 = uieditfield(app.Panel3,'numeric');
app.Field157.Position = [5 1045 140 22];
app.Field158 = uieditfield(app.Panel3,'numeric');
app.Field158.Position = [155 1045 140 22];
app.Field159 = uieditfield(app.Panel3,'numeric');
app.Field159.Position = [5 1020 140 22];
app.Field160 = uieditfield(app.Panel3,'numeric');
app.Field160.Position = [155 1020 140 22];
app.Field161 = uieditfield(app.Panel3,'numeric');
app.Field161.Position = [5 995 140 22];
app.Field162 = uieditfield(app.Panel3,'numeric');
app.Field162.Position = [155 995 140 22];
app.Field163 = uieditfield(app.Panel3,'numeric');
app.Field163.Position = [5 970 140 22];
app.Field164 = uieditfield(app.Panel3,'numeric');
app.Field164.Position = [155 970 140 22];
app.Field165 = uieditfield(app.Panel3,'numeric');
app.Field165.Position = [5 945 140 22];
app.Field166 = uieditfield(app.Panel3,'numeric');
app.Field166.Position = [155 945 140 22];
app.Field167 = uieditfield(app.Panel3,'numeric');
app.Field167.Position = [5 920 140 22];
app.Field168 = uieditfield(app.Panel3,'numeric');
app.Field168.Position = [155 920 140 22];
app.Field169 = uieditfield(app.Panel3,'numeric');
app.Field169.Position = [5 895 140 22];
app.Field170 = uieditfield(app.Panel3,'numeric');
app.Field170.Position = [155 895 140 22];
app.Field171 = uieditfield(app.Panel3,'numeric');
app.Field171.Position = [5 870 140 22];
app.Field172 = uieditfield(app.Panel3,'numeric');
app.Field172.Position = [155 870 140 22];
app.Field173 = uieditfield(app.Panel3,'numeric');
app.Field173.Position = [5 845 140 22];
app.Field174 = uieditfield(app.Panel3,'numeric');
app.Field174.Position = [155 845 140 22];
app.Field175 = uieditfield(app.Panel3,'numeric');
app.Field175.Position = [5 820 140 22];
app.Field176 = uieditfield(app.Panel3,'numeric');
app.Field176.Position = [155 820 140 22];
app.Field177 = uieditfield(app.Panel3,'numeric');
app.Field177.Position = [5 795 140 22];
app.Field178 = uieditfield(app.Panel3,'numeric');
app.Field178.Position = [155 795 140 22];
app.Field179 = uieditfield(app.Panel3,'numeric');
app.Field179.Position = [5 770 140 22];
app.Field180 = uieditfield(app.Panel3,'numeric');
app.Field180.Position = [155 770 140 22];
app.Field181 = uieditfield(app.Panel3,'numeric');
app.Field181.Position = [5 745 140 22];
app.Field182 = uieditfield(app.Panel3,'numeric');
app.Field182.Position = [155 745 140 22];
app.Field183 = uieditfield(app.Panel3,'numeric');
app.Field183.Position = [5 720 140 22];
app.Field184 = uieditfield(app.Panel3,'numeric');
app.Field184.Position = [155 720 140 22];
app.Field185 = uieditfield(app.Panel3,'numeric');
app.Field185.Position = [5 695 140 22];
app.Field186 = uieditfield(app.Panel3,'numeric');
app.Field186.Position = [155 695 140 22];
app.Field187 = uieditfield(app.Panel3,'numeric');
app.Field187.Position = [5 670 140 22];
app.Field188 = uieditfield(app.Panel3,'numeric');
app.Field188.Position = [155 670 140 22];
app.Field189 = uieditfield(app.Panel3,'numeric');
app.Field189.Position = [5 645 140 22];
app.Field190 = uieditfield(app.Panel3,'numeric');
app.Field190.Position = [155 645 140 22];
app.Field191 = uieditfield(app.Panel3,'numeric');
app.Field191.Position = [5 620 140 22];
app.Field192 = uieditfield(app.Panel3,'numeric');
app.Field192.Position = [155 620 140 22];
app.Field193 = uieditfield(app.Panel3,'numeric');
app.Field193.Position = [5 595 140 22];
app.Field194 = uieditfield(app.Panel3,'numeric');
app.Field194.Position = [155 595 140 22];
app.Field195 = uieditfield(app.Panel3,'numeric');
app.Field195.Position = [5 570 140 22];
app.Field196 = uieditfield(app.Panel3,'numeric');
app.Field196.Position = [155 570 140 22];
app.Field197 = uieditfield(app.Panel3,'numeric');
app.Field197.Position = [5 545 140 22];
app.Field198 = uieditfield(app.Panel3,'numeric');
app.Field198.Position = [155 545 140 22];
app.Field199 = uieditfield(app.Panel3,'numeric');
app.Field199.Position = [5 520 140 22];
app.Field200 = uieditfield(app.Panel3,'numeric');
app.Field200.Position = [155 520 140 22];
end
end
end