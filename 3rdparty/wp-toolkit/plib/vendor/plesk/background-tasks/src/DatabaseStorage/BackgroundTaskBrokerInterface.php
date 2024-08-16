<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage;

interface BackgroundTaskBrokerInterface
{
    /**
     * @param int $id
     * @return BackgroundTaskRowInterface|null
     */
    public function getById($id);

    /**
     * @param array $rowData
     * @return BackgroundTaskRowInterface
     */
    public function createRow(array $rowData);

    /**
     * @return BackgroundTaskRowInterface[]
     */
    public function getAll(): array;

    /**
     * @return BackgroundTaskRowInterface[]
     */
    public function getNotStarted(): array;
}
