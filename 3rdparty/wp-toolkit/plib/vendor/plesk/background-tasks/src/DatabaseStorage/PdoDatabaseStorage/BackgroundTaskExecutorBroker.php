<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage\PdoDatabaseStorage;

use BackgroundTasks\DatabaseStorage\BackgroundTaskExecutorBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use PDO;

class BackgroundTaskExecutorBroker implements BackgroundTaskExecutorBrokerInterface
{
    /**
     * @var PDO
     */
    private $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    public function tryToSetTaskExecutor(BackgroundTaskRowInterface $backgroundTaskRow, string $executorId): bool
    {
        $sth = $this->pdo->prepare("UPDATE tasks SET executorId = ? WHERE id = ? AND executorId IS NULL");
        $sth->execute([$executorId, $backgroundTaskRow->getId()]);
        return $sth->rowCount() > 0;
    }
}
