<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor\ConsoleTasks\Queue;

use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskExecutorBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;

class MultiExecutorBackgroundTaskQueue implements BackgroundTaskQueueInteface
{
    /**
     * @var string
     */
    private $executorId;

    /**
     * @var BackgroundTaskBrokerInterface
     */
    private $backgroundTaskBroker;

    /**
     * @var BackgroundTaskExecutorBrokerInterface
     */
    private $backgroundTaskExecutorBroker;

    public function __construct(
        BackgroundTaskBrokerInterface $backgroundTaskBroker,
        BackgroundTaskExecutorBrokerInterface $backgroundTaskExecutorBroker,
        string $executorId
    )
    {
        $this->executorId = $executorId;
        $this->backgroundTaskBroker = $backgroundTaskBroker;
        $this->backgroundTaskExecutorBroker = $backgroundTaskExecutorBroker;
    }

    /**
     * @param int|null $limit
     * @return BackgroundTaskRowInterface[]
     */
    public function takeNextTasks(?int $limit = null): array
    {
        $takenTasks = [];
        
        $allFreeTasks =  $this->backgroundTaskBroker->getNotStarted();
        foreach ($allFreeTasks as $freeTask) {
            if (!is_null($limit) && count($takenTasks) >= $limit) {
                break;
            }

            if ($this->backgroundTaskExecutorBroker->tryToSetTaskExecutor($freeTask, $this->executorId)) {
                $takenTasks[] = $freeTask;
            }
        }

        return $takenTasks;
    }
}
