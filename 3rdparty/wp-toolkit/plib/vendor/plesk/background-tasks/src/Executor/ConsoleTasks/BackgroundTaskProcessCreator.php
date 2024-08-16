<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor\ConsoleTasks;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskParamsBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use BackgroundTasks\DataStorage\SaasTaskDataStorage;
use Psr\Log\LoggerInterface;
use React\ChildProcess\Process;
use React\EventLoop\LoopInterface;

class BackgroundTaskProcessCreator
{
    /**
     * @var LoggerInterface
     */
    private $logger;

    /**
     * @var string[]
     */
    private $commandWithArgs;

    /**
     * @var BackgroundTaskParamsBrokerInterface
     */
    private $backgroundTaskParamsBroker;

    /**
     * @param BackgroundTaskParamsBrokerInterface $backgroundTaskParamsBroker
     * @param LoggerInterface $logger
     * @param string[] $commandWithArgs Command to execute. Task id will be automatically passed in arguments
     */
    public function __construct(
        BackgroundTaskParamsBrokerInterface $backgroundTaskParamsBroker,
        LoggerInterface $logger,
        array $commandWithArgs
    ) {
        $this->backgroundTaskParamsBroker = $backgroundTaskParamsBroker;
        $this->logger = $logger;
        $this->commandWithArgs = $commandWithArgs;
    }

    public function createTaskProcess(LoopInterface $loop, BackgroundTaskRowInterface $backgroundTask): void
    {
        $escapedCommand = implode(' ', array_map(function ($command) {
            return escapeshellarg($command);
        }, $this->commandWithArgs));

        $taskId = (int)$backgroundTask->getId();

        $this->logger->debug("Starting process for task '{id}'", [
            'id' => $taskId,
        ]);

        $stdoutLogger = $this->createLogger($taskId);
        $stderrLogger = $this->createLogger($taskId);

        $escapedLongTaskId = escapeshellarg($taskId);
        $process = new Process("{$escapedCommand} {$escapedLongTaskId}");
        $process->start($loop);

        $process->stdout->on('data', $stdoutLogger->onData());
        $process->stdout->on('end', $stdoutLogger->onEnd());

        $process->stderr->on('data', $stderrLogger->onData());
        $process->stderr->on('end', $stderrLogger->onEnd());

        $process->on('exit', function ($exitCode, $termSignal) use ($backgroundTask, $taskId) {
            $this->logger->debug("Process for task '{id}' exited with code '{code}' and signal '{signal}'", [
                'id' => $taskId,
                'code' => $exitCode,
                'signal' => $termSignal,
            ]);

            if ((int)$exitCode === 0 && is_null($termSignal)) {
                return;
            }
            $backgroundTask->setStatus(BaseTaskInterface::STATUS_ERROR);
            $taskDataStorage = new SaasTaskDataStorage($backgroundTask, $this->backgroundTaskParamsBroker);
            $taskDataStorage->addError("Task is not responding, error code '{$exitCode}'");
        });

        $backgroundTask->setPid($process->getPid());
    }

    private function createLogger(int $taskId): ChildProcessOutputLogger
    {
        return new ChildProcessOutputLogger($this->logger, "[Task id: {$taskId}] ");
    }
}
