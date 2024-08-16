<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks;

use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Model\TaskExecutionOptions;
use Psr\Log\LoggerInterface;
use Psr\Log\NullLogger;

abstract class BaseTask implements BaseTaskInterface
{
    /**
     * @var LoggerInterface
     */
    protected $logger;

    /**
     * @var TaskExecutionOptions
     */
    protected $taskExecutionOptions;

    /**
     * @param LoggerInterface|null $logger
     */
    public function __construct(LoggerInterface $logger = null)
    {
        $this->logger = $logger ?: new NullLogger();
    }

    /**
     * @param TaskDataStorageInterface $taskData
     */
    public function onStart(TaskDataStorageInterface $taskData)
    {
        // By default, do nothing. Override if you need to handle the start event.
    }

    /**
     * @param TaskDataStorageInterface $taskData
     * @param \Exception $exception
     */
    public function onError(TaskDataStorageInterface $taskData, \Exception $exception)
    {
        // By default, do nothing. Override if you need to handle the error event.
    }

    /**
     * @param TaskDataStorageInterface $taskData
     */
    public function onDone(TaskDataStorageInterface $taskData)
    {
        // By default, do nothing. Override if you need to handle the done event.
    }

    /**
     * @return TaskExecutionOptions
     */
    public function getExecutionOptions()
    {
        if (is_null($this->taskExecutionOptions)) {
            // Use default execution options, override if you need custom ones.
            return $this->taskExecutionOptions = new TaskExecutionOptions();
        }

        return $this->taskExecutionOptions;
    }

    /**
     * @param TaskExecutionOptions $executionOptions
     * @return $this
     */
    public function setExecutionOptions(TaskExecutionOptions $executionOptions)
    {
        $this->taskExecutionOptions = $executionOptions;
        return $this;
    }

    /**
     * @return string
     */
    public function getCode()
    {
        $className = static::class;
        if (preg_match('/^Modules_([^_]*)_(.*)$/', $className, $matches) ||
            preg_match('/^PleskExt\\\\([^\\\\]*)\\\\(.*)$/', $className, $matches)) {
            $id = $matches[2];
        } else {
            $id = $className;
        }

        return strtolower($id);
    }
}
