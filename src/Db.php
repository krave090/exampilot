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
