<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage\PdoDatabaseStorage;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use PDO;

class BackgroundTaskBroker implements BackgroundTaskBrokerInterface
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
     * @param int $id
     * @return BackgroundTaskRowInterface|null
     */
    public function getById($id)
    {
        $sth = $this->pdo->prepare('SELECT code, progress, status FROM tasks WHERE id = ?');
        $sth->execute([$id]);
        $rows = $sth->fetchAll();
        if (count($rows) == 0) {
            throw new \Exception("There is no background task with ID {$id}");
        }

        $row = reset($rows);
        return new BackgroundTaskRow(
            $this->pdo,
            $id,
            $row['code'],
            $row['status'],
            $row['pid'],
            $row['progress']
        );

    }

    /**
     * @param array $rowData
     * @return BackgroundTaskRowInterface
     */
    public function createRow(array $rowData)
    {
        $sth = $this->pdo->prepare('INSERT INTO tasks (code, status, pid, progress) VALUES (?, ?, ?, ?)');
        $code = $rowData['code'] ?? null;
        $status = $rowData['status'] ?? null;
        $pid = $rowData['pid'] ?? null;
        $progress = $rowData['progressValue'] ?? null;
        $sth->execute([$code, $status, $pid, $progress]);
        $id = $this->pdo->lastInsertId();
        return new BackgroundTaskRow(
            $this->pdo,
            $id,
            $code,
            $status,
            $pid,
            $progress
        );
    }

    /**
     * @return BackgroundTaskRowInterface[]
     */
    public function getAll(): array
    {
        $backgroundTasks = [];
        $sth = $this->pdo->prepare('SELECT id, code, progress, pid, status FROM tasks');
        $sth->execute();
        foreach ($sth->fetchAll() as $row) {
            $backgroundTasks[] = new BackgroundTaskRow(
                $this->pdo,
                $row['id'],
                $row['code'],
                $row['status'],
                $row['pid'],
                $row['progress']
            );
        }
        return $backgroundTasks;
    }

    /**
     * @return BackgroundTaskRowInterface[]
     */
    public function getNotStarted(): array
    {
        $backgroundTasks = [];
        $sth = $this->pdo->prepare('SELECT id, code, progress, pid, status FROM tasks WHERE status = ?');
        $sth->execute([BaseTaskInterface::STATUS_NOT_STARTED]);
        foreach ($sth->fetchAll() as $row) {
            $backgroundTasks[] = new BackgroundTaskRow(
                $this->pdo,
                $row['id'],
                $row['code'],
                $row['status'],
                $row['pid'],
                $row['progress']
            );
        }
        return $backgroundTasks;
    }
}
