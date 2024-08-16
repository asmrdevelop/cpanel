<?php

namespace BackgroundTasks\Executor\ConsoleTasks;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\Executor\ConsoleTasks\Queue\BackgroundTaskQueueInteface;
use BackgroundTasks\Manager\TaskManagerInterface;
use Psr\Log\LoggerInterface;

/**
 * The presented class should be used to periodically kill hanged background tasks
 * with dead pid, it can't be used with multiple tasks executors.
 *
 * Class SingleBackgroundTasksExecutor
 * @package BackgroundTasks\Executor\ConsoleTasks
 */
class SingleBackgroundTasksExecutor extends BackgroundTasksExecutor
{
    private const KILL_ORPHANED_TASKS_PERIOD = 60;

    /**
     * @var TaskManagerInterface
     */
    private $taskManager;

    public function __construct(
        TaskManagerInterface $taskManager,
        BackgroundTaskProcessCreator $backgroundTaskProcessCreator,
        BackgroundTaskBrokerInterface $backgroundTaskBroker,
        BackgroundTaskQueueInteface $backgroundTaskQueue,
        LoggerInterface $logger,
        float $loopTimerInterval = 1.0,
        float $shutdownTimeout = 0,
        int $maxSimultaneouslyRunningTasks = null
    ) {
        $this->taskManager = $taskManager;
        parent::__construct($backgroundTaskProcessCreator, $backgroundTaskBroker, $backgroundTaskQueue, $logger, $loopTimerInterval, $shutdownTimeout, $maxSimultaneouslyRunningTasks);
    }

    public function loop(): void
    {
        $loop = $this->getLoop();
        $loop->addPeriodicTimer(self::KILL_ORPHANED_TASKS_PERIOD, function () {
            $this->killOrphanedTasks();
        });
        parent::loop();
    }

    private function killOrphanedTasks(): void
    {
        $tasks = $this->backgroundTaskBroker->getAll();
        foreach ($tasks as $task) {
            if (
                !$task->getPid()
                || !in_array($task->getStatus(), [BaseTaskInterface::STATUS_RUNNING, BaseTaskInterface::STATUS_STARTED], true)
            ) {
                continue;
            }
            if (!posix_getsid($task->getPid()) && $taskDataStorage = $this->taskManager->getTaskDataStorage($task->getId(), $task->getCode())) {
                $taskDataStorage->addError('Task is not responding');
                $task->setStatus(BaseTaskInterface::STATUS_ERROR);
            }
        }
    }
}
