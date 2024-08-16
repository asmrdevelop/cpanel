<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Adapter;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DataStorage\PleskTaskDataStorage;
use BackgroundTasks\SimpleTaskInterface;
use Psr\Log\LoggerInterface;
use Psr\Log\NullLogger;

class PleskSimpleTaskAdapter extends PleskBaseTaskAdapter
{
    /**
     * @var SimpleTaskInterface
     */
    private $task;

    /**
     * @var PleskTaskDataStorage
     */
    private $taskDataStorage;

    /**
     * @var LoggerInterface
     */
    private $logger;

    public function __construct(SimpleTaskInterface $task, LoggerInterface $logger = null)
    {
        parent::__construct();

        $this->task = $task;
        $this->logger = $logger ?: new NullLogger();

        $this->setExecutionOptions(
            $task->getExecutionOptions()
        );
    }

    public function run()
    {
        // Workaround for https://jira.plesk.ru/browse/PPP-43858, see method description for details
        $this->assertOnStartSuccess();

        $this->task->run(
            new PleskTaskProgressAdapter($this, true),
            $this->getTaskDataStorage()
        );
        $this->setProgress(100);
    }

    /**
     * @return BaseTaskInterface
     */
    public function getExecutableTask()
    {
        return $this->task;
    }

    /**
     * @return PleskTaskDataStorage
     */
    public function getTaskDataStorage()
    {
        // ATTENTION: don't initialize in constructor, use lazy initialization!
        // When we fetching tasks from Plesk SDK, it creating new instance of each task and after that it additionally
        // setting up row of LongTask into created instance, that row is required for PleskTaskDataStorage.
        if (is_null($this->taskDataStorage)) {
            return $this->taskDataStorage = new PleskTaskDataStorage($this);
        }
        return $this->taskDataStorage;
    }

    protected function getLogger(): LoggerInterface
    {
        return $this->logger;
    }
}
