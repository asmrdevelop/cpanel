<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DataStorage;

class MemoryTaskDataStorage implements TaskDataStorageInterface
{
    /**
     * @var array
     */
    private $privateParams = [];

    /**
     * @var array
     */
    private $publicParams = [];

    /**
     * @var array
     */
    private $initialTaskParameters;

    /**
     * @var string[]
     */
    private $errors = [];

    public function __construct(array $initialTaskParameters)
    {
        $this->initialTaskParameters = $initialTaskParameters;
    }

    /**
     * @param string $name
     * @param mixed $value
     */
    public function setPrivateParam($name, $value)
    {
        $this->privateParams[$name] = $value;
    }

    /**
     * @param string $name
     * @param mixed $default
     * @return mixed
     */
    public function getPrivateParam($name, $default = null)
    {
        if (isset($this->privateParams[$name])) {
            return $this->privateParams[$name];
        }

        return $default;
    }

    /**
     * @return array
     */
    public function getPrivateParams()
    {
        return $this->privateParams;
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
        if (isset($this->publicParams[$name])) {
            return $this->publicParams[$name];
        }

        return $default;
    }

    /**
     * @return array
     */
    public function getPublicParams()
    {
        return $this->publicParams;
    }

    /**
     * Set parameter which should be passed to frontend
     *
     * @param string $name
     * @param mixed $value
     */
    public function setPublicParam($name, $value)
    {
        $this->publicParams[$name] = $value;
    }

    /**
     * @return array
     */
    public function getInitialTaskParams()
    {
        return $this->initialTaskParameters;
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
        $this->errors[] = $error;
    }

    /**
     * @return string[]
     */
    public function getErrors()
    {
        return $this->errors;
    }
}
