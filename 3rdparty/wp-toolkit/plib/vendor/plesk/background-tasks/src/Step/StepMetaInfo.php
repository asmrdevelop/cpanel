<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Step;

class StepMetaInfo
{
    /**
     * @var string
     */
    private $code;

    /**
     * @var string
     */
    private $title;

    /**
     * @var string Absolute public path
     */
    private $icon;

    /**
     * @var string
     */
    private $status;

    /**
     * @var int
     */
    private $progress;

    /**
     * @var string
     */
    private $hint;

    /**
     * @param StepInterface $step
     * @param string $status
     * @param int $progress
     * @param string $hint
     */
    public function __construct(StepInterface $step, $status, $progress, $hint)
    {
        $this->code = $step->getCode();
        $this->title = $step->getTitle();
        $this->icon = $step->getIcon();
        $this->status = $status;
        $this->progress = $progress;
        $this->hint = $hint;
    }

    /**
     * @return string
     */
    public function getCode()
    {
        return $this->code;
    }

    /**
     * @return string
     */
    public function getTitle()
    {
        return $this->title;
    }

    /**
     * @return string
     */
    public function getIcon()
    {
        return $this->icon;
    }

    /**
     * @return string
     */
    public function getStatus()
    {
        return $this->status;
    }

    /**
     * @return int
     */
    public function getProgress()
    {
        return $this->progress;
    }

    /**
     * @return string
     */
    public function getHint()
    {
        return $this->hint;
    }
}
