<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Progress;

interface ProgressInterface
{
    /**
     * @param int|float $progress value from 0 to 100
     */
    public function setProgress($progress);
}
