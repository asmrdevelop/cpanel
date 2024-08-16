<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTaskExamples;

use BackgroundTasks\DatabaseStorage\PdoDatabaseStorage\BackgroundTaskBroker;
use BackgroundTasks\DatabaseStorage\PdoDatabaseStorage\BackgroundTaskParamsBroker;
use BackgroundTasks\Manager\SaasTaskManager;
use BackgroundTasks\Model\BackgroundTasksCollection;

require_once __DIR__ . '/requirements.php';

$pdo = createSqlitePdo();
$backgroundTasksCollection = new BackgroundTasksCollection([new SimpleTask()]);
$backgroundTaskBroker = new BackgroundTaskBroker($pdo);
$backgroundTaskParamsBroker = new BackgroundTaskParamsBroker($pdo);
$taskManager = new SaasTaskManager($backgroundTaskBroker, $backgroundTaskParamsBroker, $backgroundTasksCollection);
$taskManager->startSimpleTask(new SimpleTask());
