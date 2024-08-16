<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor\ConsoleTasks\Queue;

use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;

class SingleProcessBackgroundTaskQueue implements BackgroundTaskQueueInteface
{
    /**
     * @var BackgroundTaskBrokerInterface
     */
    private $backgroundTaskBroker;

    public function __construct(BackgroundTaskBrokerInterface $backgroundTaskBroker)
    {
        $this->backgroundTaskBroker = $backgroundTaskBroker;
    }

    /**
     * @param int|null $limit
     * @return BackgroundTaskRowInterface|null
     */
    public function takeNextTasks(?int $limit = null): array
    {
        $tasks = $this->backgroundTaskBroker->getNotStarted();
        return is_null($limit) ? $tasks : array_slice($tasks, 0, $limit);
    }
}
