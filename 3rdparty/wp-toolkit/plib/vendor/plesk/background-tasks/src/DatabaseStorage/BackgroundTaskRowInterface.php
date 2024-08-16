<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage;

interface BackgroundTaskRowInterface
{
    /**
     * @param string $status
     */
    public function setStatus($status);

    /**
     * @return string
     */
    public function getStatus();

    /**
     * @param int|float $progress
     */
    public function setProgress($progress);

    /**
     * @return int|float
     */
    public function getProgress();

    /**
     * @return int
     */
    public function getId();

    /**
     * @return string
     */
    public function getCode();

    /**
     * @return void
     */
    public function save();

    /**
     * @return void
     */
    public function delete();

    /**
     * @param int $pid
     */
    public function setPid($pid);

    /**
     * @return null|int
     */
    public function getPid();
}
