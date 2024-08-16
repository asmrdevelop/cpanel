<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Model;

use BackgroundTasks\DataStorage\TaskDataStorageInterface;

class SynchronousTaskExecutionResult
{
    /**
     * @var TaskDataStorageInterface
     */
    private $taskData;

    public function __construct(TaskDataStorageInterface $taskData)
    {
        $this->taskData = $taskData;
    }

    /**
     * @return TaskDataStorageInterface
     */
    public function getTaskData()
    {
        return $this->taskData;
    }
}
