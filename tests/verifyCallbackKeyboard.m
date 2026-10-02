function evidence = verifyCallbackKeyboard()
% verifyCallbackKeyboard Verify native Tab, Enter and F5 inside an owned visible popup.
%   Keys are sent only while this verification popup reports keyboard focus.
arguments (Output)
    evidence (1, 1) struct
end
states = [macd.model.CallbackState("FirstFcn", "absent"), ...
    macd.model.CallbackState("SecondFcn", "editable"), ...
    macd.model.CallbackState("UnsafeFcn", "unsupported", "Shared handler")];
actions = 0;
reloads = 0;
dialog = macd.ui.CallbackManagerDialog("Keyboard Verification", @() states, @action, @() true, true, @reload);
cleanup = onCleanup(@() deleteIfValid(dialog));
popup = findall(0, "Tag", "macd-callback-manager");
add = findall(popup, "Tag", "macd-callback-add", "UserData", "FirstFcn");
focus(add);
drawnow;
windows = matlab.internal.webwindowmanager.instance.findAllWebwindows();
owned = windows(arrayfun(@(window) string(window.Title) == "Callbacks: Keyboard Verification", windows));
assert(isscalar(owned));
robot = javaObject("java.awt.Robot");
waitForText(owned, "Add");
sendKey(owned, robot, 9);
waitForText(owned, "Delete");
sendKey(owned, robot, 10);
started = tic;
while actions == 0 && toc(started) < 10, drawnow; end
assert(actions == 1);
sendKey(owned, robot, 116);
started = tic;
while reloads == 0 && toc(started) < 10, drawnow; end
assert(reloads == 1);
evidence = struct("NativeTabNavigation", true, "NativeEnterAction", true, "NativeF5", true);
disp(evidence);

    function message = action(name, command)
        % action Record one native keyboard activation and update authoritative state.
        assert(name == "SecondFcn" && command == "Delete");
        actions = actions + 1;
        states(2) = macd.model.CallbackState("SecondFcn", "absent");
        message = "";
    end

    function reload()
        % reload Record an actual F5 forwarded by the popup keyboard handler.
        reloads = reloads + 1;
    end
end

function waitForText(window, text)
% waitForText Wait for browser keyboard focus without assuming a rendering delay.
arguments (Input)
    window
    text (1, 1) string
end
started = tic;
while toc(started) < 10
    drawnow;
    value = string(jsondecode(window.executeJS("document.activeElement.textContent.trim()")));
    if value == text, return, end
end
error("macd:CallbackKeyboard:FocusTimeout", "Expected keyboard focus on %s; actual: %s.", text, value);
end

function deleteIfValid(dialog)
% deleteIfValid Release the verification dialog without repeating destruction.
arguments (Input)
    dialog (1, 1) macd.ui.CallbackManagerDialog
end
if isvalid(dialog), delete(dialog); end
end

function sendKey(window, robot, key)
% sendKey Send one key only while the verification popup owns keyboard focus.
arguments (Input)
    window
    robot
    key (1, 1) double
end
assert(window.isFocused && window.isWindowActive, ...
    "macd:CallbackKeyboard:NotFocused", "The verification popup must own keyboard focus.");
robot.keyPress(key);
robot.keyRelease(key);
drawnow;
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
