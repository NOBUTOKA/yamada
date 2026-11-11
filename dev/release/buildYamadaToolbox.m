function artifacts = buildYamadaToolbox(outputFolder)
% buildYamadaToolbox Build a Toolbox candidate, source manifest, and SHA-256 list.
%   Add dev/release to the path before calling this developer-only function.
%   Existing outputs are not replaced, so signed or reviewed files remain fixed.
arguments (Input)
    outputFolder (1, 1) string = ""
end
arguments (Output)
    artifacts (1, 1) struct
end

% Capture the exact checkout and selected input content before packaging.
projectRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
assert(ispc && version("-release") == "2024a", ...
    "yamada:Release:UnsupportedBuildHost", "Build with MATLAB R2024a on Windows.");
[files, metadata] = yamadaToolboxFiles(projectRoot);
if outputFolder == ""
    outputFolder = fullfile(projectRoot, "build", metadata.version);
end
if ~System.IO.Path.IsPathRooted(outputFolder)
    outputFolder = fullfile(string(pwd), outputFolder);
end
outputFolder = string(System.IO.Path.GetFullPath(char(outputFolder)));
artifacts = struct("toolbox", fullfile(outputFolder, "yamada-" + metadata.version + ".mltbx"), ...
    "manifest", fullfile(outputFolder, "build-manifest.json"), ...
    "checksums", fullfile(outputFolder, "SHA256SUMS"));
for path = string(struct2cell(artifacts))'
    assert(~isfile(path) && ~isfolder(path), "yamada:Release:OutputExists", ...
        "Use a new output folder; refusing to replace %s.", path);
end
manifest = struct("name", metadata.name, "version", metadata.version, ...
    "identifier", metadata.identifier, "sourceCommit", gitOutput(projectRoot, "rev-parse HEAD"), ...
    "sourceDirty", gitOutput(projectRoot, "status --porcelain") ~= "", ...
    "configurationSha256", sha256(fullfile(projectRoot, "dev", "release", "toolbox.json")), ...
    "matlabVersion", string(version), "platform", string(computer), "files", inputManifest(files, projectRoot));

% Package explicit inputs and reject changes made while the package was built.
if ~isfolder(outputFolder), mkdir(outputFolder); end
payload = string(tempname(outputFolder));
mkdir(payload);
payloadCleanup = onCleanup(@() rmdir(payload, "s"));
for filePath = files'
    relative = extractAfter(filePath, strlength(projectRoot) + 1);
    destination = fullfile(payload, relative);
    folder = fileparts(destination);
    if ~isfolder(folder), mkdir(folder); end
    copyfile(filePath, destination);
end
fprintf("TOOLBOX_PAYLOAD Files=%d\n", numel(files));
options = yamadaToolboxOptions(projectRoot, payload);
fprintf("TOOLBOX_OPTIONS_READY\n");
options.OutputFile = artifacts.toolbox;
matlab.addons.toolbox.packageToolbox(options);
assert(isequal(manifest.files, inputManifest(files, projectRoot)) && ...
    manifest.configurationSha256 == sha256(fullfile(projectRoot, "dev", "release", "toolbox.json")) && ...
    manifest.sourceCommit == gitOutput(projectRoot, "rev-parse HEAD") && ...
    manifest.sourceDirty == (gitOutput(projectRoot, "status --porcelain") ~= ""), ...
    "yamada:Release:InputsChanged", "Build inputs changed; discard this candidate and rebuild.");
manifest.toolboxSha256 = sha256(artifacts.toolbox);
writeUtf8(artifacts.manifest, string(jsonencode(manifest, PrettyPrint=true)) + newline);
[~, name, extension] = fileparts(artifacts.toolbox);
writeUtf8(artifacts.checksums, manifest.toolboxSha256 + "  " + name + extension + newline);
fprintf("TOOLBOX_BUILD File=%s SHA256=%s Source=%s Dirty=%d\n", ...
    artifacts.toolbox, manifest.toolboxSha256, manifest.sourceCommit, manifest.sourceDirty);
end

function entries = inputManifest(files, projectRoot)
% inputManifest Capture relative names and byte hashes for all selected files.
arguments (Input)
    files (:, 1) string
    projectRoot (1, 1) string
end
arguments (Output)
    entries (:, 1) struct
end
files = sort(files);
entries = repmat(struct("path", "", "sha256", ""), numel(files), 1);
for index = 1:numel(files)
    entries(index).path = replace(extractAfter(files(index), strlength(projectRoot) + 1), "\", "/");
    entries(index).sha256 = sha256(files(index));
end
end

function result = gitOutput(projectRoot, command)
% gitOutput Require Git to identify candidate source without changing the checkout.
arguments (Input)
    projectRoot (1, 1) string
    command (1, 1) string
end
arguments (Output)
    result (1, 1) string
end
[status, output] = system("git -C """ + projectRoot + """ " + command);
assert(status == 0, "yamada:Release:GitFailed", "Could not identify source: %s", output);
result = strip(string(output));
end

function result = sha256(filePath)
% sha256 Hash exact file bytes using MATLAB's installed Java runtime.
arguments (Input)
    filePath (1, 1) string
end
arguments (Output)
    result (1, 1) string
end
[fileId, message] = fopen(filePath, "rb");
assert(fileId >= 0, "yamada:Release:ReadFailed", "%s", message);
cleanup = onCleanup(@() fclose(fileId));
digest = java.security.MessageDigest.getInstance("SHA-256");
while ~feof(fileId)
    bytes = fread(fileId, 1024 * 1024, "*uint8");
    digest.update(typecast(bytes, "int8"));
end
[message, number] = ferror(fileId);
assert(number == 0, "yamada:Release:ReadFailed", "%s", message);
result = lower(string(reshape(dec2hex(typecast(digest.digest(), "uint8"), 2)', 1, [])));
end

function writeUtf8(filePath, text)
% writeUtf8 Write developer output and check both write and close results.
arguments (Input)
    filePath (1, 1) string
    text (1, 1) string
end
[fileId, message] = fopen(filePath, "wb");
assert(fileId >= 0, "yamada:Release:WriteFailed", "%s", message);
cleanup = onCleanup(@() closeIfOpen(fileId));
bytes = unicode2native(char(text), "UTF-8");
count = fwrite(fileId, bytes, "uint8");
assert(count == numel(bytes), "yamada:Release:WriteFailed", "Incomplete output write.");
status = fclose(fileId);
clear cleanup
assert(status == 0, "yamada:Release:CloseFailed", "Could not close output.");
end

function closeIfOpen(fileId)
% closeIfOpen Release a failed output stream without closing it twice.
arguments (Input)
    fileId (1, 1) double
end
try
    fclose(fileId);
catch
    % The explicit close may already have released this stream.
end
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
