<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage;

interface BackgroundTaskParamsBrokerInterface
{
    /**
     * @param array $rowData
     * @return BackgroundTaskParamRowInterface
     */
    public function createRow(array $rowData = []);

    /**
     * @param int $taskId
     * @return BackgroundTaskParamRowInterface[]
     */
    public function getAll(int $taskId): array;

    public function getByName(int $taskId, string $name): ?BackgroundTaskParamRowInterface;

    public function hasParameter(int $taskId, string $paramCode): bool;
}
