% ========================================================================================
% Filename: Visualize.m
% Author: Rolfe Power
% ========================================================================================

%% Constants
DATA_FILE_NAME = "output.csv";

%% Load Data
if ~isfile(DATA_FILE_NAME)
    error("Cannot find file %s", DATA_FILE_NAME);
end
data = readtable(DATA_FILE_NAME, "Delimiter", ",", "ReadVariableNames", true);

%% Content Type Histogram
figure()
histogram(categorical(data.content_group), "DisplayOrder", "ascend");
set(gca, "FontSize", 16, "ticklabelinterpreter", "Latex")
ylabel("Count", "FontSize", 16, "interpreter", "Latex");
grid on


%% Content Type Pie Chart
figure()
tps = string(data.content_group);
tps(tps ~= "pdf" & tps ~= "powerpoint" & tps ~= "video") = "other";
t = pie(categorical(tps));
set(gca, "FontSize", 16, "TickLabelInterpreter", "Latex");