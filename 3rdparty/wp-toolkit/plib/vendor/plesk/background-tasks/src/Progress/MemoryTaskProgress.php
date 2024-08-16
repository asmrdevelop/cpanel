<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Progress;

class MemoryTaskProgress implements TaskProgressInterface
{
    /**
     * @var float|int
     */
    private $progress = 0;

    /**
     * @param float|int $progress
     */
    public function setProgress($progress)
    {
        $this->progress = $progress;
    }
}
