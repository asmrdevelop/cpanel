<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTaskExamples;

use BackgroundTasks\DatabaseStorage\PdoDatabaseStorage\BackgroundTaskPdoDatabase;

require_once __DIR__ . '/requirements.php';

$pdo = createSqlitePdo();
$database = new BackgroundTaskPdoDatabase($pdo);
$database->initDatabase();
