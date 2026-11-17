function data = waitForPreviewLayout(figure, target)
% waitForPreviewLayout Await a matching Web reply without generating an image or polling rectangles.
%   The figure window waits until no container has resized its children for
%   longer than the Grid Layout resize throttle, waits for pending image loads
%   and ViewModel stabilization, and replies after the next animation frame.
%   The reply travels on the figure ViewModel channel behind the client's
%   position notifications, so MATLAB-side positions are final when it returns.
%   The reply also reports route, "cef" for a figure with its own window or
%   "desktop" for a desktop DivFigure, and installed, which is true when this
%   wait installed the session's desktop receiver.
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
resources = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "resources");
template = string(fileread(fullfile(resources, "layout-settle-request.js")));
% Choose the page route. Desktop DivFigures from R2025a have no CEF window; their
% receiver is installed once per MATLAB session before the first request.
installed = false;
if isfield(hostData, "CEF")
    route = "cef";
elseif ~isMATLABReleaseOlderThan("R2025a") && endsWith(string(class(host)), ".DivFigurePlatformHost")
    route = "desktop";
    installed = ensureDesktopReceiver(resources, template);
else
    error("yamada:PreviewLayout:NoFigureWindow", "The figure host does not support layout requests.");
end
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
if route == "cef"
    hostData.CEF.executeJS(replace(template, "CFG", string(jsonencode(configuration))), 10);
else
    message.publish(char(desktopRequestChannel()), configuration);
end
waitfor(reply, "Done", true);
% A receiver lost with its page cannot answer; reinstall it on the next request.
if route == "desktop" && reply.TimedOut, desktopReceiver("reset"); end
% Validate the matching reply and release the request resources.
data = reply.Data;
data.matlabSeconds = toc(clock);
data.route = route;
data.installed = installed;
assert(isfield(data, "token") && string(data.token) == token);
clear watchdogCleanup listenerCleanup subscriptionCleanup
if isfield(data, "error"), error("yamada:PreviewLayout:SettleReply", "%s", string(data.error)); end
end

function installed = ensureDesktopReceiver(resources, template)
% ensureDesktopReceiver Install the desktop-page request receiver unless this session has it.
%   The temporary panel is the only point that relies on the desktop running
%   script from panel content. When that stops, the route is disabled for the
%   session and every later wait reports DesktopInjectionBlocked at once.
arguments (Input)
    resources (1, 1) string
    template (1, 1) string
end
arguments (Output)
    installed (1, 1) logical
end
state = desktopReceiver("get");
if state.Blocked ~= ""
    error("yamada:PreviewLayout:DesktopInjectionBlocked", "%s", state.Blocked);
end
bootstrap = string(fileread(fullfile(resources, "layout-settle-desktop.js")));
% Compare the installed sources so an updated yamada replaces the stale receiver.
source = bootstrap + template;
installed = state.Source ~= source;
if ~installed, return, end
% Wait for the bootstrap's acknowledgement on a token-matched install channel.
token = string(java.util.UUID.randomUUID());
channel = "/yamada-layout/install/" + token;
install = struct("channel", channel, "token", token, "requests", desktopRequestChannel());
script = replace(bootstrap, "INSTALL", string(jsonencode(install)));
script = replace(script, "SCRIPT", string(jsonencode(template)));
reply = yamada.ui.LayoutStabilizeReply(token);
subscription = message.subscribe(char(channel), @(data) reply.accept(data));
subscriptionCleanup = onCleanup(@() message.unsubscribe(subscription));
watchdog = timer("ExecutionMode", "singleShot", "StartDelay", 5, "TimerFcn", @(~, ~) reply.expire());
watchdogCleanup = onCleanup(@() deleteWatchdog(watchdog));
start(watchdog);
panelCleanup = dispatchDesktopScript(script);
waitfor(reply, "Done", true);
clear panelCleanup watchdogCleanup subscriptionCleanup
% Record the outcome; a silent desktop means the injection point no longer runs script.
if reply.TimedOut
    reason = "The MATLAB desktop did not run the layout receiver from RootApp panel content " + ...
        "within 5 s; desktop layout requests are disabled for this MATLAB session. " + ...
        "Check dev/compatibility/NativeBehaviorTest on this release.";
    desktopReceiver("block", reason);
    error("yamada:PreviewLayout:DesktopInjectionBlocked", "%s", reason);
end
if isfield(reply.Data, "error")
    error("yamada:PreviewLayout:DesktopReceiver", "%s", string(reply.Data.error));
end
desktopReceiver("install", source);
end

function state = desktopReceiver(command, value)
% desktopReceiver Hold the installed desktop receiver source and blocked reason for this session.
arguments (Input)
    command (1, 1) string {mustBeMember(command, ["get", "install", "block", "reset"])}
    value (1, 1) string = ""
end
arguments (Output)
    state (1, 1) struct
end
persistent current
if isempty(current), current = struct("Source", "", "Blocked", ""); end
switch command
    case "install"
        current.Source = value;
    case "block"
        current = struct("Source", "", "Blocked", value);
    case "reset"
        current.Source = "";
end
state = current;
end

function channel = desktopRequestChannel()
% desktopRequestChannel Return the message channel the desktop receiver subscribes to.
arguments (Output)
    channel (1, 1) string
end
channel = "/yamada-layout/desktop-request";
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
