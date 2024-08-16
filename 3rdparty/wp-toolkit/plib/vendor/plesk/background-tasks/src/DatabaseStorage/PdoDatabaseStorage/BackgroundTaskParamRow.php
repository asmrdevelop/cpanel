<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage\PdoDatabaseStorage;

use BackgroundTasks\DatabaseStorage\BackgroundTaskParamRowInterface;
use PDO;

class BackgroundTaskParamRow implements BackgroundTaskParamRowInterface
{
    /**
     * @var PDO
     */
    private $pdo;

    /**
     * @var int|null
     */
    private $id;

    /**
     * @var int|null
     */
    private $taskId;

    /**
     * @var mixed|null
     */
    private $value;

    /**
     * @var string|null
     */
    private $name;

    public function __construct(PDO $pdo, int $id, ?int $taskId = null, ?string $name = null, $value = null)
    {
        $this->pdo = $pdo;
        $this->id = $id;
        $this->taskId = $taskId;
        $this->name = $name;
        $this->value = $value;
    }

    public function setTaskId(int $taskId): BackgroundTaskParamRowInterface
    {
        $this->taskId = $taskId;
        $this->save();
        return $this;
    }

    /**
     * @param mixed $value
     * @return $this
     */
    public function setValue($value): BackgroundTaskParamRowInterface
    {
        $this->value = $value;
        $this->save();
        return $this;
    }

    /**
     * @return mixed
     */
    public function getValue()
    {
        return $this->value;
    }

    public function setName(string $name): BackgroundTaskParamRowInterface
    {
        $this->name = $name;
        $this->save();
        return $this;
    }

    public function getName(): string
    {
        return $this->name;
    }

    public function save()
    {
        $sth = $this->pdo->prepare('UPDATE params SET taskId = ?, paramName = ?, paramValue = ? WHERE id = ?');
        $sth->execute([$this->taskId, $this->name, serialize($this->value), $this->id]);
    }
}
