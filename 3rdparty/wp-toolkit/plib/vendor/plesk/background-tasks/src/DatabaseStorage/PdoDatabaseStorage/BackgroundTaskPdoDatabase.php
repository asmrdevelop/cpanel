<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage\PdoDatabaseStorage;

use PDO;

class BackgroundTaskPdoDatabase
{
    /**
     * @var PDO
     */
    private $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    public function initDatabase()
    {
        $this->pdo->exec(
            "CREATE TABLE tasks (id INTEGER PRIMARY KEY, code TEXT, progress INTEGER, status TEXT, pid INTEGER, executorId TEXT)"
        );
        $this->pdo->exec(
            "CREATE TABLE params (id INTEGER PRIMARY KEY, taskId INTEGER, paramName TEXT, paramValue TEXT)"
        );
    }
}
