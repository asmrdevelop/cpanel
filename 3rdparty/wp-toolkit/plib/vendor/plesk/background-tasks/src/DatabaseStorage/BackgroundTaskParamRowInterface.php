<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DatabaseStorage;

interface BackgroundTaskParamRowInterface
{
    public function setTaskId(int $taskId): self;

    /**
     * @param mixed $value
     * @return $this
     */
    public function setValue($value): self;

    /**
     * @return mixed
     */
    public function getValue();

    public function setName(string $name): self;

    public function getName(): string;

    public function save();
}
