function data = waitForPreviewLayout(figure, target)
% waitForPreviewLayout Await a matching Web reply without generating an image or polling rectangles.
%   The figure window waits until no container has resized its children for
%   longer than the Grid Layout resize throttle, waits for pending image loads
%   and ViewModel stabilization, and replies after the next animation frame.
%   The reply travels on the figure ViewModel channel behind the client's
%   position notifications, so MATLAB-side positions are final when it returns.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    target (1, 1) matlab.graphics.Graphics %#ok<INUSA>
end
arguments (Output)
    data (1, 1) struct
end
% Each browser-side wait gives up after this many milliseconds instead of blocking the editor.
waitLimitMilliseconds = 500;
% Grid Layouts relayout their children, and only then report positions to MATLAB, from
% a handler throttled with lodash.throttle(handler, THROTTLE_DELAY, {leading: true,
% trailing: true}), where THROTTLE_DELAY is 200 ms in R2023a through R2026b. The quiet
% period adds a margin to that delay. To check a new release, search the figure client
% bundle for the "containerClientAreaSizeChanged" listener of the Grid Layout controller
% (stored as _throttledHandleParentSizeChanged from R2025b) and for THROTTLE_DELAY in the
% gbtshared/util/EventSupport module it imports; doc/ARCHITECTURE.md lists the bundles.
quietMilliseconds = 220;
% Continuous resizing must not block the editor; the reply then reports quieted = false.
quietLimitMilliseconds = 3000;
clock = tic;
% Struct conversion reads deprecated getters; restore warning state before dispatch.
previous = warning("off", "all");
warningCleanup = onCleanup(@() warning(previous));
figureData = struct(figure); controllerData = struct(figureData.Controller);
host = controllerData.PlatformHost;
hostData = struct(host);
viewModel = controllerData.ViewModel;
clear warningCleanup
% Listen before dispatch so an immediately resolved promise cannot be missed. Failures
% before the figure ViewModel is found arrive on the message service channel instead.
token = string(java.util.UUID.randomUUID());
eventName = "YamadaLayoutSettled";
channel = "/yamada-layout/" + token;
reply = yamada.ui.LayoutStabilizeReply(token);
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
    "figureChannel", string(matlab.ui.internal.FigureServices.getUniqueChannelId(figure)));
resources = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "resources");
configJSON = string(jsonencode(configuration));
script = replace(string(fileread(fullfile(resources, "layout-settle-request.js"))), "CFG", configJSON);
if isfield(hostData, "CEF")
    hostData.CEF.executeJS(script, 10);
elseif ~isMATLABReleaseOlderThan("R2025a") && endsWith(string(class(host)), ".DivFigurePlatformHost")
    bootstrap = replace(string(fileread(fullfile(resources, "layout-settle-desktop.js"))), "CFG", configJSON);
    dispatchCleanup = dispatchDesktopScript(replace(bootstrap, "SCRIPT", string(jsonencode(script))));
else
    error("yamada:PreviewLayout:NoFigureWindow", "The figure host does not support layout requests.");
end
waitfor(reply, "Done", true);
% Validate the matching reply and release the request resources.
data = reply.Data;
data.matlabSeconds = toc(clock);
assert(isfield(data, "token") && string(data.token) == token);
clear dispatchCleanup watchdogCleanup listenerCleanup subscriptionCleanup
if isfield(data, "error"), error("yamada:PreviewLayout:SettleReply", "%s", string(data.error)); end
end

function cleanup = dispatchDesktopScript(script)
% dispatchDesktopScript Send a project-owned script through a temporary desktop panel.
arguments (Input)
    script (1, 1) string
end
arguments (Output)
    cleanup (1, 1) onCleanup
end
% The internal panel renders its content in the desktop page. Escape the
% event attribute so the script is passed to it verbatim.
app = matlab.ui.container.internal.RootApp.getInstance();
tag = "yamadaLayout_" + string(java.util.UUID.randomUUID());
panel = matlab.ui.container.internal.appcontainer.Panel( ...
    "Tag", tag, "Title", "Yamada", "Region", "bottom");
script = replace("this.onerror=null;" + script, "&", "&amp;");
script = replace(script, [char(34), "<", ">"], ["&quot;", "&lt;", "&gt;"]);
panel.Content = "<img src='yamada-layout-request' onerror=" + char(34) + script + char(34) + ">";
panel.Opened = false;
app.add(panel);
cleanup = onCleanup(@() app.removePanel(tag));
end

function acceptEvent(reply, event)
% acceptEvent Forward a figure ViewModel event payload to the token-matched reply.
arguments (Input)
    reply (1, 1) yamada.ui.LayoutStabilizeReply
    event
end
payload = event.data;
if isstruct(payload) && isscalar(payload), reply.accept(payload); end
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
