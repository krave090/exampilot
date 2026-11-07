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
