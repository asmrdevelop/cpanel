<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage\PdoDatabaseStorage;

use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use PDO;

class BackgroundTaskRow implements BackgroundTaskRowInterface
{
    /**
     * @var PDO
     */
    private $pdo;

    /**
     * @var string|null
     */
    private $status;

    /**
     * @var int|null
     */
    private $progress;

    /**
     * @var int|null
     */
    private $id;

    /**
     * @var string|null
     */
    private $code;

    /**
     * @var int|null
     */
    private $pid;

    public function __construct(PDO $pdo, ?int $id, ?string $code, ?string $status, ?int $pid, int $progress)
    {
        $this->pdo = $pdo;
        $this->id = $id;
        $this->code = $code;
        $this->status = $status;
        $this->pid = $pid;
        $this->progress = $progress;
    }

    /**
     * @param string $status
     */
    public function setStatus($status)
    {
        $this->status = $status;
        $this->save();
    }

    /**
     * @return string
     */
    public function getStatus()
    {
        return $this->status;
    }

    /**
     * @param int|float $progress
     */
    public function setProgress($progress)
    {
        $this->progress = $progress;
        $this->save();
    }

    /**
     * @return int|float
     */
    public function getProgress()
    {
        return $this->progress;
    }

    /**
     * @return int
     */
    public function getId()
    {
        return $this->id;
    }

    /**
     * @return string
     */
    public function getCode()
    {
        return $this->code;
    }

    /**
     * @return void
     */
    public function save()
    {
        $sth = $this->pdo->prepare('UPDATE tasks SET code = ?, status = ?, progress = ?, pid = ? WHERE id = ?');
        $sth->execute([$this->code, $this->status, $this->progress, $this->pid, $this->id]);
    }

    /**
     * @return void
     */
    public function delete()
    {
        $sth = $this->pdo->prepare('DELETE FROM tasks WHERE id = ?');
        $sth->execute([$this->id]);
    }

    public function setPid($pid)
    {
        $this->pid = $pid;
        $this->save();
    }

    public function getPid()
    {
        return $this->pid;
    }
}
