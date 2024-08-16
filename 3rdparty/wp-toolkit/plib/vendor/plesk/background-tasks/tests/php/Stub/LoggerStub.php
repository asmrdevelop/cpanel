<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Test\Stub;

use Psr\Log\AbstractLogger;
use Psr\Log\LoggerInterface;

class LoggerStub extends AbstractLogger implements LoggerInterface
{
    /**
     * @var string[]
     */
    public $logMessages = [];

    public function log($level, $message, array $context = array())
    {
        $this->logMessages[] = $message;
    }
}
