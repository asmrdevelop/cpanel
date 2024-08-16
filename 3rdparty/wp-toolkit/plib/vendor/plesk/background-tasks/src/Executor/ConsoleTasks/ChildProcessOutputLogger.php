<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor\ConsoleTasks;

use Psr\Log\LoggerInterface;

class ChildProcessOutputLogger
{
    /**
     * @var string
     */
    private $buffer = '';

    /**
     * @var LoggerInterface
     */
    private $logger;

    /**
     * @var string
     */
    private $prefix;

    /**
     * @var string
     */
    private $separator;

    public function __construct(
        LoggerInterface $logger,
        string $prefix = '',
        string $separator = PHP_EOL
    ) {
        $this->logger = $logger;
        $this->prefix = $prefix;
        $this->separator = $separator;
    }

    /**
     * @return \Closure
     */
    public function onData(): callable
    {
        return function ($chunk) {
            $this->buffer .= $chunk;
            $parts = explode($this->separator, $this->buffer);
            if (count($parts) > 1) {
                $output = array_slice($parts, 0, count($parts) - 1);
                foreach ($output as $line) {
                    $this->logger->debug("{$this->prefix}{$line}");
                }
            }
            $this->buffer = end($parts);
        };
    }

    /**
     * @return \Closure
     */
    public function onEnd(): callable
    {
        return function () {
            if ($this->buffer === '') {
                return;
            }

            $this->logger->debug("{$this->prefix}{$this->buffer}");
        };
    }
}
