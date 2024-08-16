<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Model;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\ComplexTaskInterface;
use BackgroundTasks\SimpleTaskInterface;

interface BackgroundTasksCollectionInterface
{
    /**
     * @return BaseTaskInterface[]
     */
    public function getAll(): array;

    /**
     * @param string $code
     * @return BaseTaskInterface|SimpleTaskInterface|ComplexTaskInterface|null
     */
    public function getByCode(string $code): ?BaseTaskInterface;
}
