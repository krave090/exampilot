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
