<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor\ConsoleTasks\Queue;

use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;

interface BackgroundTaskQueueInteface
{
    /**
     * @param int|null $limit
     * @return BackgroundTaskRowInterface[]
     */
    public function takeNextTasks(?int $limit = null): array;
}
