<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Progress;

interface StepProgressInterface extends ProgressInterface
{
    const CURRENT_STEP_PROGRESS = 'currentStepProgress';
    const CURRENT_STEP_HINT = 'currentStepText';

    /**
     * @param string $text
     */
    public function setHint($text);
}
