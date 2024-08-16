<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage\PdoDatabaseStorage;

use BackgroundTasks\DatabaseStorage\BackgroundTaskParamRowInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskParamsBrokerInterface;
use PDO;

class BackgroundTaskParamsBroker implements BackgroundTaskParamsBrokerInterface
{
    /**
     * @var PDO
     */
    private $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    /**
     * @param array $rowData
     * @return BackgroundTaskParamRowInterface
     */
    public function createRow(array $rowData = [])
    {
        $sth = $this->pdo->prepare('INSERT INTO params DEFAULT VALUES');
        $sth->execute();
        $id = $this->pdo->lastInsertId();

        return new BackgroundTaskParamRow($this->pdo, $id);
    }

    /**
     * @param int $taskId
     * @return BackgroundTaskParamRowInterface[]
     */
    public function getAll(int $taskId): array
    {
        $params = [];
        $sth = $this->pdo->prepare('SELECT id, taskId, paramName, paramValue FROM params');
        $sth->execute();
        foreach ($sth->fetchAll() as $row) {
            $params[] = new BackgroundTaskParamRow(
                $this->pdo,
                $row['id'],
                $row['taskId'],
                $row['paramName'],
                $row['paramValue'] ?? unserialize($row['paramValue'])
            );
        }

        return $params;
    }

    public function getByName(int $taskId, string $name): ?BackgroundTaskParamRowInterface
    {
        $sth = $this->pdo->prepare(
            'SELECT id, taskId, paramName, paramValue FROM params WHERE taskId = ? AND paramName = ?'
        );
        $sth->execute([$taskId, $name]);
        $rows = $sth->fetchAll();

        if (count($rows) == 0) {
            return null;
        }

        $row = reset($rows);

        return new BackgroundTaskParamRow(
            $this->pdo,
            $row['id'],
            $row['taskId'],
            $row['paramName'],
            $row['paramValue'] ?? unserialize($row['paramValue'])
        );
    }

    public function hasParameter(int $taskId, string $paramCode): bool
    {
        return !is_null($this->getByName($taskId, $paramCode));
    }
}
