@echo off
cd /d "%USERPROFILE%\Desktop\exampilot"
title ExamPilot Bot Listener
:loop
C:\xampp\php\php.exe test.php
timeout /t 3 >nul
goto loop