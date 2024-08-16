<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DataStorage;

use BackgroundTasks\Adapter\PleskBaseTaskAdapter;

class PleskTaskDataStorage implements TaskDataStorageInterface
{
    const PUBLIC_PARAMS_KEY = 'publicParams';

    /**
     * @var PleskBaseTaskAdapter
     */
    private $taskAdapter;

    public function __construct(PleskBaseTaskAdapter $taskAdapter)
    {
        $this->taskAdapter = $taskAdapter;
    }

    /**
     * @param string $name
     * @param mixed $value
     */
    public function setPrivateParam($name, $value)
    {
        $this->taskAdapter->setParam($name, $value);
    }

    /**
     * @param string $name
     * @param mixed $default
     * @return mixed
     */
    public function getPrivateParam($name, $default = null)
    {
        return $this->taskAdapter->getParam($name, $default);
    }

    /**
     * @return array
     */
    public function getPrivateParams()
    {
        $privateParameters = $this->taskAdapter->getParams();
        if (isset($privateParameters[self::PUBLIC_PARAMS_KEY])) {
            unset($privateParameters[self::PUBLIC_PARAMS_KEY]);
        }
        return (array) $privateParameters;
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
        $publicParams = $this->getPrivateParam(self::PUBLIC_PARAMS_KEY, []);
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
        return (array) $this->getPrivateParam(self::PUBLIC_PARAMS_KEY, []);
    }

    /**
     * Set parameter which should be passed to frontend
     *
     * @param string $name
     * @param mixed $value
     */
    public function setPublicParam($name, $value)
    {
        $publicParams = $this->getPrivateParam(self::PUBLIC_PARAMS_KEY, []);
        $publicParams[$name] = $value;
        $this->setPrivateParam(self::PUBLIC_PARAMS_KEY, $publicParams);
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
