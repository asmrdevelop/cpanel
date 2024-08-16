<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks;

use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Progress\TaskProgressInterface;

interface SimpleTaskInterface extends BaseTaskInterface
{
    /**
     * @param TaskProgressInterface $progress
     * @param TaskDataStorageInterface $taskData
     */
    public function run(TaskProgressInterface $progress, TaskDataStorageInterface $taskData);
}
