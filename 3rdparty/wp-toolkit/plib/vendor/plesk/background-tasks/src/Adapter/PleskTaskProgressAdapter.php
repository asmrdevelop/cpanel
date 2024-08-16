<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Adapter;

use BackgroundTasks\Progress\TaskProgressInterface;

class PleskTaskProgressAdapter implements TaskProgressInterface
{
    /**
     * @var PleskBaseTaskAdapter
     */
    private $pleskTask;

    /**
     * @var bool
     */
    private $isTaskProgressControlledManually;

    /**
     * @param PleskBaseTaskAdapter $pleskTask
     * @param bool $isTaskProgressControlledManually
     */
    public function __construct(PleskBaseTaskAdapter $pleskTask, $isTaskProgressControlledManually)
    {
        $this->pleskTask = $pleskTask;
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

        $this->pleskTask->setProgress($progress);
    }
}
