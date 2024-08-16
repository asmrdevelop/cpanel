<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Adapter;

use BackgroundTasks\DataStorage\PleskTaskDataStorage;
use BackgroundTasks\Helper\StepHelper;
use BackgroundTasks\Progress\StepProgressInterface;
use BackgroundTasks\ComplexTaskInterface;
use BackgroundTasks\Step\StepMetaInfo;
use Psr\Log\LoggerInterface;
use Psr\Log\NullLogger;

class PleskComplexTaskAdapter extends PleskBaseTaskAdapter
{
    /**
     * @var ComplexTaskInterface
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

    /**
     * @param ComplexTaskInterface $task
     * @param LoggerInterface|null $logger
     */
    public function __construct(ComplexTaskInterface $task, LoggerInterface $logger = null)
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

        $taskDataStorage = $this->getTaskDataStorage();
        $steps = $this->task->getSteps($taskDataStorage);
        $stepsCount = count(StepHelper::getVisibleSteps($steps));
        $progressPerStep = 100 / ($stepsCount > 0 ? $stepsCount : 1);
        $isTaskProgressControlledManually = $this->task->getExecutionOptions()->isTaskProgressControlledManually();

        foreach ($steps as $step) {
            $this->logger->debug('Start step {step} of background task {taskName} #{taskId}', [
                'step' => get_class($step),
                'taskName' => get_class($this->task),
                'taskId' => $this->getInstanceId()
            ]);

            // Set initial values, so data from previous step doesn't affect current one
            $taskDataStorage->setPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, -1);
            $taskDataStorage->setPrivateParam(StepProgressInterface::CURRENT_STEP_HINT, '');

            $step->run(
                new PleskStepProgressAdapter($taskDataStorage),
                new PleskTaskProgressAdapter($this, $isTaskProgressControlledManually),
                $taskDataStorage
            );

            $stepProgress = $taskDataStorage->getPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, -1);
            if ($stepProgress >= 0) {
                $taskDataStorage->setPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, 100);
            }

            if (!$step->isHidden() && !$isTaskProgressControlledManually) {
                $this->setProgress($this->getProgress() + $progressPerStep);
            }

            $this->logger->debug('Step {step} of background task {taskName} #{taskId} has finished', [
                'step' => get_class($step),
                'taskName' => get_class($this->task),
                'taskId' => $this->getInstanceId()
            ]);
        }

        $this->logger->debug('Background task {taskName} #{taskId} has finished', [
            'taskName' => get_class($this->task),
            'taskId' => $this->getInstanceId()
        ]);

        $this->setProgress(100);
    }

    /**
     * @return array
     */
    public function getSteps()
    {
        $taskDataStorage = $this->getTaskDataStorage();

        try {
            $stepsMetaInfo = StepHelper::getStepsMetaInfo(
                $this->task->getSteps($taskDataStorage),
                $taskDataStorage,
                $this->getProgress(),
                $this->getStatus()
            );

            return array_map(function (StepMetaInfo $stepMetaInfo) {
                return [
                    'id' => $stepMetaInfo->getCode(),
                    'icon' => $stepMetaInfo->getIcon(),
                    'title' => $stepMetaInfo->getTitle(),
                    'progress' => $stepMetaInfo->getProgress(),
                    'status' => $stepMetaInfo->getStatus(),
                    'progressStatus' => $stepMetaInfo->getHint(),
                ];
            }, $stepsMetaInfo);
        } catch (\Exception $exception) {
            $this->logger->error('Unable to receive steps from task. Reason: {exception}', [
                'exception' => $exception,
            ]);
        }
        return [];
    }

    /**
     * @return ComplexTaskInterface
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
