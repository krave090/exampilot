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
