@echo off
title ExamPilot Final Fix
color 0A
cd /d "%~dp0"

echo 1. Downloading Composer (if missing)...
if not exist composer.phar (
    powershell -Command "Invoke-WebRequest -Uri 'https://getcomposer.org/download/latest-stable/composer.phar' -OutFile 'composer.phar'"
)

echo 2. Creating a Git Bash friendly Composer...
echo #!/bin/bash > composer
echo /c/xampp/php/php.exe /c/xampp/php/composer.phar "$@" >> composer

echo 3. Running the build script...
set PATH=%~dp0;C:\xampp\php;%PATH%
"C:\Program Files\Git\bin\bash.exe" build.sh

echo.
echo ====================================================
echo ✅ DONE! You can close this window now.
echo ====================================================
pause