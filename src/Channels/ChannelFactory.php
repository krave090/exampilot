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
