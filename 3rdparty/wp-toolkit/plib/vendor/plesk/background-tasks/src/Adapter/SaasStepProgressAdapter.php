<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Adapter;

use BackgroundTasks\DataStorage\SaasTaskDataStorage;
use BackgroundTasks\Progress\StepProgressInterface;

class SaasStepProgressAdapter implements StepProgressInterface
{
    /**
     * @var SaasTaskDataStorage
     */
    private $taskDataStorage;

    public function __construct(SaasTaskDataStorage $taskDataStorage)
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
