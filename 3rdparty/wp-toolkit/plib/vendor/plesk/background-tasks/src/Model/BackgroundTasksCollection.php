<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Model;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\ComplexTaskInterface;
use BackgroundTasks\SimpleTaskInterface;

class BackgroundTasksCollection implements BackgroundTasksCollectionInterface
{
    /**
     * @var BaseTaskInterface[]
     */
    private $backgroundTasks = [];

    /**
     * @param BaseTaskInterface[] $backgroundTasks
     */
    public function __construct($backgroundTasks)
    {
        foreach ($backgroundTasks as $backgroundTask) {
            $this->add($backgroundTask);
        }
    }

    /**
     * @param BaseTaskInterface $backgroundTask
     */
    private function add(BaseTaskInterface $backgroundTask)
    {
        $this->backgroundTasks[$backgroundTask->getCode()] = $backgroundTask;
    }

    /**
     * @return BaseTaskInterface[]
     */
    public function getAll(): array
    {
        return $this->backgroundTasks;
    }

    /**
     * @param string $code
     * @return BaseTaskInterface|SimpleTaskInterface|ComplexTaskInterface|null
     */
    public function getByCode(string $code): ?BaseTaskInterface
    {
        foreach ($this->getAll() as $backgroundTask) {
            if ($backgroundTask->getCode() === $code) {
                return $backgroundTask;
            }
        }
        return null;
    }
}
