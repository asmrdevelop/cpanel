<?php
// Copyright 1999-2018. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Helper;

use BackgroundTasks\Progress\TaskProgressInterface;

/**
 * Class which helps to report progress for specific long tasks which:
 * - consist of one or several steps
 * - each step should process several items, and progress of each item should be equal
 *
 * Each step is identified by ID - a string or an integer.
 *
 * First, register all steps you have with number of items that should be processed in scope of the step.
 * For example:
 * $taskProgress->setStepItemsCount('secure', 2); // we're going to secure WordPress instances on 2 domains
 * $taskProgress->setStepItemsCount('update', 5); // we're going to update WordPress instances on 5 domains
 *
 * Once a step item is processed, register that.
 * For example:
 * // Here both steps are not started
 * $taskProgress->onStepItemFinished('secure'); // WordPress instances on the 1st domain were secured
 * $taskProgress->onStepItemFinished('secure'); // WordPress instances on the 2nd domain were secured
 * // Here the 1st step will be displayed as finished
 * $taskProgress->onStepItemFinished('update'); // WordPress instances on the 1st domain were updated
 * $taskProgress->onStepItemFinished('update'); // WordPress instances on the 2nd domain were updated
 * $taskProgress->onStepItemFinished('update'); // WordPress instances on the 3rd domain were updated
 * $taskProgress->onStepItemFinished('update'); // WordPress instances on the 4th domain were updated
 * $taskProgress->onStepItemFinished('update'); // WordPress instances on the 5th domain were updated
 * // Here the 2nd step and the whole long task will be displayed as finished
 */
class TaskProgressEqualItems
{
    /**
     * @var TaskProgressInterface
     */
    private $taskProgress;

    /**
     * @var array
     */
    private $stepItemsCount;

    /**
     * @var array
     */
    private $finishedItemsCount;

    /**
     * @param TaskProgressInterface $taskProgress
     */
    public function __construct(TaskProgressInterface $taskProgress)
    {
        $this->taskProgress = $taskProgress;
        $this->stepItemsCount = [];
    }

    /**
     * @param int|string $stepId
     * @param int $itemsCount
     */
    public function setStepItemsCount($stepId, $itemsCount)
    {
        if ($itemsCount > 0) {
            $this->stepItemsCount[$stepId] = $itemsCount;
        }
    }

    /**
     * @param int|string $stepId
     */
    public function onStepItemFinished($stepId)
    {
        // For example, task should perform 2 steps on different domain sets:
        // - step #1 should secure WordPress instances on 2 domains
        // - step #2 should update WordPress instances on 5 domains
        // Here we consider that:
        // - each step takes equal progress: 50% for the 1st step, and 50% for the 2nd step.
        // - each item (domain) takes equal progress within step: for step #1 each domain takes a half of step progress,
        // so overall it takes 25% of progress, for step #2 each domain takes 1/5 of step progress which is 10% overall.
        //
        // So, progress goes in the following way:
        // no domains are processed: 0%
        // step #1, the 1st domain is processed: 25%
        // step #1, the 2nd domain is processed: 50%
        // step #2, the 1st domain is processed: 60%
        // step #2, the 2nd domain is processed: 70%
        // step #2, the 3rd domain is processed: 80%
        // step #2, the 4th domain is processed: 90%
        // step #2, the 5th domain is processed: 100%

        if (!isset($this->finishedItemsCount[$stepId])) {
            $this->finishedItemsCount[$stepId] = 0;
        }
        $this->finishedItemsCount[$stepId]++;

        $stepsCount = count($this->stepItemsCount);
        $singleStepWeight = ceil(100 / ($stepsCount > 0 ? $stepsCount : 1));

        $progress = 0;
        foreach ($this->finishedItemsCount as $stepId => $finishedCount) {
            $itemsCount = $this->stepItemsCount[$stepId];
            $progress += $finishedCount * $singleStepWeight / $itemsCount;
        }

        if ($this->taskProgress) {
            $this->taskProgress->setProgress(ceil($progress));
        }
    }
}
