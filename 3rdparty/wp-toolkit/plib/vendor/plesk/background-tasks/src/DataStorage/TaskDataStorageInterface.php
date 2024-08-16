<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTasks\DataStorage;

interface TaskDataStorageInterface
{
    const INITIAL_TASK_PARAMETERS = 'initialTaskParameters';
    const ERRORS = 'errors';

    /**
     * @param string $name
     * @param mixed $value
     */
    public function setPrivateParam($name, $value);

    /**
     * @param string $name
     * @param mixed $default
     * @return mixed
     */
    public function getPrivateParam($name, $default = null);

    /**
     * @return array
     */
    public function getPrivateParams();

    /**
     * Set parameter which should be passed to frontend
     *
     * @param string $name
     * @param mixed $value
     */
    public function setPublicParam($name, $value);

    /**
     * Get value of parameter which should be passed to frontend
     *
     * @param string $name
     * @param mixed $default
     * @return mixed
     */
    public function getPublicParam($name, $default = null);

    /**
     * @return array
     */
    public function getPublicParams();

    /**
     * @return array
     */
    public function getInitialTaskParams();

    /**
     * @param string $name
     * @param mixed $default
     * @return mixed
     */
    public function getInitialTaskParam($name, $default = null);

    /**
     * @param string $error
     */
    public function addError($error);

    /**
     * @return string[]
     */
    public function getErrors();
}
