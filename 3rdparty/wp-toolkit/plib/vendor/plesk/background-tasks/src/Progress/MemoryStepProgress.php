<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Progress;

class MemoryStepProgress implements StepProgressInterface
{
    /**
     * @var float|int
     */
    private $progress = 0;

    /**
     * @var string
     */
    private $hint;

    /**
     * @param float|int $progress
     */
    public function setProgress($progress)
    {
        $this->progress = $progress;
    }

    /**
     * @param string $text
     */
    public function setHint($text)
    {
        $this->hint = $text;
    }
}
