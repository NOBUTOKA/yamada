@echo off
rem Copyright (C) 2026 Nobuto Kaitoh
rem SPDX-License-Identifier: GPL-3.0-or-later
rem This file is part of yamada. See LICENSE for the license text.

setlocal DisableDelayedExpansion
if "%~1"=="" goto usage
if "%~2"=="" goto usage
if not "%~3"=="" goto usage

pwsh.exe -NoLogo -NoProfile -File "%~dp0Complete-YamadaRelease.ps1" -Artifact "%~1" -SigningKey "%~2"
exit /b %errorlevel%

:usage
>&2 echo Usage: %~nx0 "path-to-toolbox.mltbx" "signing-key"
exit /b 2
