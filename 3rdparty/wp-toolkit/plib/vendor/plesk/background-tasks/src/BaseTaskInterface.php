<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks;

use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Model\TaskExecutionOptions;

interface BaseTaskInterface {
    const STATUS_SCHEDULING = 'scheduling';
    const STATUS_NOT_STARTED = 'not_started';
    const STATUS_STARTED = 'started';
    const STATUS_RUNNING = 'running';
    const STATUS_CANCELED = 'canceled';
    const STATUS_ERROR = 'error';
    const STATUS_DONE = 'done';

    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getNotStartedMessage(TaskDataStorageInterface $taskData);

    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getInProgressMessage(TaskDataStorageInterface $taskData);

    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getDoneMessage(TaskDataStorageInterface $taskData);

    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getErrorMessage(TaskDataStorageInterface $taskData);

    /**
     * @param TaskDataStorageInterface $taskData
     */
    public function onStart(TaskDataStorageInterface $taskData);

    /**
     * @param TaskDataStorageInterface $taskData
     * @param \Exception $exception
     */
    public function onError(TaskDataStorageInterface $taskData, \Exception $exception);

    /**
     * @param TaskDataStorageInterface $taskData
     */
    public function onDone(TaskDataStorageInterface $taskData);

    /**
     * @return TaskExecutionOptions
     */
    public function getExecutionOptions();

    /**
     * @return string
     */
    public function getCode();
}
