<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Manager;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskParamsBrokerInterface;
use BackgroundTasks\DataStorage\SaasTaskDataStorage;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use BackgroundTasks\Helper\StepHelper;
use BackgroundTasks\Model\BackgroundTasksCollection;
use BackgroundTasks\Model\BackgroundTasksCollectionInterface;
use BackgroundTasks\SimpleTaskInterface;
use BackgroundTasks\ComplexTaskInterface;

class SaasTaskManager implements TaskManagerInterface
{
    /**
     * @var BackgroundTaskBrokerInterface
     */
    private $backgroundTaskBroker;

    /**
     * @var BackgroundTasksCollectionInterface
     */
    private $backgroundTasksCollection;

    /**
     * @var BackgroundTaskParamsBrokerInterface
     */
    private $backgroundTaskParamsBroker;

    public function __construct(
        BackgroundTaskBrokerInterface $backgroundTaskBroker,
        BackgroundTaskParamsBrokerInterface $backgroundTaskParamsBroker,
        BackgroundTasksCollectionInterface $backgroundTasksCollection = null
    ) {
        $this->backgroundTaskBroker = $backgroundTaskBroker;
        $this->backgroundTaskParamsBroker = $backgroundTaskParamsBroker;
        $this->backgroundTasksCollection = $backgroundTasksCollection ?: new BackgroundTasksCollection([]);
    }

    /**
     * @param SimpleTaskInterface $task
     * @param array $parameters
     * @return int started task ID which could be used to track its progress
     */
    public function startSimpleTask(SimpleTaskInterface $task, array $parameters = [])
    {
        $longTask = $this->createLongTask($task, $parameters);
        $longTask->setStatus(BaseTaskInterface::STATUS_NOT_STARTED);
        return $longTask->getId();
    }

    /**
     * @param ComplexTaskInterface $task
     * @param array $parameters
     * @return int started task ID which could be used to track its progress
     */
    public function startTaskWithSteps(ComplexTaskInterface $task, array $parameters = [])
    {
        $longTask = $this->createLongTask($task, $parameters);
        $longTask->setStatus(BaseTaskInterface::STATUS_NOT_STARTED);
        return $longTask->getId();
    }

    public function getTaskDataStorage(int $id, string $code): ?TaskDataStorageInterface
    {
        $task = $this->getTask($id);
        if ($task === null) {
            return null;
        }
        return new SaasTaskDataStorage($task, $this->backgroundTaskParamsBroker);
    }

    /**
     * @param int $id
     * @param string $code
     * @return array|null
     */
    public function getTaskInfo($id, $code)
    {
        $task = $this->getTask($id);
        if (is_null($task)) {
            return null;
        }

        $executableTask = $this->backgroundTasksCollection->getByCode($task->getCode());
        if (is_null($executableTask)) {
            return null;
        }
        $taskDataStorage = new SaasTaskDataStorage($task, $this->backgroundTaskParamsBroker);

        $steps = [];
        if ($executableTask instanceof ComplexTaskInterface) {
            $stepsMetaInfo = StepHelper::getStepsMetaInfo(
                $executableTask->getSteps($taskDataStorage),
                $taskDataStorage,
                $task->getProgress(),
                $task->getStatus()
            );

            foreach ($stepsMetaInfo as $stepMetaInfo) {
                $steps[$stepMetaInfo->getCode()] = [
                    'title' => $stepMetaInfo->getTitle(),
                    'icon' => $stepMetaInfo->getIcon(),
                    'progress' => $stepMetaInfo->getProgress(),
                    'status' => $stepMetaInfo->getStatus(),
                    'hint' => $stepMetaInfo->getHint(),
                ];
            }
        }

        return [
            'id' => $task->getId(),
            'code' => $executableTask->getCode(),
            'title' => $this->getTaskTitle($executableTask, $task, $taskDataStorage),
            'status' => $task->getStatus(),
            'progress' => $task->getProgress(),
            'steps' => $steps,
            'publicParams' => $taskDataStorage->getPublicParams(),
            'errors' => $taskDataStorage->getErrors(),
        ];
    }

    public function getAll(): array
    {
        $tasks = [];
        foreach ($this->backgroundTaskBroker->getAll() as $task) {
            $tasks[] = $this->getTaskInfo($task->getId(), $task->getCode());
        }
        return $tasks;
    }

    public function delete(int $id, string $code): void
    {
        $task = $this->getTask($id);
        if (is_null($task)) {
            return;
        }

        $task->delete();
    }

    /**
     * @param BaseTaskInterface $task
     * @param array $parameters
     * @return BackgroundTaskRowInterface
     */
    protected function createLongTask(BaseTaskInterface $task, array $parameters = [])
    {
        $longTask = $this->backgroundTaskBroker->createRow([
            'code' => $task->getCode(),
            'status' => BaseTaskInterface::STATUS_SCHEDULING,
            'progressValue' => 0,
        ]);
        $longTask->save();

        $dataStorage = new SaasTaskDataStorage($longTask, $this->backgroundTaskParamsBroker);
        $dataStorage->setPrivateParam(TaskDataStorageInterface::INITIAL_TASK_PARAMETERS, $parameters);

        return $longTask;
    }

    /**
     * @param int $id
     * @return BackgroundTaskRowInterface|null
     */
    private function getTask($id)
    {
        return $this->backgroundTaskBroker->getById($id);
    }

    /**
     * @param BaseTaskInterface $executableTask
     * @param BackgroundTaskRowInterface $task
     * @param TaskDataStorageInterface $taskData
     * @return string
     */
    private function getTaskTitle(BaseTaskInterface $executableTask, BackgroundTaskRowInterface $task, TaskDataStorageInterface $taskData)
    {
        switch ($task->getStatus()) {
            case BaseTaskInterface::STATUS_RUNNING:
            case BaseTaskInterface::STATUS_STARTED:
                return $executableTask->getInProgressMessage($taskData);
            case BaseTaskInterface::STATUS_ERROR:
                return $executableTask->getErrorMessage($taskData);
            case BaseTaskInterface::STATUS_DONE:
                return $executableTask->getDoneMessage($taskData);
            default:
                return $executableTask->getNotStartedMessage($taskData);
        }
    }
}
