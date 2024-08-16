<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Manager;

use BackgroundTasks\Adapter\PleskBaseTaskAdapter;
use BackgroundTasks\Adapter\PleskSimpleTaskAdapter;
use BackgroundTasks\Adapter\PleskComplexTaskAdapter;
use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use BackgroundTasks\DataStorage\PleskTaskDataStorage;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Helper\StepHelper;
use BackgroundTasks\Model\BackgroundTasksCollectionInterface;
use BackgroundTasks\SimpleTaskInterface;
use BackgroundTasks\ComplexTaskInterface;
use Psr\Log\LoggerInterface;
use Psr\Log\NullLogger;

class PleskTaskManager implements TaskManagerInterface
{
    /**
     * @var LoggerInterface
     */
    private $logger;

    /**
     * @var BackgroundTasksCollectionInterface
     */
    private $backgroundTasksCollection;

    public function __construct(BackgroundTasksCollectionInterface $backgroundTasksCollection, LoggerInterface $logger = null)
    {
        $this->logger = $logger ?: new NullLogger();
        $this->backgroundTasksCollection = $backgroundTasksCollection;
    }

    /**
     * @param SimpleTaskInterface $task
     * @param array $parameters
     * @return int started task ID which could be used to track its progress
     * @throws \pm_Exception
     */
    public function startSimpleTask(SimpleTaskInterface $task, array $parameters = [])
    {
        $this->logger->debug("Start background task {task} with parameters: {parameters}", [
            'task' => get_class($task),
            'parameters' => var_export($parameters, true)
        ]);
        $taskManager = new \pm_LongTask_Manager();
        $pleskAdapter = new PleskSimpleTaskAdapter($task);
        $pleskAdapter->getTaskDataStorage()->setPrivateParam(TaskDataStorageInterface::INITIAL_TASK_PARAMETERS, $parameters);
        return $taskManager->start($pleskAdapter)->getInstanceId();
    }

    /**
     * @param ComplexTaskInterface $task
     * @param array $parameters
     * @return int started task ID which could be used to track its progress
     * @throws \pm_Exception
     */
    public function startTaskWithSteps(ComplexTaskInterface $task, array $parameters = [])
    {
        $this->logger->debug("Start multi-steps background task {task} with parameters: {parameters}", [
            'task' => get_class($task),
            'parameters' => var_export($parameters, true)
        ]);
        $taskManager = new \pm_LongTask_Manager();
        $pleskAdapter = new PleskComplexTaskAdapter($task);
        $pleskAdapter->getTaskDataStorage()->setPrivateParam(TaskDataStorageInterface::INITIAL_TASK_PARAMETERS, $parameters);
        return $taskManager->start($pleskAdapter)->getInstanceId();
    }

    /**
     * @param int $id
     * @param string $code
     * @return array|null
     */
    public function getTaskInfo($id, $code)
    {
        // TODO: candidate to another "service" like a "TaskTransformer::transform(TransformableTask $task): array"
        $task = $this->getTask($id, $code);
        if (is_null($task)) {
            return null;
        }

        /** @var ComplexTaskInterface|SimpleTaskInterface $executableTask */
        $executableTask = $task->getExecutableTask();
        $taskDataStorage = $task->getTaskDataStorage();

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

        $errors = $taskDataStorage->getErrors();
        $unhandledError = $this->getUnhandledError($task, $errors);
        if (!is_null($unhandledError)) {
            $errors[] = $unhandledError;
        }

        return [
            'id' => $task->getInstanceId(),
            'code' => $executableTask->getCode(),
            'title' => $task->statusMessage(),
            'status' => $task->getStatus(),
            'progress' => $task->getProgress(),
            'steps' => $steps,
            'publicParams' => $taskDataStorage->getPublicParams(),
            'errors' => $errors,
        ];
    }

    public function getAll(): array
    {
        $taskIds = array_map(function (BaseTaskInterface $task) {
            return $task->getCode();
        }, $this->backgroundTasksCollection->getAll());

        $tasks = [];
        $manager = new \pm_LongTask_Manager();
        foreach ($manager->getTasks($taskIds) as $task) {
            /** @var PleskBaseTaskAdapter $task */
            $tasks[] = $this->getTaskInfo($task->getInstanceId(), $task->getExecutableTask()->getCode());
        }
        return $tasks;
    }

    public function delete(int $id, string $code): void
    {
        $task = $this->getTask($id, $code);
        if (is_null($task)) {
            return;
        }

        $taskManager = new \pm_LongTask_Manager();
        $taskManager->cancel($task);
    }

    /**
     * @param int $id
     * @param string $code
     * @return PleskBaseTaskAdapter|null
     */
    private function getTask($id, $code)
    {
        $tasks = array_filter($this->getTasksByCode($code), function (PleskBaseTaskAdapter $task) use ($id) {
            return (int)$task->getInstanceId() === (int)$id;
        });

        if (empty($tasks)) {
            return null;
        }

        return array_shift($tasks);
    }

    /**
     * @param string $code
     * @return PleskBaseTaskAdapter[]
     */
    private function getTasksByCode($code)
    {
        $taskManager = new \pm_LongTask_Manager();
        /** @noinspection PhpIncompatibleReturnTypeInspection */
        return $taskManager->getTasks([$code]);
    }

    /**
     * @param PleskBaseTaskAdapter $task
     * @param array $errors
     * @return string|null
     */
    private function getUnhandledError(PleskBaseTaskAdapter $task, array $errors)
    {
        try {
            /** @var \Db_Table_Row_LongTask $taskRow */
            $taskRow = $task->getTask();
            $progressParams = $taskRow->getProgressParams();
            if (!is_array($progressParams) || !isset($progressParams['errorMessage'])) {
                return null;
            }

            $lastError = end($errors);
            if (trim($lastError) === trim($progressParams['errorMessage'])) {
                return null;
            }

            return $progressParams['errorMessage'];
        } catch (\Exception $exception) {
            return null;
        }
    }

    public function getTaskDataStorage(int $id, string $code): ?TaskDataStorageInterface
    {
        $task = $this->getTask($id, $code);
        if ($task === null) {
            return null;
        }
        return $task->getTaskDataStorage();
    }
}
