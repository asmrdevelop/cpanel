<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Executor;

use BackgroundTasks\ComplexTaskInterface;
use BackgroundTasks\DataStorage\MemoryTaskDataStorage;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Model\SynchronousTaskExecutionResult;
use BackgroundTasks\Progress\MemoryStepProgress;
use BackgroundTasks\Progress\MemoryTaskProgress;
use BackgroundTasks\SimpleTaskInterface;
use Psr\Log\LoggerInterface;
use Psr\Log\NullLogger;

class SynchronousExecutor
{
    /**
     * @var LoggerInterface
     */
    private $logger;

    public function __construct(LoggerInterface $logger = null)
    {
        $this->logger = $logger ?: new NullLogger();
    }

    /**
     * @param SimpleTaskInterface $task
     * @param array $parameters
     * @return SynchronousTaskExecutionResult
     */
    public function executeSimpleTask(SimpleTaskInterface $task, array $parameters = [])
    {
        $memoryTaskData = new MemoryTaskDataStorage($parameters);
        $memoryTaskProgress = new MemoryTaskProgress();

        try {
            $parametersString = var_export($parameters, true);
            $this->logger->debug("Starting execution '{$task->getCode()}' task synchronously with parameters: {$parametersString}");

            $task->onStart($memoryTaskData);
            $task->run($memoryTaskProgress, $memoryTaskData);
            $task->onDone($memoryTaskData);
        } catch (\Exception $exception) {
            $task->onError($memoryTaskData, $exception);

            $this->addUniqueLastError($exception, $memoryTaskData);
        } finally {
            $this->logger->debug("Stopping execution '{$task->getCode()}' task");
        }

        return new SynchronousTaskExecutionResult($memoryTaskData);
    }

    /**
     * @param ComplexTaskInterface $task
     * @param array $parameters
     * @return SynchronousTaskExecutionResult
     */
    public function executeComplexTask(ComplexTaskInterface $task, array $parameters = [])
    {
        $memoryTaskData = new MemoryTaskDataStorage($parameters);
        $memoryStepProgress = new MemoryStepProgress();
        $memoryTaskProgress = new MemoryTaskProgress();

        try {
            $parametersString = var_export($parameters, true);
            $this->logger->debug("Starting execution '{$task->getCode()}' task synchronously with parameters: {$parametersString}");

            $task->onStart($memoryTaskData);
            foreach ($task->getSteps($memoryTaskData) as $step) {
                $this->logger->debug("Executing '{$step->getCode()}' step");

                $step->run($memoryStepProgress, $memoryTaskProgress, $memoryTaskData);
            }
            $task->onDone($memoryTaskData);
        } catch (\Exception $exception) {
            $task->onError($memoryTaskData, $exception);

            $this->addUniqueLastError($exception, $memoryTaskData);
        } finally {
            $this->logger->debug("Stopping execution '{$task->getCode()}' task");
        }

        return new SynchronousTaskExecutionResult($memoryTaskData);
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
