<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

class MemoryLogger
{
    /**
     * @var float
     */
    private $startTime;

    /**
     * @var string[]
     */
    private $messages;

    /**
     * @var MemoryLogger
     */
    private static $instance;

    public static function getInstance(): MemoryLogger
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function start(): void
    {
        $this->startTime = microtime(true);
    }

    public function log(string $message): void
    {
        $time = round((microtime(true) - $this->startTime) * 1000);
        $this->messages[] = "[{$time} ms] {$message}";
    }

    public function getMessages(): array
    {
        return $this->messages;
    }
}
