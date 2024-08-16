<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Test\Suite;

use BackgroundTasks\Executor\ConsoleTasks\ChildProcessOutputLogger;
use BackgroundTasks\Test\Stub\LoggerStub;
use PHPUnit\Framework\TestCase;

class ChildProcessOutputLoggerTest extends TestCase
{
    /**
     * @var string
     */
    private $separator = PHP_EOL;

    /**
     * @param array $chunks
     * @param array $expectedLogMessages
     * @dataProvider dataCriticalCases
     * @throws \Exception
     */
    public function testCriticalCases(array $chunks, array $expectedLogMessages)
    {
        $loggerStub = new LoggerStub();
        $childProcessOutputLogger = new ChildProcessOutputLogger($loggerStub, '', $this->separator);

        foreach ($chunks as $chunk) {
            $childProcessOutputLogger->onData()($chunk);
        }
        $childProcessOutputLogger->onEnd()();

        $this->assertEquals($expectedLogMessages, $loggerStub->logMessages);
    }

    public function dataCriticalCases()
    {
        return [
            [
                [],
                [],
            ],
            [
                ['line1'],
                ['line1'],
            ],
            [
                ['line1', '-postfix'],
                ['line1-postfix'],
            ],
            [
                ["line1{$this->separator}line2"],
                ['line1', 'line2'],
            ],
            [
                ["line1{$this->separator}line2", "-postfix"],
                ['line1', 'line2-postfix'],
            ],
            [
                ['lin', "e1{$this->separator}lin", 'e2'],
                ['line1', 'line2'],
            ],
            [
                ['lin', "e1{$this->separator}line2{$this->separator}lin", 'e3', '-postfix'],
                ['line1', 'line2', 'line3-postfix'],
            ],
            [
                ['line1', $this->separator, 'line2'],
                ['line1', 'line2'],
            ],
            [
                ["line1{$this->separator}", $this->separator, $this->separator, "line4{$this->separator}"],
                ['line1', '', '', 'line4'],
            ],
            [
                ["line1{$this->separator}", "line2{$this->separator}", $this->separator, $this->separator],
                ['line1', 'line2', '', ''],
            ],
        ];
    }
}
