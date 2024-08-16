<?php

namespace BackgroundTaskExamples;

use BackgroundTasks\BaseSimpleTask;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Progress\TaskProgressInterface;

class SimpleTask extends BaseSimpleTask
{
    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getNotStartedMessage(TaskDataStorageInterface $taskData)
    {
        return 'my simple task is not started';
    }

    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getInProgressMessage(TaskDataStorageInterface $taskData)
    {
        return 'my simple task is in progress';
    }

    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getDoneMessage(TaskDataStorageInterface $taskData)
    {
        return 'my simple task is done';
    }

    /**
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    public function getErrorMessage(TaskDataStorageInterface $taskData)
    {
        return 'my simple task has failed';
    }

    /**
     * @param TaskProgressInterface $progress
     * @param TaskDataStorageInterface $taskData
     */
    public function run(TaskProgressInterface $progress, TaskDataStorageInterface $taskData)
    {
        echo 'my simple task stated' . PHP_EOL;
        sleep(10);
        echo 'my simple task finished' . PHP_EOL;
    }
}
