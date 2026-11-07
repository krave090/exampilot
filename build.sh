#!/usr/bin/env bash
set -euo pipefail

echo "🏗️  Building ExamPilot (MySQL/XAMPP default, Postgres/Neon ready)..."

if ! command -v php >/dev/null 2>&1; then
    for dir in \
        "/c/xampp/php" \
        "/opt/lampp/bin" \
        "/Applications/XAMPP/xamppfiles/bin" \
        "${PROGRAMFILES:-C:\\Program Files}/xampp/php"
    do
        if [ -d "$dir" ] && { [ -x "$dir/php" ] || [ -x "$dir/php.exe" ]; }; then
            export PATH="$dir:$PATH"
            echo "ℹ️  Found PHP at $dir (added to PATH for this session)"
            break
        fi
    done
fi

for b in php composer curl; do
  command -v "$b" >/dev/null 2>&1 || { echo "❌ $b not found in PATH"; exit 1; }
done

mkdir -p public bin src src/Channels src/Ai src/Services migrations views

lint() {
  if php -l "$1" > /dev/null 2>&1; then return 0; fi
  echo "❌ Lint failed: $1"
  php -l "$1" || true
  exit 1
}

cat > composer.json << 'EOF'
{
    "name": "exampilot/exampilot",
    "description": "ExamPilot — messaging bot for Nigerian university students",
    "type": "project",
    "license": "MIT",
    "require": {
        "php": "^8.2",
        "ext-pdo": "*",
        "guzzlehttp/guzzle": "^7.8",
        "smalot/pdfparser": "^2.10",
        "vlucas/phpdotenv": "^5.6"
    },
    "suggest": {
        "ext-pdo_mysql": "Required when DB_CONNECTION=mysql (local XAMPP)",
        "ext-pdo_pgsql": "Required when DB_CONNECTION=pgsql (production Neon)"
    },
    "autoload": {
        "psr-4": {
            "ExamPilot\\": "src/"
        }
    },
    "config": {
        "sort-packages": true
    }
}
EOF

cat > .gitignore << 'EOF'
/vendor/
.env
.DS_Store
*.log
EOF

cat > .env.example << 'EOF'
APP_URL=http://127.0.0.1:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=exampilot
DB_USERNAME=root
DB_PASSWORD=

# ─── PRODUCTION with Neon Postgres ───
# DB_CONNECTION=pgsql
# DB_HOST=ep-xxxx-yyyy.us-east-2.aws.neon.tech
# DB_PORT=5432
# DB_DATABASE=neondb
# DB_USERNAME=neondb_owner
# DB_PASSWORD=your-neon-password
# DB_SSLMODE=require

TELEGRAM_BOT_TOKEN=
TELEGRAM_WEBHOOK_SECRET=change-me-tg-secret

WHATSAPP_TOKEN=
WHATSAPP_PHONE_ID=
WHATSAPP_VERIFY_TOKEN=change-me-wa-verify
WHATSAPP_WEBHOOK_SECRET=change-me-wa-secret

PAYSTACK_SECRET_KEY=
PAYSTACK_PUBLIC_KEY=
PAYSTACK_PAYMENT_LINK=

AI_API_URL=
AI_API_KEY=
AI_MODEL=gpt-4o-mini
EOF

cat > README.md << 'EOF'
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
EOF

cat > migrations/001_init.mysql.sql << 'EOF'
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    channel_id VARCHAR(120) NOT NULL,
    name VARCHAR(120),
    plan_time VARCHAR(5) NOT NULL DEFAULT '07:30',
    tier VARCHAR(20) NOT NULL DEFAULT 'free',
    tier_expires_at DATETIME NULL,
    ai_questions_today INT NOT NULL DEFAULT 0,
    ai_questions_date DATE NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_users_channel (channel, channel_id),
    KEY idx_users_plan_time (plan_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS courses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    code VARCHAR(20) NOT NULL,
    title VARCHAR(200) NOT NULL,
    exam_date DATE NOT NULL,
    outline TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_courses_user (user_id),
    CONSTRAINT fk_courses_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS past_questions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    course_id INT NOT NULL,
    question TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_pq_course (course_id),
    CONSTRAINT fk_pq_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS messages_queue (
    id INT AUTO_INCREMENT PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    raw_json LONGTEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempts INT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME NULL,
    KEY idx_mq_status (status, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS daily_plans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    plan_date DATE NOT NULL,
    content LONGTEXT NOT NULL,
    sent_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_dp_user_date (user_id, plan_date),
    CONSTRAINT fk_dp_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS payments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    reference VARCHAR(120) NOT NULL,
    amount_kobo INT NOT NULL,
    email VARCHAR(200),
    status VARCHAR(20) NOT NULL,
    payload LONGTEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_pay_ref (reference),
    CONSTRAINT fk_pay_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS conversation_state (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    state VARCHAR(40) NULL,
    data LONGTEXT NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_cs_user (user_id),
    CONSTRAINT fk_cs_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF

cat > migrations/001_init.pgsql.sql << 'EOF'
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    channel_id VARCHAR(120) NOT NULL,
    name VARCHAR(120),
    plan_time VARCHAR(5) NOT NULL DEFAULT '07:30',
    tier VARCHAR(20) NOT NULL DEFAULT 'free',
    tier_expires_at TIMESTAMP,
    ai_questions_today INT NOT NULL DEFAULT 0,
    ai_questions_date DATE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (channel, channel_id)
);
CREATE INDEX IF NOT EXISTS idx_users_plan_time ON users(plan_time);

CREATE TABLE IF NOT EXISTS courses (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code VARCHAR(20) NOT NULL,
    title VARCHAR(200) NOT NULL,
    exam_date DATE NOT NULL,
    outline TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_courses_user ON courses(user_id);

CREATE TABLE IF NOT EXISTS past_questions (
    id SERIAL PRIMARY KEY,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages_queue (
    id SERIAL PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    raw_json TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempts INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_mq_status ON messages_queue(status, id);

CREATE TABLE IF NOT EXISTS daily_plans (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_date DATE NOT NULL,
    content TEXT NOT NULL,
    sent_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, plan_date)
);

CREATE TABLE IF NOT EXISTS payments (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE SET NULL,
    reference VARCHAR(120) NOT NULL UNIQUE,
    amount_kobo INT NOT NULL,
    email VARCHAR(200),
    status VARCHAR(20) NOT NULL,
    payload TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversation_state (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    state VARCHAR(40),
    data TEXT NOT NULL DEFAULT '{}',
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
EOF

cat > src/Config.php << 'EOF'
<?php
namespace ExamPilot;

use Dotenv\Dotenv;

final class Config
{
    private static bool $loaded = false;

    public static function load(string $baseDir): void
    {
        if (self::$loaded) {
            return;
        }
        if (is_file($baseDir . '/.env')) {
            Dotenv::createImmutable($baseDir)->safeLoad();
        }
        self::$loaded = true;
    }

    public static function get(string $key, ?string $default = null): ?string
    {
        $v = $_ENV[$key] ?? $_SERVER[$key] ?? getenv($key);
        if ($v === false || $v === null || $v === '') {
            return $default;
        }
        return (string) $v;
    }

    public static function require(string $key): string
    {
        $v = self::get($key);
        if ($v === null) {
            throw new \RuntimeException("Missing required env: {$key}");
        }
        return $v;
    }

    public static function baseDir(): string
    {
        return dirname(__DIR__);
    }
}
EOF
lint src/Config.php

cat > src/Db.php << 'EOF'
<?php
namespace ExamPilot;

use PDO;

final class Db
{
    private static ?PDO $pdo = null;

    public static function driver(): string
    {
        $d = strtolower((string) Config::get('DB_CONNECTION', 'mysql'));
        if ($d === 'postgres' || $d === 'postgresql') {
            return 'pgsql';
        }
        return $d;
    }

    public static function pdo(): PDO
    {
        if (self::$pdo !== null) {
            return self::$pdo;
        }

        $driver = self::driver();
        $dsn = Config::get('DATABASE_DSN');

        if ($dsn === null) {
            $host = Config::get('DB_HOST', '127.0.0.1');
            $port = Config::get('DB_PORT', $driver === 'pgsql' ? '5432' : '3306');
            $name = Config::get('DB_DATABASE', 'exampilot');

            if ($driver === 'pgsql') {
                $dsn = "pgsql:host={$host};port={$port};dbname={$name}";
                $ssl = Config::get('DB_SSLMODE');
                if ($ssl !== null) {
                    $dsn .= ";sslmode={$ssl}";
                }
            } else {
                $dsn = "mysql:host={$host};port={$port};dbname={$name};charset=utf8mb4";
            }
        }

        $user = Config::get('DB_USERNAME', $driver === 'pgsql' ? 'postgres' : 'root');
        $pass = Config::get('DB_PASSWORD', '');

        self::$pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        return self::$pdo;
    }
}
EOF
lint src/Db.php

cat > src/MessageContext.php << 'EOF'
<?php
namespace ExamPilot;

final class MessageContext
{
    public function __construct(
        public readonly string $channel,
        public readonly string $recipientId,
        public readonly string $text,
        public readonly ?string $callbackId = null,
        public readonly array $raw = []
    ) {
    }
}
EOF
lint src/MessageContext.php

cat > src/Channels/ChannelInterface.php << 'EOF'
<?php
namespace ExamPilot\Channels;

use ExamPilot\MessageContext;

interface ChannelInterface
{
    public function name(): string;
    public function parseUpdate(array $raw): ?MessageContext;
    public function send(string $recipientId, string $text, array $buttons = []): void;
    public function answerCallback(string $callbackId, string $text = ''): void;
}
EOF
lint src/Channels/ChannelInterface.php

cat > src/Channels/TelegramChannel.php << 'EOF'
<?php
namespace ExamPilot\Channels;

use ExamPilot\Config;
use ExamPilot\MessageContext;
use GuzzleHttp\Client;

final class TelegramChannel implements ChannelInterface
{
    private Client $http;
    private string $token;

    public function __construct(?Client $http = null)
    {
        $this->token = (string) Config::get('TELEGRAM_BOT_TOKEN', '');
        $this->http = $http ?? new Client([
            'base_uri' => 'https://api.telegram.org/',
            'timeout' => 15,
        ]);
    }

    public function name(): string { return 'telegram'; }

    public function parseUpdate(array $raw): ?MessageContext
    {
        if (isset($raw['message']) && is_array($raw['message'])) {
            $m = $raw['message'];
            $chatId = (string) ($m['chat']['id'] ?? '');
            $text = (string) ($m['text'] ?? '');
            if ($chatId === '' || $text === '') { return null; }
            return new MessageContext('telegram', $chatId, $text, null, $raw);
        }
        if (isset($raw['callback_query']) && is_array($raw['callback_query'])) {
            $cq = $raw['callback_query'];
            $chatId = (string) ($cq['message']['chat']['id'] ?? '');
            $data = (string) ($cq['data'] ?? '');
            $cbId = (string) ($cq['id'] ?? '');
            if ($chatId === '' || $data === '') { return null; }
            return new MessageContext('telegram', $chatId, $data, $cbId, $raw);
        }
        return null;
    }

    public function send(string $recipientId, string $text, array $buttons = []): void
    {
        if ($this->token === '') { return; }
        $payload = [
            'chat_id' => $recipientId,
            'text' => $text,
            'parse_mode' => 'HTML',
            'disable_web_page_preview' => true,
        ];
        if ($buttons !== []) {
            $keyboard = [];
            foreach ($buttons as $row) {
                $keyboard[] = array_map(static function ($b) {
                    return ['text' => (string) ($b['text'] ?? ''), 'callback_data' => (string) ($b['data'] ?? '')];
                }, (array) $row);
            }
            $payload['reply_markup'] = json_encode(['inline_keyboard' => $keyboard]);
        }
        $this->http->post("bot{$this->token}/sendMessage", ['json' => $payload]);
    }

    public function answerCallback(string $callbackId, string $text = ''): void
    {
        if ($this->token === '') { return; }
        $this->http->post("bot{$this->token}/answerCallbackQuery", [
            'json' => ['callback_query_id' => $callbackId, 'text' => $text],
        ]);
    }
}
EOF
lint src/Channels/TelegramChannel.php

cat > src/Channels/WhatsAppChannel.php << 'EOF'
<?php
namespace ExamPilot\Channels;

use ExamPilot\Config;
use ExamPilot\MessageContext;
use GuzzleHttp\Client;

final class WhatsAppChannel implements ChannelInterface
{
    private Client $http;
    private string $token;
    private string $phoneId;

    public function __construct(?Client $http = null)
    {
        $this->token = (string) Config::get('WHATSAPP_TOKEN', '');
        $this->phoneId = (string) Config::get('WHATSAPP_PHONE_ID', '');
        $this->http = $http ?? new Client([
            'base_uri' => 'https://graph.facebook.com/v20.0/',
            'timeout' => 15,
        ]);
    }

    public function name(): string { return 'whatsapp'; }

    public function parseUpdate(array $raw): ?MessageContext
    {
        $entry = $raw['entry'][0] ?? null;
        if (!is_array($entry)) { return null; }
        $change = $entry['changes'][0] ?? null;
        if (!is_array($change)) { return null; }
        $value = $change['value'] ?? [];
        if (!is_array($value)) { return null; }
        $msg = $value['messages'][0] ?? null;
        if (!is_array($msg)) { return null; }
        $from = (string) ($msg['from'] ?? '');
        $type = (string) ($msg['type'] ?? '');
        $text = '';
        if ($type === 'text') {
            $text = (string) ($msg['text']['body'] ?? '');
        } elseif ($type === 'interactive') {
            $text = (string) ($msg['interactive']['button_reply']['id'] ?? '');
        }
        if ($from === '' || $text === '') { return null; }
        return new MessageContext('whatsapp', $from, $text, null, $raw);
    }

    public function send(string $recipientId, string $text, array $buttons = []): void
    {
        if ($this->token === '' || $this->phoneId === '') { return; }
        $this->http->post("{$this->phoneId}/messages", [
            'headers' => ['Authorization' => "Bearer {$this->token}"],
            'json' => [
                'messaging_product' => 'whatsapp',
                'to' => $recipientId,
                'type' => 'text',
                'text' => ['body' => $text],
            ],
        ]);
    }

    public function answerCallback(string $callbackId, string $text = ''): void {}
}
EOF
lint src/Channels/WhatsAppChannel.php

cat > src/Channels/ChannelFactory.php << 'EOF'
<?php
namespace ExamPilot\Channels;

final class ChannelFactory
{
    public static function make(string $name): ChannelInterface
    {
        return match ($name) {
            'telegram' => new TelegramChannel(),
            'whatsapp' => new WhatsAppChannel(),
            default => throw new \InvalidArgumentException("Unknown channel: {$name}"),
        };
    }
}
EOF
lint src/Channels/ChannelFactory.php

cat > src/Ai/AiClient.php << 'EOF'
<?php
namespace ExamPilot\Ai;

use ExamPilot\Config;
use GuzzleHttp\Client;

final class AiClient
{
    private Client $http;

    public function __construct(?Client $http = null)
    {
        $this->http = $http ?? new Client(['timeout' => 30]);
    }

    public function answer(string $question, string $courseContext): string
    {
        $url = Config::get('AI_API_URL');
        $key = Config::get('AI_API_KEY');
        $model = Config::get('AI_MODEL', 'gpt-4o-mini');

        if ($url === null || $key === null) {
            return $this->fallback($question, $courseContext);
        }

        $system = "You are ExamPilot, a study assistant for Nigerian university students. "
            . "Answer ONLY using the provided course context when possible. Be concise (max ~200 words).\n\n"
            . "Course context:\n" . $courseContext;

        try {
            $resp = $this->http->post($url, [
                'headers' => [
                    'Authorization' => "Bearer {$key}",
                    'Content-Type' => 'application/json',
                ],
                'json' => [
                    'model' => $model,
                    'messages' => [
                        ['role' => 'system', 'content' => $system],
                        ['role' => 'user', 'content' => $question],
                    ],
                    'temperature' => 0.4,
                ],
            ]);
            $data = json_decode((string) $resp->getBody(), true);
            if (is_array($data)) {
                $text = $data['choices'][0]['message']['content'] ?? null;
                if (is_string($text) && trim($text) !== '') {
                    return trim($text);
                }
            }
            return $this->fallback($question, $courseContext);
        } catch (\Throwable $e) {
            return $this->fallback($question, $courseContext);
        }
    }

    private function fallback(string $question, string $courseContext): string
    {
        $snippet = trim($courseContext);
        if ($snippet === '') {
            $snippet = 'No course context uploaded yet.';
        } elseif (strlen($snippet) > 600) {
            $snippet = substr($snippet, 0, 600) . '...';
        }
        return "AI is not configured on this server yet. Here is what your uploads cover:\n\n" . $snippet;
    }
}
EOF
lint src/Ai/AiClient.php

cat > src/Services/PlanGenerator.php << 'EOF'
<?php
namespace ExamPilot\Services;

use ExamPilot\Ai\AiClient;

final class PlanGenerator
{
    private AiClient $ai;

    public function __construct(?AiClient $ai = null)
    {
        $this->ai = $ai ?? new AiClient();
    }

    public function generate(array $course, array $pastQuestions): string
    {
        $outline = trim((string) ($course['outline'] ?? ''));
        $title = trim(((string) ($course['code'] ?? 'Course')) . ' ' . ((string) ($course['title'] ?? '')));
        $exam = (string) ($course['exam_date'] ?? '');

        $pqBlock = '';
        if ($pastQuestions !== []) {
            $parts = [];
            foreach (array_slice($pastQuestions, 0, 5) as $pq) {
                $parts[] = '- ' . trim((string) ($pq['question'] ?? ''));
            }
            $pqBlock = "\n\nRecent past questions:\n" . implode("\n", $parts);
        }

        $prompt = "Generate today's study plan for {$title} (exam date: {$exam}).\n"
            . "Course outline:\n{$outline}{$pqBlock}\n\n"
            . "Return 2-3 topics to study today plus 2 practice questions, formatted plainly.";

        $plan = $this->ai->answer($prompt, $outline . $pqBlock);
        return "📚 {$title} — today's plan:\n\n" . trim($plan);
    }
}
EOF
lint src/Services/PlanGenerator.php

cat > src/Services/PaystackService.php << 'EOF'
<?php
namespace ExamPilot\Services;

use ExamPilot\Config;
use ExamPilot\Db;

final class PaystackService
{
    public function verifySignature(string $rawBody, string $signature): bool
    {
        $secret = (string) Config::get('PAYSTACK_SECRET_KEY', '');
        if ($secret === '' || $signature === '') { return false; }
        return hash_equals(hash_hmac('sha512', $rawBody, $secret), $signature);
    }

    public function processChargeSuccess(array $event): void
    {
        $data = $event['data'] ?? [];
        if (!is_array($data)) { return; }
        $ref = (string) ($data['reference'] ?? '');
        $amountKobo = (int) ($data['amount'] ?? 0);
        $email = (string) ($data['customer']['email'] ?? '');
        if ($ref === '') { return; }

        $pdo = Db::pdo();
        $stmt = $pdo->prepare('SELECT id FROM payments WHERE reference = :r');
        $stmt->execute([':r' => $ref]);
        if ($stmt->fetchColumn()) { return; }

        $meta = $data['metadata'] ?? [];
        $userId = is_array($meta) && isset($meta['user_id']) ? (int) $meta['user_id'] : null;

        $pdo->prepare(
            'INSERT INTO payments (user_id, reference, amount_kobo, email, status, payload, created_at)
             VALUES (:uid, :ref, :amt, :email, :status, :payload, NOW())'
        )->execute([
            ':uid' => $userId, ':ref' => $ref, ':amt' => $amountKobo,
            ':email' => $email, ':status' => 'success', ':payload' => json_encode($event),
        ]);

        if ($userId === null) { return; }

        if ($amountKobo >= 100000) { $days = 30; $tier = 'monthly'; }
        elseif ($amountKobo >= 50000) { $days = 7; $tier = 'sprint'; }
        else { return; }

        $expiresAt = date('Y-m-d H:i:s', strtotime("+{$days} days"));
        $pdo->prepare('UPDATE users SET tier = :tier, tier_expires_at = :exp WHERE id = :id')
            ->execute([':tier' => $tier, ':exp' => $expiresAt, ':id' => $userId]);
    }
}
EOF
lint src/Services/PaystackService.php

cat > src/Handlers.php << 'EOF'
<?php
namespace ExamPilot;

use ExamPilot\Ai\AiClient;
use ExamPilot\Channels\ChannelInterface;
use ExamPilot\Services\PlanGenerator;

final class Handlers
{
    public static function handle(MessageContext $ctx, ChannelInterface $channel): void
    {
        $pdo = Db::pdo();
        $user = self::getOrCreateUser($pdo, $ctx);
        $text = trim($ctx->text);

        if ($ctx->callbackId !== null) { $channel->answerCallback($ctx->callbackId, 'OK'); }

        $lower = strtolower($text);
        if (self::isCommand($text, '/start') || in_array($lower, ['hi', 'hello', 'hey'], true)) {
            self::setState($pdo, (int) $user['id'], null, []);
            $channel->send($ctx->recipientId, self::welcomeText($user));
            return;
        }
        if (self::isCommand($text, '/help')) { $channel->send($ctx->recipientId, self::helpText()); return; }
        if (self::isCommand($text, '/cancel')) {
            self::setState($pdo, (int) $user['id'], null, []);
            $channel->send($ctx->recipientId, 'Cancelled.');
            return;
        }
        if (self::isCommand($text, '/addcourse')) {
            self::setState($pdo, (int) $user['id'], 'await_course_code', []);
            $channel->send($ctx->recipientId, "What's the course code? (e.g. PHY101)\n\nSend /cancel to abort.");
            return;
        }
        if (self::isCommand($text, '/courses')) {
            $channel->send($ctx->recipientId, self::listCourses($pdo, (int) $user['id']));
            return;
        }
        if (self::isCommand($text, '/today')) {
            $channel->send($ctx->recipientId, self::generateToday($pdo, $user));
            return;
        }
        if (self::isCommand($text, '/plan')) {
            $parts = preg_split('/\s+/', $text) ?: [];
            $time = (string) ($parts[1] ?? '');
            if (!preg_match('/^\d{2}:\d{2}$/', $time)) {
                $channel->send($ctx->recipientId, 'Usage: /plan HH:MM  (e.g. /plan 07:30)');
                return;
            }
            $pdo->prepare('UPDATE users SET plan_time = :t WHERE id = :id')->execute([':t' => $time, ':id' => $user['id']]);
            $channel->send($ctx->recipientId, "Got it. Daily plan at {$time}.");
            return;
        }
        if (self::isCommand($text, '/upgrade')) { $channel->send($ctx->recipientId, self::upgradeText()); return; }

        $state = self::getState($pdo, (int) $user['id']);
        if ($state['state'] !== null) {
            self::handleState($pdo, $user, $state, $text, $channel, $ctx);
            return;
        }
        self::handleQuestion($pdo, $user, $text, $channel, $ctx);
    }

    private static function isCommand(string $text, string $cmd): bool
    {
        $parts = preg_split('/\s+/', trim($text)) ?: [];
        return strcasecmp((string) ($parts[0] ?? ''), $cmd) === 0;
    }

    private static function getOrCreateUser(\PDO $pdo, MessageContext $ctx): array
    {
        $stmt = $pdo->prepare('SELECT * FROM users WHERE channel = :ch AND channel_id = :cid LIMIT 1');
        $stmt->execute([':ch' => $ctx->channel, ':cid' => $ctx->recipientId]);
        $user = $stmt->fetch();
        if (is_array($user)) { return $user; }
        $pdo->prepare(
            'INSERT INTO users (channel, channel_id, plan_time, tier, ai_questions_today, ai_questions_date, created_at)
             VALUES (:ch, :cid, :pt, :tier, 0, :d, NOW())'
        )->execute([':ch' => $ctx->channel, ':cid' => $ctx->recipientId, ':pt' => '07:30', ':tier' => 'free', ':d' => date('Y-m-d')]);
        $stmt->execute([':ch' => $ctx->channel, ':cid' => $ctx->recipientId]);
        return (array) $stmt->fetch();
    }

    private static function getState(\PDO $pdo, int $userId): array
    {
        $stmt = $pdo->prepare('SELECT state, data FROM conversation_state WHERE user_id = :id');
        $stmt->execute([':id' => $userId]);
        $row = $stmt->fetch();
        if (!is_array($row)) { return ['state' => null, 'data' => []]; }
        $decoded = json_decode((string) $row['data'], true);
        return ['state' => $row['state'] !== null ? (string) $row['state'] : null, 'data' => is_array($decoded) ? $decoded : []];
    }

    private static function setState(\PDO $pdo, int $userId, ?string $state, array $data): void
    {
        $existing = $pdo->prepare('SELECT id FROM conversation_state WHERE user_id = :id');
        $existing->execute([':id' => $userId]);
        if ($existing->fetchColumn()) {
            $pdo->prepare('UPDATE conversation_state SET state = :s, data = :d, updated_at = NOW() WHERE user_id = :id')
                ->execute([':s' => $state, ':d' => json_encode($data), ':id' => $userId]);
        } else {
            $pdo->prepare('INSERT INTO conversation_state (user_id, state, data, updated_at) VALUES (:id, :s, :d, NOW())')
                ->execute([':id' => $userId, ':s' => $state, ':d' => json_encode($data)]);
        }
    }

    private static function handleState(\PDO $pdo, array $user, array $state, string $text, ChannelInterface $channel, MessageContext $ctx): void
    {
        $data = $state['data'];
        switch ($state['state']) {
            case 'await_course_code':
                $code = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $text) ?? '');
                if ($code === '') { $channel->send($ctx->recipientId, 'Send a code like PHY101.'); return; }
                $data['code'] = $code;
                self::setState($pdo, (int) $user['id'], 'await_course_title', $data);
                $channel->send($ctx->recipientId, "Title for {$code}? (e.g. General Physics)");
                return;
            case 'await_course_title':
                if ($text === '') { $channel->send($ctx->recipientId, 'Send the course title.'); return; }
                $data['title'] = $text;
                self::setState($pdo, (int) $user['id'], 'await_exam_date', $data);
                $channel->send($ctx->recipientId, 'Exam date? (YYYY-MM-DD)');
                return;
            case 'await_exam_date':
                if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $text)) { $channel->send($ctx->recipientId, 'Please use YYYY-MM-DD format.'); return; }
                $data['exam_date'] = $text;
                self::setState($pdo, (int) $user['id'], 'await_outline', $data);
                $channel->send($ctx->recipientId, "Paste the course outline, or send 'skip'.");
                return;
            case 'await_outline':
                $data['outline'] = strtolower($text) === 'skip' ? '' : $text;
                self::setState($pdo, (int) $user['id'], 'await_past_questions', $data);
                $channel->send($ctx->recipientId, "Paste past questions (one per line), or send 'skip'.");
                return;
            case 'await_past_questions':
                $pqText = strtolower($text) === 'skip' ? '' : $text;
                $pdo->prepare(
                    'INSERT INTO courses (user_id, code, title, exam_date, outline, created_at)
                     VALUES (:uid, :code, :title, :exam, :outline, NOW())'
                )->execute([
                    ':uid' => $user['id'], ':code' => (string) ($data['code'] ?? ''),
                    ':title' => (string) ($data['title'] ?? ''),
                    ':exam' => (string) ($data['exam_date'] ?? date('Y-m-d')),
                    ':outline' => (string) ($data['outline'] ?? ''),
                ]);
                $courseId = (int) $pdo->lastInsertId();
                if ($pqText !== '') {
                    $lines = preg_split('/\r?\n/', $pqText) ?: [];
                    $ins = $pdo->prepare('INSERT INTO past_questions (course_id, question, created_at) VALUES (:cid, :q, NOW())');
                    foreach ($lines as $line) {
                        $line = trim($line);
                        if ($line === '') { continue; }
                        $ins->execute([':cid' => $courseId, ':q' => $line]);
                    }
                }
                self::setState($pdo, (int) $user['id'], null, []);
                $code = (string) ($data['code'] ?? '');
                $title = (string) ($data['title'] ?? '');
                $channel->send($ctx->recipientId, "✅ Course added: {$code} {$title}\n\nSend another with /addcourse, or ask me any question.");
                return;
        }
        self::setState($pdo, (int) $user['id'], null, []);
    }

    private static function handleQuestion(\PDO $pdo, array $user, string $text, ChannelInterface $channel, MessageContext $ctx): void
    {
        if ($text === '') { return; }
        $stmt = $pdo->prepare('SELECT * FROM courses WHERE user_id = :uid ORDER BY id ASC');
        $stmt->execute([':uid' => $user['id']]);
        $courses = $stmt->fetchAll();
        if (!is_array($courses) || $courses === []) {
            $channel->send($ctx->recipientId, 'You have no courses yet. Add one with /addcourse.');
            return;
        }
        $parts = preg_split('/\s+/', $text) ?: [];
        $firstToken = strtoupper((string) ($parts[0] ?? ''));
        $chosen = $courses[0];
        foreach ($courses as $c) {
            if (strcasecmp((string) $c['code'], $firstToken) === 0) { $chosen = $c; break; }
        }
        $tier = (string) $user['tier'];
        $expires = $user['tier_expires_at'];
        $isPaid = ($tier === 'sprint' || $tier === 'monthly') && ($expires === null || strtotime((string) $expires) >= time());
        if (!$isPaid && ($tier === 'sprint' || $tier === 'monthly')) {
            $pdo->prepare("UPDATE users SET tier = 'free' WHERE id = :id")->execute([':id' => $user['id']]);
            $tier = 'free';
        }
        if ($tier === 'free') {
            $today = date('Y-m-d');
            $used = (int) $user['ai_questions_today'];
            if ((string) $user['ai_questions_date'] !== $today) { $used = 0; }
            if ($used >= 5) {
                $channel->send($ctx->recipientId, "You've used all 5 free AI questions today. Upgrade: /upgrade");
                return;
            }
            $used++;
            $pdo->prepare('UPDATE users SET ai_questions_today = :n, ai_questions_date = :d WHERE id = :id')
                ->execute([':n' => $used, ':d' => $today, ':id' => $user['id']]);
        }
        $context = trim((string) $chosen['outline']);
        $pqStmt = $pdo->prepare('SELECT question FROM past_questions WHERE course_id = :cid LIMIT 10');
        $pqStmt->execute([':cid' => $chosen['id']]);
        $pqs = $pqStmt->fetchAll(\PDO::FETCH_COLUMN) ?: [];
        if ($pqs !== []) { $context .= "\n\nPast questions:\n- " . implode("\n- ", array_map('strval', $pqs)); }
        if ($context === '') { $context = 'Course: ' . $chosen['code'] . ' ' . $chosen['title']; }
        $answer = (new AiClient())->answer($text, $context);
        $channel->send($ctx->recipientId, $answer);
    }

    private static function welcomeText(array $user): string
    {
        return "👋 Welcome to ExamPilot!\n\n"
            . "Commands:\n"
            . "• /addcourse — add a course\n"
            . "• /courses — list courses\n"
            . "• /today — generate today's plan\n"
            . "• /plan HH:MM — set daily time (currently " . (string) $user['plan_time'] . ")\n"
            . "• /upgrade — paid plans\n"
            . "• /help — help\n\n"
            . "Free: 5 AI questions/day.";
    }

    private static function helpText(): string
    {
        return "ExamPilot help:\n\n/start /addcourse /courses /today /plan HH:MM /upgrade /cancel\n\nOr just type a question.";
    }

    private static function listCourses(\PDO $pdo, int $userId): string
    {
        $stmt = $pdo->prepare('SELECT code, title, exam_date FROM courses WHERE user_id = :uid ORDER BY exam_date ASC, id ASC');
        $stmt->execute([':uid' => $userId]);
        $rows = $stmt->fetchAll();
        if (!is_array($rows) || $rows === []) { return 'No courses yet. Add one with /addcourse.'; }
        $lines = ['📚 Your courses:'];
        foreach ($rows as $r) { $lines[] = "• {$r['code']} — {$r['title']} (exam: {$r['exam_date']})"; }
        return implode("\n", $lines);
    }

    private static function generateToday(\PDO $pdo, array $user): string
    {
        $stmt = $pdo->prepare('SELECT * FROM courses WHERE user_id = :uid ORDER BY id ASC');
        $stmt->execute([':uid' => $user['id']]);
        $courses = $stmt->fetchAll();
        if (!is_array($courses) || $courses === []) { return 'No courses yet. Add one with /addcourse.'; }
        $gen = new PlanGenerator();
        $chunks = [];
        foreach ($courses as $c) {
            $pq = $pdo->prepare('SELECT question FROM past_questions WHERE course_id = :cid');
            $pq->execute([':cid' => $c['id']]);
            $pqs = $pq->fetchAll();
            $chunks[] = $gen->generate($c, is_array($pqs) ? $pqs : []);
        }
        return "☀️ Here's your plan for today:\n\n" . implode("\n\n---\n\n", $chunks);
    }

    private static function upgradeText(): string
    {
        $link = (string) Config::get('PAYSTACK_PAYMENT_LINK', '');
        $lines = ['💳 Upgrade ExamPilot:', '', '• ₦500 — 7-day Exam Sprint', '• ₦1,000 — 30-day Monthly', ''];
        if ($link !== '') { $lines[] = "Pay here: {$link}"; }
        else { $lines[] = 'Set PAYSTACK_PAYMENT_LINK in .env.'; }
        return implode("\n", $lines);
    }
}
EOF
lint src/Handlers.php

cat > public/index.php << 'EOF'
<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Config;
use ExamPilot\Db;
use ExamPilot\Services\PaystackService;
Config::load(dirname(__DIR__));
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$uri = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH) ?: '/';
$json = static function (int $code, array $body): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($body);
    exit;
};
if ($uri === '/health') { $json(200, ['status' => 'ok']); }
if ($uri === '/' && $method === 'GET') {
    header('Content-Type: text/html; charset=utf-8');
    require __DIR__ . '/../views/landing.php';
    exit;
}
if ($method === 'POST' && preg_match('#^/webhook/telegram/([^/]+)$#', $uri, $m) === 1) {
    $expected = (string) Config::get('TELEGRAM_WEBHOOK_SECRET', '');
    if ($expected === '' || !hash_equals($expected, $m[1])) { $json(403, ['error' => 'forbidden']); }
    $raw = (string) file_get_contents('php://input');
    if ($raw === '') { $json(200, ['ok' => true]); }
    Db::pdo()->prepare("INSERT INTO messages_queue (channel, raw_json, status, created_at) VALUES ('telegram', :r, 'pending', NOW())")->execute([':r' => $raw]);
    $json(200, ['ok' => true]);
}
if ($method === 'GET' && preg_match('#^/webhook/whatsapp/([^/]+)$#', $uri, $m) === 1) {
    $expected = (string) Config::get('WHATSAPP_WEBHOOK_SECRET', '');
    if ($expected === '' || !hash_equals($expected, $m[1])) { $json(403, ['error' => 'forbidden']); }
    $mode = (string) ($_GET['hub_mode'] ?? ($_GET['hub.mode'] ?? ''));
    $token = (string) ($_GET['hub_verify_token'] ?? ($_GET['hub.verify_token'] ?? ''));
    $challenge = (string) ($_GET['hub_challenge'] ?? ($_GET['hub.challenge'] ?? ''));
    if ($mode === 'subscribe' && $token !== '' && hash_equals((string) Config::get('WHATSAPP_VERIFY_TOKEN', ''), $token)) {
        http_response_code(200); header('Content-Type: text/plain'); echo $challenge; exit;
    }
    $json(403, ['error' => 'verify failed']);
}
if ($method === 'POST' && preg_match('#^/webhook/whatsapp/([^/]+)$#', $uri, $m) === 1) {
    $expected = (string) Config::get('WHATSAPP_WEBHOOK_SECRET', '');
    if ($expected === '' || !hash_equals($expected, $m[1])) { $json(403, ['error' => 'forbidden']); }
    $raw = (string) file_get_contents('php://input');
    if ($raw === '') { $json(200, ['ok' => true]); }
    Db::pdo()->prepare("INSERT INTO messages_queue (channel, raw_json, status, created_at) VALUES ('whatsapp', :r, 'pending', NOW())")->execute([':r' => $raw]);
    $json(200, ['ok' => true]);
}
if ($method === 'POST' && $uri === '/paystack/webhook') {
    $raw = (string) file_get_contents('php://input');
    $sig = (string) ($_SERVER['HTTP_X_PAYSTACK_SIGNATURE'] ?? '');
    $svc = new PaystackService();
    if (!$svc->verifySignature($raw, $sig)) { $json(403, ['error' => 'invalid signature']); }
    $event = json_decode($raw, true);
    if (is_array($event) && ($event['event'] ?? '') === 'charge.success') {
        try { $svc->processChargeSuccess($event); } catch (\Throwable $e) { error_log('Paystack: ' . $e->getMessage()); }
    }
    $json(200, ['ok' => true]);
}
http_response_code(404); header('Content-Type: text/plain'); echo 'Not found';
EOF
lint public/index.php

cat > public/router.php << 'EOF'
<?php
$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$file = __DIR__ . $uri;
if ($uri !== '/' && is_file($file)) { return false; }
require __DIR__ . '/index.php';
EOF
lint public/router.php

cat > public/.htaccess << 'EOF'
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [QSA,L]
EOF

cat > views/landing.php << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>ExamPilot — AI study coach for Nigerian students</title>
<style>
:root{--accent:#0ea5e9;--bg:#0b1220;--card:#111c30;--text:#e5e7eb;--muted:#94a3b8}
*{box-sizing:border-box}
body{margin:0;font-family:system-ui,-apple-system,sans-serif;background:linear-gradient(180deg,var(--bg),#0a0f1a);color:var(--text);line-height:1.6}
.container{max-width:960px;margin:0 auto;padding:64px 24px}
h1{font-size:44px;line-height:1.15;margin:0 0 16px;font-weight:800}
.tag{color:var(--accent);text-transform:uppercase;letter-spacing:2px;font-size:13px;font-weight:700}
p.lede{font-size:20px;color:var(--muted);max-width:640px;margin:0}
.cta{display:inline-block;margin-top:24px;padding:14px 22px;background:var(--accent);color:#001224;font-weight:700;border-radius:10px;text-decoration:none}
.grid{display:grid;gap:20px;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));margin-top:56px}
.card{background:var(--card);border:1px solid #1f2d4a;padding:20px;border-radius:12px}
.card h3{margin:0 0 8px;font-size:18px}
.card p{margin:0;color:var(--muted);font-size:15px}
footer{margin-top:64px;color:var(--muted);font-size:14px}
</style>
</head>
<body>
<main class="container">
<div class="tag">ExamPilot</div>
<h1>Your AI study coach for Nigerian university students.</h1>
<p class="lede">Add your courses, exam dates, outlines and past questions in a chat. Every morning ExamPilot sends you a personalized study plan — inside Telegram (and WhatsApp).</p>
<a class="cta" href="https://t.me/">Start on Telegram →</a>
<div class="grid">
<div class="card"><h3>📅 Daily plan</h3><p>2–3 topics + practice questions, sent at your preferred time.</p></div>
<div class="card"><h3>🧠 AI answers</h3><p>Ask anything about your course — grounded in your uploads.</p></div>
<div class="card"><h3>🎯 Past questions</h3><p>Upload past questions and get practice prompts.</p></div>
<div class="card"><h3>💳 Pricing</h3><p>Free: 5 AI questions/day. ₦500 Sprint. ₦1,000 Monthly.</p></div>
</div>
<footer>© ExamPilot. Built for students who refuse to cram.</footer>
</main>
</body>
</html>
EOF
lint views/landing.php

cat > bin/migrate.php << 'EOF'
<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Config;
use ExamPilot\Db;
Config::load(dirname(__DIR__));
$driver = Db::driver();
if (!in_array($driver, \PDO::getAvailableDrivers(), true)) {
    fwrite(STDERR, "❌ PDO driver '{$driver}' not available.\n");
    fwrite(STDERR, "   Installed: " . implode(', ', \PDO::getAvailableDrivers()) . "\n");
    exit(1);
}
try {
    $pdo = Db::pdo();
} catch (\PDOException $e) {
    $msg = $e->getMessage();
    if ($driver === 'mysql' && stripos($msg, 'Unknown database') !== false) {
        echo "ℹ️  Database not found — creating it...\n";
        $host = Config::get('DB_HOST', '127.0.0.1');
        $port = Config::get('DB_PORT', '3306');
        $name = (string) Config::get('DB_DATABASE', 'exampilot');
        $user = Config::get('DB_USERNAME', 'root');
        $pass = Config::get('DB_PASSWORD', '');
        $safe = str_replace('`', '', $name);
        $sys = new \PDO("mysql:host={$host};port={$port}", $user, $pass, [\PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION]);
        $sys->exec("CREATE DATABASE `{$safe}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
        echo "✅ Database '{$name}' created\n";
        $pdo = Db::pdo();
    } else {
        fwrite(STDERR, "❌ Connection failed: {$msg}\n");
        exit(1);
    }
}
$sqlFile = dirname(__DIR__) . "/migrations/001_init.{$driver}.sql";
if (!is_file($sqlFile)) { fwrite(STDERR, "❌ Missing: {$sqlFile}\n"); exit(1); }
$sql = (string) file_get_contents($sqlFile);
$statements = preg_split('/;\s*$/m', $sql) ?: [];
$ran = 0;
foreach ($statements as $stmt) {
    $stmt = trim($stmt);
    if ($stmt === '') { continue; }
    try { $pdo->exec($stmt); $ran++; }
    catch (\PDOException $e) {
        fwrite(STDERR, "❌ Migration error #{$ran}: " . $e->getMessage() . "\n");
        exit(1);
    }
}
echo "✅ Migrations applied ({$driver}, {$ran} statements)\n";
EOF
lint bin/migrate.php

cat > bin/worker.php << 'EOF'
<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Channels\ChannelFactory;
use ExamPilot\Config;
use ExamPilot\Db;
use ExamPilot\Handlers;
Config::load(dirname(__DIR__));
set_time_limit(50);
$pdo = Db::pdo();
$stmt = $pdo->prepare("SELECT id, channel, raw_json FROM messages_queue WHERE status = 'pending' ORDER BY id ASC LIMIT 20");
$stmt->execute();
$rows = $stmt->fetchAll();
$processed = 0; $failed = 0;
foreach ($rows as $row) {
    try {
        $raw = json_decode((string) $row['raw_json'], true);
        if (!is_array($raw)) {
            $pdo->prepare("UPDATE messages_queue SET status='failed', attempts=attempts+1, processed_at=NOW() WHERE id=:id")->execute([':id' => $row['id']]);
            $failed++; continue;
        }
        $channel = ChannelFactory::make((string) $row['channel']);
        $ctx = $channel->parseUpdate($raw);
        if ($ctx !== null) { Handlers::handle($ctx, $channel); }
        $pdo->prepare("UPDATE messages_queue SET status='done', attempts=attempts+1, processed_at=NOW() WHERE id=:id")->execute([':id' => $row['id']]);
        $processed++;
    } catch (\Throwable $e) {
        error_log('Worker: ' . $e->getMessage());
        $pdo->prepare("UPDATE messages_queue SET status='failed', attempts=attempts+1, processed_at=NOW() WHERE id=:id")->execute([':id' => $row['id']]);
        $failed++;
    }
}
echo "Worker: processed={$processed} failed={$failed}\n";
EOF
lint bin/worker.php

cat > bin/scheduler.php << 'EOF'
<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Channels\ChannelFactory;
use ExamPilot\Config;
use ExamPilot\Db;
use ExamPilot\Services\PlanGenerator;
Config::load(dirname(__DIR__));
set_time_limit(50);
$pdo = Db::pdo();
$now = date('H:i'); $today = date('Y-m-d');
$stmt = $pdo->prepare('SELECT * FROM users WHERE plan_time = :t');
$stmt->execute([':t' => $now]);
$users = $stmt->fetchAll();
$gen = new PlanGenerator(); $sent = 0;
foreach ($users as $user) {
    try {
        $check = $pdo->prepare('SELECT id FROM daily_plans WHERE user_id=:uid AND plan_date=:d');
        $check->execute([':uid' => $user['id'], ':d' => $today]);
        if ($check->fetchColumn()) { continue; }
        $cStmt = $pdo->prepare('SELECT * FROM courses WHERE user_id=:uid ORDER BY id ASC');
        $cStmt->execute([':uid' => $user['id']]);
        $courses = $cStmt->fetchAll();
        if (!is_array($courses) || $courses === []) { continue; }
        $chunks = [];
        foreach ($courses as $course) {
            $pq = $pdo->prepare('SELECT question FROM past_questions WHERE course_id=:cid');
            $pq->execute([':cid' => $course['id']]);
            $pqs = $pq->fetchAll();
            $chunks[] = $gen->generate($course, is_array($pqs) ? $pqs : []);
        }
        $body = "☀️ Good morning! Your plan for today:\n\n" . implode("\n\n---\n\n", $chunks);
        try {
            $pdo->prepare('INSERT INTO daily_plans (user_id, plan_date, content, sent_at, created_at) VALUES (:uid,:d,:c,NOW(),NOW())')
                ->execute([':uid' => $user['id'], ':d' => $today, ':c' => $body]);
        } catch (\PDOException $e) { continue; }
        ChannelFactory::make((string) $user['channel'])->send((string) $user['channel_id'], $body);
        $sent++;
    } catch (\Throwable $e) { error_log('Scheduler: ' . $e->getMessage()); }
}
echo "Scheduler: sent={$sent} (tick {$now}, driver=" . Db::driver() . ")\n";
EOF
lint bin/scheduler.php

cat > bin/set_telegram_webhook.php << 'EOF'
<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Config;
use GuzzleHttp\Client;
Config::load(dirname(__DIR__));
$token = Config::get('TELEGRAM_BOT_TOKEN');
$secret = Config::get('TELEGRAM_WEBHOOK_SECRET');
$base = Config::get('APP_URL');
if ($token === null || $secret === null || $base === null) {
    fwrite(STDERR, "Set TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET and APP_URL in .env first.\n");
    exit(1);
}
$url = rtrim($base, '/') . "/webhook/telegram/{$secret}";
try {
    $resp = (new Client(['base_uri' => 'https://api.telegram.org/', 'timeout' => 15]))
        ->post("bot{$token}/setWebhook", ['json' => ['url' => $url]]);
    echo (string) $resp->getBody() . "\n";
} catch (\Throwable $e) {
    fwrite(STDERR, '❌ Failed: ' . $e->getMessage() . "\n");
    exit(1);
}
EOF
lint bin/set_telegram_webhook.php

echo "📦 Installing composer dependencies..."
composer install --no-dev --no-interaction --no-progress

if [ ! -f .env ]; then
    cp .env.example .env
    echo "⚠️  .env was missing — copied from .env.example"
fi

echo "🗄️  Running migrations..."
php bin/migrate.php

echo "🚀 Booting built-in server for verification..."
php -S 127.0.0.1:8000 -t public public/router.php > /tmp/exampilot_server.log 2>&1 &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 2

HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health || true)
ROOT=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/ || true)
cleanup
trap - EXIT

if [ "$HEALTH" != "200" ] || [ "$ROOT" != "200" ]; then
    echo "❌ Boot check failed: /health=$HEALTH  /=$ROOT"
    cat /tmp/exampilot_server.log || true
    exit 1
fi

echo "✅ ExamPilot built. Next: edit .env, then run php bin/set_telegram_webhook.php"