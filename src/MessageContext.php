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
