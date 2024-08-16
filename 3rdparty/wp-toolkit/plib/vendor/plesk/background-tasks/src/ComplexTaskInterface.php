<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks;

use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Step\StepInterface;

interface ComplexTaskInterface extends BaseTaskInterface
{
    /**
     * @param TaskDataStorageInterface $taskData
     * @return StepInterface[]
     */
    public function getSteps(TaskDataStorageInterface $taskData);
}
