function info = waitForFigureLayout(fig)
% waitForFigureLayout Wait for browser layout before reading component positions.
%
%   drawnow;
%   info = waitForFigureLayout(fig);  % Diagnostics are optional.
%
%   fig is the MATLAB UI figure that contains the components. Its host must
%   provide a CEF browser window. See README.md for figure creation by release.
%
%   info is an optional output struct with diagnostics about the layout wait.
%   info.hooked and info.watched count new hooks and observed resize emitters.
%   info.quieted indicates whether resizing quieted within 3 seconds.
%   info.imagesWaited counts pending images. info.imagesLoaded indicates
%   whether they all completed or reported an error within 500 ms.
%   info.stabilized and info.framed indicate whether ViewModel stabilization
%   and an animation frame completed within 500 ms each.
%   info.matlabSeconds is the elapsed MATLAB time. info.token is the request ID.
arguments (Input)
    fig (1, 1) matlab.ui.Figure
end
arguments (Output)
    info (1, 1) struct
end
% Bound each image, ViewModel, and animation-frame wait.
waitLimitMilliseconds = 500;
% Grid Layout uses a 200 ms resize throttle with a trailing call.
quietMilliseconds = 220;
% If resizing continues past this limit, the reply reports quieted = false.
quietLimitMilliseconds = 3000;
clock = tic;
% Struct conversion reads deprecated getters; restore warning state before dispatch.
previous = warning("off", "all");
warningCleanup = onCleanup(@() warning(previous));
figureData = struct(fig);
controllerData = struct(figureData.Controller);
host = controllerData.PlatformHost;
hostData = struct(host);
viewModel = controllerData.ViewModel;
clear warningCleanup
% Desktop-hosted figures from R2025a need the isolated figure constructor.
if ~isfield(hostData, "CEF") || isempty(hostData.CEF)
    error("waitForFigureLayout:NoFigureWindow", ...
        "The figure host %s has no CEF window. In R2025a or later, " + ...
        "create the figure with matlab.ui.internal.uifigureIsolated.", class(host));
end
window = hostData.CEF;
% Listen before dispatch so an immediately resolved promise cannot be missed. Failures
% before the figure ViewModel is found arrive on the message service channel instead.
token = string(java.util.UUID.randomUUID());
eventName = "FigureLayoutWaitCompleted_" + erase(token, "-");
channel = "/figure-layout-wait/" + token;
sourceFolder = fileparts(mfilename("fullpath"));
reply = createReply(sourceFolder, token);
subscription = message.subscribe(char(channel), @(data) reply.accept(data));
subscriptionCleanup = onCleanup(@() message.unsubscribe(subscription));
listener = viewModel.addEventListener(char(eventName), @(~, event) acceptEvent(reply, event));
listenerCleanup = onCleanup(@() delete(listener));
watchdog = timer("ExecutionMode", "singleShot", "StartDelay", 10, "TimerFcn", @(~, ~) reply.expire());
watchdogCleanup = onCleanup(@() deleteWatchdog(watchdog));
start(watchdog);
% Dispatch the bounded browser-side wait.
configuration = struct("channel", channel, "token", token, "limit", waitLimitMilliseconds, ...
    "quiet", quietMilliseconds, "quietLimit", quietLimitMilliseconds, "event", eventName, ...
    "figure", string(viewModel.getId()), ...
    "figureChannel", string(matlab.ui.internal.FigureServices.getUniqueChannelId(fig)));
script = string(fileread(fullfile(sourceFolder, "waitForFigureLayout.js")));
script = replace(script, "__LAYOUT_WAIT_CONFIGURATION__", string(jsonencode(configuration)));
window.executeJS(char(script), 10);
waitfor(reply, "Done", true);
info = reply.Data;
clear watchdogCleanup listenerCleanup subscriptionCleanup
if isfield(info, "error")
    error("waitForFigureLayout:SettleReply", "%s", string(info.error));
end
info.matlabSeconds = toc(clock);
end

function reply = createReply(folder, token)
% Resolve the sibling class when this library is vendored inside a namespace.
className = "FigureLayoutWaitReply";
[parent, name] = fileparts(folder);
while startsWith(name, "+")
    className = extractAfter(string(name), 1) + "." + className;
    [parent, name] = fileparts(parent);
end
reply = feval(className, token);
end

function acceptEvent(reply, event)
% acceptEvent Forward a figure ViewModel event payload to the token-matched reply.
reply.accept(event.data);
end

function deleteWatchdog(watchdog)
% deleteWatchdog Remove only the non-polling timeout guard owned by this request.
arguments (Input)
    watchdog (1, 1) timer
end
stop(watchdog);
delete(watchdog);
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of waitForFigureLayout.

waitForFigureLayout is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

waitForFigureLayout is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with waitForFigureLayout. If not, see <https://www.gnu.org/licenses/>.
%}

