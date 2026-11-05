function evidence = verifyCallbackKeyboard()
% verifyCallbackKeyboard Verify native Tab, dropdown choice and F5 inside an owned visible popup.
%   Keys are sent only while this verification popup reports keyboard focus.
arguments (Output)
    evidence (1, 1) struct
end
states = [yamada.model.CallbackState("FirstFcn", "absent"), ...
    yamada.model.CallbackState("SecondFcn", "editable", "", "existing"), ...
    yamada.model.CallbackState("UnsafeFcn", "unsupported", "Shared handler")];
actions = 0;
reloads = 0;
dialog = yamada.ui.CallbackManagerDialog("Keyboard Verification", @() states, @action, @() true, true, @reload, ...
    @(~) struct("Name", "existing", "Label", "existing(app)"));
cleanup = onCleanup(@() deleteIfValid(dialog));
popup = findall(0, "Tag", "yamada-callback-manager");
control = findall(popup, "Tag", "yamada-callback-target", "UserData", "FirstFcn");
drawnow;
windows = matlab.internal.webwindowmanager.instance.findAllWebwindows();
owned = windows(arrayfun(@(window) string(window.Title) == "Callbacks: Keyboard Verification", windows));
assert(isscalar(owned));
owned.bringToFront();
titlePath = string(tempname) + ".txt";
titleCleanup = onCleanup(@() delete(titlePath));
yamada.source.SourceWriter.write(titlePath, string(popup.Name), "LF");
helper = fullfile(fileparts(mfilename("fullpath")), "focusVerificationWindow.ps1");
[status, message] = system("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ + ...
    helper + """ -TitleFile """ + titlePath + """ -OwnerProcessId " + feature("getpid"));
assert(status == 0, "yamada:CallbackKeyboard:ActivateFailed", "%s", message);
robot = javaObject("java.awt.Robot");
robot.setAutoDelay(150);
waitForText(owned, "<Disconnect>", control);
sendKey(owned, robot, 9);
waitForText(owned, "existing(app)");
test = matlab.uitest.TestCase.forInteractiveUse;
control = findall(popup, "Tag", "yamada-callback-target", "UserData", "SecondFcn");
test.choose(control, "<Disconnect>");
started = tic;
while actions == 0 && toc(started) < 10, drawnow; end
assert(actions == 1);
sendKey(owned, robot, 116);
started = tic;
while reloads == 0 && toc(started) < 10, drawnow; end
assert(reloads == 1);
evidence = struct("NativeTabNavigation", true, "NativeDropDownChoice", true, "NativeF5", true);
disp(evidence);

    function message = action(name, command, ~)
        % action Record one native keyboard activation and update authoritative state.
        assert(name == "SecondFcn" && command == "Disconnect");
        actions = actions + 1;
        states(2) = yamada.model.CallbackState("SecondFcn", "absent");
        message = "";
    end

    function reload()
        % reload Record an actual F5 forwarded by the popup keyboard handler.
        reloads = reloads + 1;
    end
end

function waitForText(window, text, initialControl)
% waitForText Wait for browser keyboard focus without assuming a rendering delay.
arguments (Input)
    window
    text (1, 1) string
    initialControl matlab.ui.control.DropDown = matlab.ui.control.DropDown.empty
end
started = tic;
requested = false;
while toc(started) < 10
    drawnow;
    if ~isempty(initialControl) && ~requested
        rendered = string(jsondecode(window.executeJS("JSON.stringify(Array.from(document.querySelectorAll('.vc-comboboxdropdown input')).map(input => input.value))")));
        rendered = string(jsondecode(rendered));
        if any(rendered == text), focus(initialControl); requested = true; end
    end
    value = string(jsondecode(window.executeJS("(document.activeElement.querySelector('input') || document.activeElement).value || document.activeElement.textContent.trim()")));
    if value == text, return, end
end
details = string(window.executeJS("JSON.stringify({tag:document.activeElement.tagName,classes:document.activeElement.className,parent:document.activeElement.parentElement.getAttribute('style')})"));
error("yamada:CallbackKeyboard:FocusTimeout", "Expected keyboard focus on %s; actual: %s. %s", text, value, details);
end

function deleteIfValid(dialog)
% deleteIfValid Release the verification dialog without repeating destruction.
arguments (Input)
    dialog (1, 1) yamada.ui.CallbackManagerDialog
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
    "yamada:CallbackKeyboard:NotFocused", "The verification popup must own keyboard focus.");
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
