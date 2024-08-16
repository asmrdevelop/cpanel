<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage;

interface BackgroundTaskExecutorBrokerInterface
{
    /**
     * Try to set task executor for specified background task. Return true on success.
     * If task is already taken by another executor, return false. You could use query like:
     *      UPDATE tasks SET executorId = $newExecutorId WHERE taskId = $taskId and executorId IS NULL
     * and then check how many rows were affected. If no rows were changed then the task is already taken
     * by another executor, and the method should return false.
     *
     * @param BackgroundTaskRowInterface $backgroundTaskRow
     * @param string $executorId
     * @return bool
     */
    public function tryToSetTaskExecutor(BackgroundTaskRowInterface $backgroundTaskRow, string $executorId): bool;
}
