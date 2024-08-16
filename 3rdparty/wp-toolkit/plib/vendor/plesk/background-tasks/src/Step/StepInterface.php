<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Step;

use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Progress\StepProgressInterface;
use BackgroundTasks\Progress\TaskProgressInterface;

interface StepInterface
{
    const STATUS_NOT_STARTED = 'not_started';
    const STATUS_STARTED = 'started';
    const STATUS_RUNNING = 'running';
    const STATUS_CANCELED = 'canceled';
    const STATUS_ERROR = 'error';
    const STATUS_DONE = 'done';

    /**
     * @param StepProgressInterface $progress
     * @param TaskProgressInterface $taskProgress
     * @param TaskDataStorageInterface $taskData
     */
    public function run(StepProgressInterface $progress, TaskProgressInterface $taskProgress, TaskDataStorageInterface $taskData);

    // TODO: rollback?

    /**
     * @return string Unique string, used as key in object of all steps
     */
    public function getCode();

    /**
     * @return string
     */
    public function getTitle();

    /**
     * @return string
     */
    public function getIcon();

    /**
     * @return bool
     */
    public function isHidden();
}
