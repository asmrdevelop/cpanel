<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Adapter;

use BackgroundTasks\DataStorage\PleskTaskDataStorage;
use BackgroundTasks\Progress\StepProgressInterface;

class PleskStepProgressAdapter implements StepProgressInterface
{
    /**
     * @var PleskTaskDataStorage
     */
    private $taskDataStorage;

    public function __construct(PleskTaskDataStorage $taskDataStorage)
    {
        $this->taskDataStorage = $taskDataStorage;
    }

    /**
     * @param int|float $progress value from 0 to 100
     */
    public function setProgress($progress)
    {
        $this->taskDataStorage->setPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, $progress);
    }

    /**
     * @param string $text
     */
    public function setHint($text)
    {
        $this->taskDataStorage->setPrivateParam(StepProgressInterface::CURRENT_STEP_HINT, $text);
    }
}
