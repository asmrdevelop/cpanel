<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor;

use BackgroundTasks\Adapter\SaasStepProgressAdapter;
use BackgroundTasks\Adapter\SaasTaskProgressAdapter;
use BackgroundTasks\BaseComplexTask;
use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\ComplexTaskInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskParamsBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;
use BackgroundTasks\DataStorage\SaasTaskDataStorage;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Exception\TaskHasWrongStatusException;
use BackgroundTasks\Exception\TaskNotFoundException;
use BackgroundTasks\Exception\UnknownTaskType;
use BackgroundTasks\Helper\StepHelper;
use BackgroundTasks\Model\BackgroundTasksCollectionInterface;
use BackgroundTasks\Progress\StepProgressInterface;
use BackgroundTasks\Progress\TaskProgressInterface;
use BackgroundTasks\SimpleTaskInterface;
use Psr\Log\LoggerInterface;
use Psr\Log\NullLogger;

class SaasExecutor
{
    /**
     * @var BackgroundTasksCollectionInterface
     */
    private $backgroundTasksCollection;

    /**
     * @var BackgroundTaskBrokerInterface
     */
    private $backgroundTaskBroker;

    /**
     * @var LoggerInterface
     */
    private $logger;

    /**
     * @var BackgroundTaskParamsBrokerInterface
     */
    private $backgroundTaskParamsBroker;

    public function __construct(
        BackgroundTasksCollectionInterface $backgroundTasksCollection,
        BackgroundTaskBrokerInterface $backgroundTaskBroker,
        BackgroundTaskParamsBrokerInterface $backgroundTaskParamsBroker,
        LoggerInterface $logger = null
    ) {
        $this->backgroundTasksCollection = $backgroundTasksCollection;
        $this->backgroundTaskBroker = $backgroundTaskBroker;
        $this->backgroundTaskParamsBroker = $backgroundTaskParamsBroker;
        $this->logger = $logger ?: new NullLogger();
    }

    /**
     * @param int $id
     * @throws TaskNotFoundException
     * @throws TaskHasWrongStatusException
     * @throws UnknownTaskType
     * @throws \Exception
     */
    public function execute(int $id): void
    {
        $longTask = $this->backgroundTaskBroker->getById($id);
        if (is_null($longTask)) {
            throw new TaskNotFoundException(
                "Task with id {$id} not found in database"
            );
        }

        if ($longTask->getStatus() !== BaseTaskInterface::STATUS_STARTED) {
            $expectedStatus = BaseTaskInterface::STATUS_STARTED;
            throw new TaskHasWrongStatusException(
                "Task with id {$id} must be in status {$expectedStatus}, but now it has status {$longTask->getStatus()}"
            );
        }

        $executableTask = $this->backgroundTasksCollection->getByCode($longTask->getCode());
        $taskData = new SaasTaskDataStorage($longTask, $this->backgroundTaskParamsBroker);
        if ($executableTask instanceof ComplexTaskInterface) {
            $taskProgress = new SaasTaskProgressAdapter($longTask, $executableTask->getExecutionOptions()->isTaskProgressControlledManually());
            $stepProgress = new SaasStepProgressAdapter($taskData);
            $this->executeComplexTask(
                $executableTask,
                $longTask,
                $taskData,
                $taskProgress,
                $stepProgress
            );
        } elseif ($executableTask instanceof SimpleTaskInterface) {
            $taskProgress = new SaasTaskProgressAdapter($longTask, true);
            $this->executeSimpleTask(
                $executableTask,
                $longTask,
                $taskData,
                $taskProgress
            );
        } else {
            // should never reach that code
            throw new UnknownTaskType(
                'Unknown task type'
            );
        }
    }

    /**
     * @param SimpleTaskInterface $executableTask
     * @param BackgroundTaskRowInterface $task
     * @param TaskDataStorageInterface $taskData
     * @param TaskProgressInterface $taskProgress
     */
    public function executeSimpleTask(
        SimpleTaskInterface $executableTask,
        BackgroundTaskRowInterface $task,
        TaskDataStorageInterface $taskData,
        TaskProgressInterface $taskProgress
    ) {
        try {
            $parametersString = var_export($taskData->getInitialTaskParams(), true);
            $this->logger->debug("Starting execution '{$executableTask->getCode()}' task with parameters: {$parametersString}");
            $task->setStatus(BaseComplexTask::STATUS_STARTED);

            $executableTask->onStart($taskData);
            $task->setStatus(BaseComplexTask::STATUS_RUNNING);

            $executableTask->run($taskProgress, $taskData);

            $task->setProgress(100);
            $executableTask->onDone($taskData);
            $task->setStatus(BaseComplexTask::STATUS_DONE);
        } catch (\Exception $exception) {
            $executableTask->onError($taskData, $exception);

            $this->addUniqueLastError($exception, $taskData);

            $task->setStatus(BaseComplexTask::STATUS_ERROR);
        } finally {
            $this->logger->debug("Stopping execution '{$executableTask->getCode()}' task");
        }
    }

    /**
     * @param ComplexTaskInterface $executableTask
     * @param BackgroundTaskRowInterface $task
     * @param TaskDataStorageInterface $taskData
     * @param TaskProgressInterface $taskProgress
     * @param StepProgressInterface $stepProgress
     */
    public function executeComplexTask(
        ComplexTaskInterface $executableTask,
        BackgroundTaskRowInterface $task,
        TaskDataStorageInterface $taskData,
        TaskProgressInterface $taskProgress,
        StepProgressInterface $stepProgress
    ) {
        try {
            $parametersString = var_export($taskData->getInitialTaskParams(), true);
            $this->logger->debug("Starting execution '{$executableTask->getCode()}' task with parameters: {$parametersString}");
            $task->setStatus(BaseComplexTask::STATUS_STARTED);

            $steps = $executableTask->getSteps($taskData);
            $stepsCount = count(StepHelper::getVisibleSteps($steps));
            $progressPerStep = 100 / ($stepsCount > 0 ? $stepsCount : 1);

            $executableTask->onStart($taskData);
            $task->setStatus(BaseComplexTask::STATUS_RUNNING);

            foreach ($steps as $step) {
                $this->logger->debug("Executing '{$step->getCode()}' step");

                // Set initial values, so data from previous step doesn't affect current one
                $taskData->setPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, -1);
                $taskData->setPrivateParam(StepProgressInterface::CURRENT_STEP_HINT, '');

                $step->run($stepProgress, $taskProgress, $taskData);

                $currentStepProgress = $taskData->getPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, -1);
                if ($currentStepProgress >= 0) {
                    $taskData->setPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, 100);
                }

                if (!$step->isHidden() && !$executableTask->getExecutionOptions()->isTaskProgressControlledManually()) {
                    $task->setProgress($task->getProgress() + $progressPerStep);
                }
            }

            $task->setProgress(100);
            $executableTask->onDone($taskData);
            $task->setStatus(BaseComplexTask::STATUS_DONE);
        } catch (\Exception $exception) {
            $executableTask->onError($taskData, $exception);

            $this->addUniqueLastError($exception, $taskData);

            $task->setStatus(BaseComplexTask::STATUS_ERROR);
        } finally {
            $this->logger->debug("Stopping execution '{$executableTask->getCode()}' task");
        }
    }

    /**
     * @param \Exception $exception
     * @param TaskDataStorageInterface $memoryTaskData
     */
    private function addUniqueLastError(\Exception $exception, TaskDataStorageInterface $memoryTaskData)
    {
        // Developer can catch all exceptions himself, store error in task data and throw it upper,
        // so need to check that last stored error isn't equal to current
        $errorMessage = $exception->getMessage();
        $errors = $memoryTaskData->getErrors();
        $lastError = end($errors);
        if ($lastError !== $errorMessage) {
            $memoryTaskData->addError($errorMessage);

            $this->logger->error($errorMessage);
            $this->logger->debug($exception);
        }
    }
}
