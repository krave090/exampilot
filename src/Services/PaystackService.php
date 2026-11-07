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
