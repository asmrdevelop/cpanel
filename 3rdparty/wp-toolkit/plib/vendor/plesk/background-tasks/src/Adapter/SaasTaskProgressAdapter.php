<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Adapter;

use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use BackgroundTasks\Progress\TaskProgressInterface;

class SaasTaskProgressAdapter implements TaskProgressInterface
{
    /**
     * @var BackgroundTaskRowInterface
     */
    private $task;

    /**
     * @var bool
     */
    private $isTaskProgressControlledManually;

    /**
     * @param BackgroundTaskRowInterface $task
     * @param bool $isTaskProgressControlledManually
     */
    public function __construct(BackgroundTaskRowInterface $task, $isTaskProgressControlledManually)
    {
        $this->task = $task;
        $this->isTaskProgressControlledManually = $isTaskProgressControlledManually;
    }

    /**
     * @param int|float $progress value from 0 to 100
     * @throws \RuntimeException
     */
    public function setProgress($progress)
    {
        if (!$this->isTaskProgressControlledManually) {
            throw new \RuntimeException('Cannot update task progress, because manual control of progress is disabled');
        }

        $this->task->setProgress($progress);
    }
}
