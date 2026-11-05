function data = waitForPreviewLayout(figure, target)
% waitForPreviewLayout Await a matching Web reply without generating an image or polling rectangles.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    target
end
arguments (Output)
    data (1, 1) struct
end
clock = tic;
% Struct conversion reads deprecated getters; restore warning state before dispatch.
previous = warning("off", "all");
warningCleanup = onCleanup(@() warning(previous));
figureData = struct(figure); controllerData = struct(figureData.Controller);
hostData = struct(controllerData.PlatformHost); window = hostData.CEF;
targetData = struct(target); id = string(targetData.Controller.getId());
clear warningCleanup
% Subscribe before dispatch so an immediately resolved promise cannot be missed.
token = string(java.util.UUID.randomUUID());
channel = "/yamada-layout/" + token;
reply = yamada.ui.LayoutStabilizeReply(token);
subscription = message.subscribe(char(channel), @(data) reply.accept(data));
subscriptionCleanup = onCleanup(@() message.unsubscribe(subscription));
watchdog = timer("ExecutionMode", "singleShot", "StartDelay", 10, "TimerFcn", @(~, ~) reply.expire());
watchdogCleanup = onCleanup(@() deleteWatchdog(watchdog));
start(watchdog);
configuration = struct("channel", channel, "token", token, "target", id);
script = string(fileread(fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "resources", "stabilize-request.js")));
script = replace(script, "CFG", string(jsonencode(configuration)));
window.executeJS(script, 10);
waitfor(reply, "Done", true);
data = reply.Data;
data.matlabSeconds = toc(clock);
assert(isfield(data, "token") && string(data.token) == token);
if isfield(data, "error"), error("yamada:PreviewLayout:StabilizeReply", "%s", string(data.error)); end
clear watchdogCleanup subscriptionCleanup
end

function deleteWatchdog(watchdog)
% deleteWatchdog Remove only the non-polling timeout guard owned by this request.
arguments (Input)
    watchdog (1, 1) timer
end
if isvalid(watchdog), stop(watchdog); delete(watchdog); end
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
