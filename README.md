# ExamPilot

Messaging-first study coach for Nigerian university students.

## Database

Set `DB_CONNECTION=mysql` for local XAMPP, or `DB_CONNECTION=pgsql` for Neon.
Run `php bin/migrate.php` after editing `.env`.

## Cron

    * * * * * php /path/exampilot/bin/worker.php
    * * * * * php /path/exampilot/bin/scheduler.php

## Local test

    php -S 127.0.0.1:8000 -t public public/router.php
