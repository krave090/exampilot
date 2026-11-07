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
