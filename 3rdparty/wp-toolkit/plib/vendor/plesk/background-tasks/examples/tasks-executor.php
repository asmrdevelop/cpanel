<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTaskExamples;

use BackgroundTasks\DatabaseStorage\PdoDatabaseStorage\BackgroundTaskBroker;
use BackgroundTasks\DatabaseStorage\PdoDatabaseStorage\BackgroundTaskExecutorBroker;
use BackgroundTasks\DatabaseStorage\PdoDatabaseStorage\BackgroundTaskParamsBroker;
use BackgroundTasks\Executor\ConsoleTasks\BackgroundTaskProcessCreator;
use BackgroundTasks\Executor\ConsoleTasks\BackgroundTasksExecutor;
use BackgroundTasks\Executor\ConsoleTasks\Queue\MultiExecutorBackgroundTaskQueue;
use BackgroundTasks\Model\BackgroundTasksCollection;

require_once __DIR__ . '/requirements.php';

$pdo = createSqlitePdo();
$backgroundTaskBroker = new BackgroundTaskBroker($pdo);
$backgroundTaskExecutorBroker = new BackgroundTaskExecutorBroker($pdo);
$backgroundTaskParamsBroker = new BackgroundTaskParamsBroker($pdo);
$logger = new SimpleLogger();
$processCreator = new BackgroundTaskProcessCreator(
    $backgroundTaskParamsBroker,
    $logger,
    ['php', __DIR__ . '/run-task.php']
);
$queue = new MultiExecutorBackgroundTaskQueue($backgroundTaskBroker, $backgroundTaskExecutorBroker, uniqid());
$executor = new BackgroundTasksExecutor(
    $processCreator,
    $backgroundTaskBroker,
    $queue,
    $logger,
    1.0,
    0,
    2
);
$executor->loop();
