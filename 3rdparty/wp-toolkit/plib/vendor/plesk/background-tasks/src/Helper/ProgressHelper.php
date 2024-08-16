<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Helper;

use BackgroundTasks\Progress\ProgressInterface;

class ProgressHelper
{
    /**
     * @var int
     */
    private $itemsCount;

    /**
     * @var int
     */
    private $processedItemsCount;

    /**
     * @var float
     */
    private $progressPerItem;

    /**
     * @var ProgressInterface
     */
    private $progress;

    /**
     * @param int $itemsCount
     * @param ProgressInterface $progress
     */
    public function __construct($itemsCount, ProgressInterface $progress)
    {
        $this->itemsCount = $itemsCount > 0 ? $itemsCount : 1;
        $this->progressPerItem = 100 / ($this->itemsCount > 0 ? $this->itemsCount : 1);
        $this->progress = $progress;
    }

    public function itemProcessed()
    {
        $this->processedItemsCount = $this->processedItemsCount + 1;
        $progress = ceil($this->progressPerItem * $this->processedItemsCount);
        if ($progress > 100) {
            $progress = 100;
        }
        $this->progress->setProgress($progress);
    }
}
