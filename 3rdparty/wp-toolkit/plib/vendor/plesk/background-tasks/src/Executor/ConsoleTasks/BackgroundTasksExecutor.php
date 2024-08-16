<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor\ConsoleTasks;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\Executor\ConsoleTasks\Queue\BackgroundTaskQueueInteface;
use Psr\Log\LoggerInterface;
use React\EventLoop\Factory;
use React\EventLoop\LoopInterface;

class BackgroundTasksExecutor
{
    /**
     * @var BackgroundTaskProcessCreator
     */
    private $backgroundTaskProcessCreator;

    /**
     * @var BackgroundTaskBrokerInterface
     */
    protected $backgroundTaskBroker;

    /**
     * @var BackgroundTaskQueueInteface
     */
    private $backgroundTaskQueue;

    /**
     * @var LoopInterface
     */
    private $loop;

    /**
     * @var LoggerInterface
     */
    private $logger;

    /**
     * @var float
     */
    private $interval;

    /**
     * @var float
     */
    private $shutdownTimeout;

    /**
     * @var int|null
     */
    private $maxSimultaneouslyRunningTasks;

    /**
     * @var int[]
     */
    private $runningTaskIds;

    public function __construct(
        BackgroundTaskProcessCreator $backgroundTaskProcessCreator,
        BackgroundTaskBrokerInterface $backgroundTaskBroker,
        BackgroundTaskQueueInteface $backgroundTaskQueue,
        LoggerInterface $logger,
        float $loopTimerInterval = 1.0,
        float $shutdownTimeout = 0,
        int $maxSimultaneouslyRunningTasks = null
    ) {
        $this->backgroundTaskProcessCreator = $backgroundTaskProcessCreator;
        $this->backgroundTaskBroker = $backgroundTaskBroker;
        $this->backgroundTaskQueue = $backgroundTaskQueue;
        $this->logger = $logger;
        $this->interval = $loopTimerInterval;
        $this->shutdownTimeout = $shutdownTimeout;
        $this->maxSimultaneouslyRunningTasks = $maxSimultaneouslyRunningTasks;
        $this->runningTaskIds = [];
    }

    public function loop(): void
    {
        $loop = $this->getLoop();
        $periodicTimer = $loop->addPeriodicTimer($this->interval, function () use ($loop) {
            try {
                $this->runTasks($loop);
            } catch (\Exception $exception) {
                $this->logger->error($exception);
            }
        });
        if ($this->shutdownTimeout > 0) {
            $loop->addTimer($this->shutdownTimeout, function () use ($loop, $periodicTimer) {
                $loop->cancelTimer($periodicTimer);
            });
        }
        $loop->run();
    }

    private function runTasks(LoopInterface $loop): void
    {
        try {
            $this->refreshRunningTaskIds();
        } catch (\Exception $exception) {
            $this->logger->error($exception);
            return;
        }

        $backgroundTasks = $this->backgroundTaskQueue->takeNextTasks($this->getFreeTasksLimit());
        foreach ($backgroundTasks as $backgroundTask) {
            $backgroundTask->setStatus(BaseTaskInterface::STATUS_STARTED);
            $this->backgroundTaskProcessCreator->createTaskProcess($loop, $backgroundTask);

            $this->runningTaskIds[] = $backgroundTask->getId();
        }
    }

    protected function getLoop(): LoopInterface
    {
        if (is_null($this->loop)) {
            $this->loop = Factory::create();
        }
        return $this->loop;
    }

    public function setLoop(LoopInterface $loop): BackgroundTasksExecutor
    {
        $this->loop = $loop;
        return $this;
    }

    private function refreshRunningTaskIds(): void
    {
        $finishedTasks = [];
        foreach ($this->runningTaskIds as $taskId) {
            $task = $this->backgroundTaskBroker->getById($taskId);
            $status = $task->getStatus();
            if (
                $status !== BaseTaskInterface::STATUS_STARTED &&
                $status !== BaseTaskInterface::STATUS_RUNNING
            ) {
                $finishedTasks[] = $task->getId();
            }
        }

        $this->runningTaskIds = array_diff($this->runningTaskIds, $finishedTasks);
    }

    private function getFreeTasksLimit(): ?int
    {
        if (is_null($this->maxSimultaneouslyRunningTasks)) {
            return null;
        }
        return $this->maxSimultaneouslyRunningTasks - count($this->runningTaskIds);
    }
}
