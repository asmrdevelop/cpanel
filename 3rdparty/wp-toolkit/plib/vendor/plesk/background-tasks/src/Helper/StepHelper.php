<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Helper;

use BackgroundTasks\BaseTaskInterface;
use BackgroundTasks\DataStorage\TaskDataStorageInterface;
use BackgroundTasks\Progress\StepProgressInterface;
use BackgroundTasks\Step\StepInterface;
use BackgroundTasks\Step\StepMetaInfo;

class StepHelper
{
    /**
     * @param StepInterface[] $steps
     * @param TaskDataStorageInterface $taskDataStorage
     * @param int $taskProgress
     * @param string $taskStatus
     * @return StepMetaInfo[]
     */
    public static function getStepsMetaInfo(array $steps, TaskDataStorageInterface $taskDataStorage, $taskProgress, $taskStatus)
    {
        $visibleSteps = self::getVisibleSteps($steps);
        $stepsCount = count($visibleSteps);
        $progressPerStep = ceil(100 / ($stepsCount > 0 ? $stepsCount : 1));
        $stepsProgress = 0;

        $stepsMetaInfo = [];
        foreach ($visibleSteps as $step) {
            $stepHint = '';
            if ($stepsProgress + $progressPerStep <= $taskProgress) {
                $progress = 100;
                $status = StepInterface::STATUS_DONE;
            } elseif ($stepsProgress <= $taskProgress && $stepsProgress + $progressPerStep > $taskProgress) {
                $progress = -1;
                $customProgress = $taskDataStorage->getPrivateParam(StepProgressInterface::CURRENT_STEP_PROGRESS, -1);
                if ($customProgress >= 0) {
                    $progress = $customProgress;
                }
                $customHint = $taskDataStorage->getPrivateParam(StepProgressInterface::CURRENT_STEP_HINT, '');
                if ($customHint !== '') {
                    $stepHint = $customHint;
                }
                $status = $taskStatus;
            } else {
                $progress = 0;
                if ($taskStatus === BaseTaskInterface::STATUS_ERROR) {
                    $status = StepInterface::STATUS_CANCELED;
                } else {
                    $status = StepInterface::STATUS_NOT_STARTED;
                }
            }
            $stepsProgress += $progressPerStep;

            $stepsMetaInfo[] = new StepMetaInfo(
                $step,
                $status,
                $progress,
                $stepHint
            );
        }

        return $stepsMetaInfo;
    }

    /**
     * @param StepInterface[] $steps
     * @return StepInterface[]
     */
    public static function getVisibleSteps(array $steps)
    {
        return array_filter($steps, function (StepInterface $step) {
            return !$step->isHidden();
        });
    }
}
