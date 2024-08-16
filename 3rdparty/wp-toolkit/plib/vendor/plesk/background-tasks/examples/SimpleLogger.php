<?php

namespace BackgroundTaskExamples;

use Psr\Log\AbstractLogger;

class SimpleLogger extends AbstractLogger
{
    /**
     * Logs with an arbitrary level.
     *
     * @param mixed $level
     * @param string $message
     * @param array $context
     *
     * @return void
     *
     * @throws \Psr\Log\InvalidArgumentException
     */
    public function log($level, $message, array $context = array())
    {
        $date = date('m/d/Y h:i:s a', time());
        $contextStr = !empty($context) ? var_export($context, true) : '';
        echo "{$date} {$level} {$message} {$contextStr}" . PHP_EOL;
    }
}
