<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\Model;

class TaskExecutionOptions
{
    /**
     * @var int
     */
    private $poolSize;

    /**
     * @var bool
     */
    private $isProgressTrackable;

    /**
     * @var bool
     */
    private $isHidden;

    /**
     * @var bool
     */
    private $isTaskProgressControlledManually;

    public function __construct()
    {
        $this->isHidden = false;
        $this->poolSize = -1;
        $this->isProgressTrackable = true;
        $this->isTaskProgressControlledManually = false;
    }

    /**
     * @return bool
     */
    public function getIsHidden()
    {
        return $this->isHidden;
    }

    /**
     * @param bool $isHidden
     * @return $this
     */
    public function setIsHidden($isHidden)
    {
        $this->isHidden = $isHidden;
        return $this;
    }

    /**
     * @return bool
     */
    public function getIsProgressTrackable()
    {
        return $this->isProgressTrackable;
    }

    /**
     * @param bool $isProgressTrackable
     * @return $this
     */
    public function setIsProgressTrackable($isProgressTrackable)
    {
        $this->isProgressTrackable = $isProgressTrackable;
        return $this;
    }

    /**
     * @return int
     */
    public function getPoolSize()
    {
        return $this->poolSize;
    }

    /**
     * @param int $poolSize
     * @return $this
     */
    public function setPoolSize($poolSize)
    {
        $this->poolSize = $poolSize;
        return $this;
    }

    /**
     * @return bool
     */
    public function isTaskProgressControlledManually()
    {
        return $this->isTaskProgressControlledManually;
    }

    /**
     * @param bool $isTaskProgressControlledManually
     * @return TaskExecutionOptions
     */
    public function setIsTaskProgressControlledManually($isTaskProgressControlledManually)
    {
        $this->isTaskProgressControlledManually = $isTaskProgressControlledManually;
        return $this;
    }
}
