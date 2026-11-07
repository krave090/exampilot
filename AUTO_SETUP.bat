@echo off
title ExamPilot Auto-Deploy Setup
color 0A
cd /d "%~dp0exampilot"

echo 1. Creating GitHub Workflow folder...
if not exist ".github\workflows" mkdir .github\workflows

echo 2. Creating cron_worker.php...
echo ^<?php > public\cron_worker.php
echo require __DIR__ . '/../vendor/autoload.php'; >> public\cron_worker.php
echo \ExamPilot\Config::load(dirname(__DIR__)); >> public\cron_worker.php
echo $secret = \ExamPilot\Config::get('CRON_SECRET', ''); >> public\cron_worker.php
echo if (($_GET['secret'] ?? '') !== $secret ^|^| $secret === '') { >> public\cron_worker.php
echo     http_response_code(403); >> public\cron_worker.php
echo     die('Unauthorized'); >> public\cron_worker.php
echo } >> public\cron_worker.php
echo require __DIR__ . '/../bin/worker.php'; >> public\cron_worker.php

echo 3. Creating cron_scheduler.php...
echo ^<?php > public\cron_scheduler.php
echo require __DIR__ . '/../vendor/autoload.php'; >> public\cron_scheduler.php
echo \ExamPilot\Config::load(dirname(__DIR__)); >> public\cron_scheduler.php
echo $secret = \ExamPilot\Config::get('CRON_SECRET', ''); >> public\cron_scheduler.php
echo if (($_GET['secret'] ?? '') !== $secret ^|^| $secret === '') { >> public\cron_scheduler.php
echo     http_response_code(403); >> public\cron_scheduler.php
echo     die('Unauthorized'); >> public\cron_scheduler.php
echo } >> public\cron_scheduler.php
echo require __DIR__ . '/../bin/scheduler.php'; >> public\cron_scheduler.php

echo 4. Creating migrate.php...
echo ^<?php > public\migrate.php
echo require __DIR__ . '/../vendor/autoload.php'; >> public\migrate.php
echo \ExamPilot\Config::load(dirname(__DIR__)); >> public\migrate.php
echo $secret = \ExamPilot\Config::get('CRON_SECRET', ''); >> public\migrate.php
echo if (($_GET['secret'] ?? '') !== $secret ^|^| $secret === '') { >> public\migrate.php
echo     http_response_code(403); >> public\migrate.php
echo     die('Unauthorized'); >> public\migrate.php
echo } >> public\migrate.php
echo require __DIR__ . '/../bin/migrate.php'; >> public\migrate.php

echo 5. Creating GitHub Actions cron.yml...
echo name: ExamPilot Cron Jobs > .github\workflows\cron.yml
echo on: >> .github\workflows\cron.yml
echo   schedule: >> .github\workflows\cron.yml
echo     - cron: '*/5 * * * *' >> .github\workflows\cron.yml
echo   workflow_dispatch: >> .github\workflows\cron.yml
echo. >> .github\workflows\cron.yml
echo jobs: >> .github\workflows\cron.yml
echo   run-cron: >> .github\workflows\cron.yml
echo     runs-on: ubuntu-latest >> .github\workflows\cron.yml
echo     steps: >> .github\workflows\cron.yml
echo       - name: Keep Alive >> .github\workflows\cron.yml
echo         run: curl -s --max-time 60 https://YOUR-RENDER-APP-NAME.onrender.com/health ^> /dev/null >> .github\workflows\cron.yml
echo       - name: Run Worker >> .github\workflows\cron.yml
echo         run: curl -s --max-time 60 "https://YOUR-RENDER-APP-NAME.onrender.com/cron_worker.php?secret=MySuperSecretPassword123" ^> /dev/null >> .github\workflows\cron.yml
echo       - name: Run Scheduler >> .github\workflows\cron.yml
echo         run: curl -s --max-time 60 "https://YOUR-RENDER-APP-NAME.onrender.com/cron_scheduler.php?secret=MySuperSecretPassword123" ^> /dev/null >> .github\workflows\cron.yml

echo 6. Updating .env file...
echo APP_URL=https://YOUR-RENDER-APP-NAME.onrender.com > .env
echo. >> .env
echo DB_CONNECTION=pgsql >> .env
echo DB_HOST=ep-xxxx-pooler.region.aws.neon.tech >> .env
echo DB_PORT=5432 >> .env
echo DB_DATABASE=neondb >> .env
echo DB_USERNAME=your_neon_username >> .env
echo DB_PASSWORD=your_neon_password >> .env
echo DB_SSLMODE=require >> .env
echo. >> .env
echo TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here >> .env
echo TELEGRAM_WEBHOOK_SECRET=ExamPilotSecret987 >> .env
echo. >> .env
echo AI_API_URL=https://api.groq.com/openai/v1/chat/completions >> .env
echo AI_API_KEY=your_groq_api_key_here >> .env
echo AI_MODEL=llama3-8b-8192 >> .env
echo. >> .env
echo CRON_SECRET=MySuperSecretPassword123 >> .env

echo 7. Pushing to GitHub...
git add .
git commit -m "Auto-generated Render configs and GitHub Actions"
git push

echo.
echo ====================================================
echo ✅ SUCCESS! All files created and pushed to GitHub.
echo ====================================================
pause