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
