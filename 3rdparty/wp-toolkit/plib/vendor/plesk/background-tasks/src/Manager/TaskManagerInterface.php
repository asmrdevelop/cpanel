<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Manager;

use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\SimpleTaskInterface;
use BackgroundTasks\ComplexTaskInterface;

interface TaskManagerInterface
{
    /**
     * @param SimpleTaskInterface $task
     * @param array $parameters
     * @return int started task ID which could be used to track its progress
     */
    public function startSimpleTask(SimpleTaskInterface $task, array $parameters = []);

    /**
     * @param ComplexTaskInterface $task
     * @param array $parameters
     * @return int started task ID which could be used to track its progress
     */
    public function startTaskWithSteps(ComplexTaskInterface $task, array $parameters = []);

    /**
     * @param int $id
     * @param string $code
     * @return array|null
     */
    public function getTaskInfo($id, $code);

    /**
     * @return array Tasks for frontend
     */
    public function getAll(): array;

    public function delete(int $id, string $code): void;

    public function getTaskDataStorage(int $id, string $code): ?TaskDataStorageInterface;
}
