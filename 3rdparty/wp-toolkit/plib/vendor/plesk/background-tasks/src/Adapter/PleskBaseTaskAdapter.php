<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Adapter;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Model\TaskExecutionOptions;
use Psr\Log\LoggerInterface;

abstract class PleskBaseTaskAdapter extends \pm_LongTask_Task
{
    /**
     * @var int
     */
    public $poolSize;

    /**
     * @var bool
     */
    public $trackProgress;

    /**
     * @var bool
     */
    public $hidden;

    /**
     * Storage for exception at onStartMethod to workaround https://jira.plesk.ru/browse/PPP-43858
     *
     * @var null|\Exception
     */
    private $onStartException;

    /**
     * @return BaseTaskInterface
     */
    abstract public function getExecutableTask();

    /**
     * @return TaskDataStorageInterface
     */
    abstract public function getTaskDataStorage();

    /**
     * @param int $progress
     */
    public function setProgress($progress)
    {
        $progress = ceil($progress);
        if ($progress > 100) {
            $progress = 100;
        }
        parent::updateProgress($progress);
    }

    public function onStart()
    {
        // The try-catch block is to workaround https://jira.plesk.ru/browse/PPP-43858:
        // long task which throws an exception at "onStart" method, is displayed as "in progress" and hangs in
        // that state.

        try {
            $this->getExecutableTask()->onStart(
                $this->getTaskDataStorage()
            );
        } catch (\Exception $e) {
            $this->getLogger()->debug("Failed to start long task {taskName}: {exception}", [
                'exception' => $e,
                'taskName' => get_class($this->getExecutableTask())
            ]);

            $this->onStartException = $e;
        }
    }

    public function onError(\Exception $exception)
    {
        $this->getExecutableTask()->onError(
            $this->getTaskDataStorage(),
            $exception
        );
    }

    public function onDone()
    {
        $this->getExecutableTask()->onDone(
            $this->getTaskDataStorage()
        );
    }

    /**
     * @return string
     */
    public function statusMessage()
    {
        $task = $this->getExecutableTask();
        $taskDataStorage = $this->getTaskDataStorage();

        $status = $this->getStatus();
        switch ($status) {
            case BaseTaskInterface::STATUS_NOT_STARTED:
                return $task->getNotStartedMessage($taskDataStorage);
            case BaseTaskInterface::STATUS_STARTED:
            case BaseTaskInterface::STATUS_RUNNING:
                return $task->getInProgressMessage($taskDataStorage);
            case BaseTaskInterface::STATUS_ERROR:
                return $task->getErrorMessage($taskDataStorage);
            default:
                return $task->getDoneMessage($taskDataStorage);
        }
    }

    /**
     * @return string
     */
    public function getId()
    {
        return $this->getExecutableTask()->getCode();
    }

    /**
     * @param TaskExecutionOptions $options
     */
    protected function setExecutionOptions(TaskExecutionOptions $options)
    {
        $this->poolSize = $options->getPoolSize();
        $this->trackProgress = $options->getIsProgressTrackable();
        $this->hidden = $options->getIsHidden();
    }

    /**
     * Workaround for https://jira.plesk.ru/browse/PPP-43858:
     * long task which throws an exception at "onStart" method, is displayed as "in progress" and hangs in
     * that state.
     *
     * That method should be called at the very beginning of "run" method.
     *
     * @throws \Exception
     */
    protected function assertOnStartSuccess()
    {
        if (!is_null($this->onStartException)) {
            throw $this->onStartException;
        }
    }

    abstract protected function getLogger(): LoggerInterface;
}
