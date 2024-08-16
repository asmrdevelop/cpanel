<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DataStorage;

use BackgroundTasks\DatabaseStorage\BackgroundTaskParamsBrokerInterface;
use BackgroundTasks\DatabaseStorage\BackgroundTaskRowInterface;

class SaasTaskDataStorage implements TaskDataStorageInterface
{
    const PUBLIC_PARAMETERS = 'publicParameters';

    /**
     * @var BackgroundTaskRowInterface
     */
    private $taskRow;
    /**
     * @var BackgroundTaskParamsBrokerInterface
     */
    private $taskParamsBroker;

    public function __construct(BackgroundTaskRowInterface $taskRow, BackgroundTaskParamsBrokerInterface $taskParamsBroker)
    {
        $this->taskRow = $taskRow;
        $this->taskParamsBroker = $taskParamsBroker;
    }

    /**
     * @param string $name
     * @param mixed $value
     */
    public function setPrivateParam($name, $value)
    {
        $taskId = (int)$this->taskRow->getId();
        if ($taskId === 0) {
            $this->taskRow->save();
            $taskId = (int)$this->taskRow->getId();
        }

        if ($this->taskParamsBroker->hasParameter($taskId, $name)) {
            $taskParamRow = $this->taskParamsBroker->getByName($taskId, $name);
        } else {
            $taskParamRow = $this->taskParamsBroker->createRow();
        }

        $taskParamRow
            ->setTaskId($taskId)
            ->setName($name)
            ->setValue($value)
            ->save();
    }

    /**
     * @param string $name
     * @param null $default
     * @return mixed
     */
    public function getPrivateParam($name, $default = null)
    {
        $taskId = (int)$this->taskRow->getId();
        if ($taskId === 0) {
            return $default;
        }

        if (!$this->taskParamsBroker->hasParameter($taskId, $name)) {
            return $default;
        }

        $longTaskParameter = $this->taskParamsBroker->getByName($taskId, $name);
        return $longTaskParameter->getValue();
    }

    /**
     * @return array
     */
    public function getPrivateParams()
    {
        $taskId = (int)$this->taskRow->getId();
        $parameters = [];
        if ($taskId === 0) {
            return $parameters;
        }

        foreach ($this->taskParamsBroker->getAll($taskId) as $taskParamRow) {
            if ($taskParamRow->getName() === self::PUBLIC_PARAMETERS) {
                continue;
            }

            $parameters[$taskParamRow->getName()] = $taskParamRow->getValue();
        }

        return $parameters;
    }

    /**
     * Set parameter which should be passed to frontend
     *
     * @param string $name
     * @param mixed $value
     */
    public function setPublicParam($name, $value)
    {
        $publicParams = $this->getPrivateParam(self::PUBLIC_PARAMETERS, []);
        $publicParams[$name] = $value;
        $this->setPrivateParam(self::PUBLIC_PARAMETERS, $publicParams);
    }

    /**
     * Get value of parameter which should be passed to frontend
     *
     * @param string $name
     * @param mixed $default
     * @return mixed
     */
    public function getPublicParam($name, $default = null)
    {
        $publicParams = $this->getPrivateParam(self::PUBLIC_PARAMETERS, []);
        if (!isset($publicParams[$name])) {
            return $default;
        }

        return $publicParams[$name];
    }

    /**
     * @return array
     */
    public function getPublicParams()
    {
        return (array) $this->getPrivateParam(self::PUBLIC_PARAMETERS, []);
    }

    /**
     * @return array
     */
    public function getInitialTaskParams()
    {
        return (array) $this->getPrivateParam(TaskDataStorageInterface::INITIAL_TASK_PARAMETERS, []);
    }

    /**
     * @param string $name
     * @param mixed $default
     * @return mixed
     */
    public function getInitialTaskParam($name, $default = null)
    {
        $initialTaskParams = $this->getInitialTaskParams();
        return isset($initialTaskParams[$name]) ? $initialTaskParams[$name] : $default;
    }

    /**
     * @param string $error
     */
    public function addError($error)
    {
        $this->setPrivateParam(
            TaskDataStorageInterface::ERRORS,
            array_merge($this->getErrors(), [$error])
        );
    }

    /**
     * @return string[]
     */
    public function getErrors()
    {
        return (array) $this->getPrivateParam(TaskDataStorageInterface::ERRORS, []);
    }
}
