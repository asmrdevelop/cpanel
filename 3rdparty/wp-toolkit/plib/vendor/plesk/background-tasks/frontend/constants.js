// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

export const BACKGROUND_TASK_STATUS = {
    NOT_STARTED: 'not_started',
    STARTED: 'started',
    RUNNING: 'running',
    // TODO: currently isn't used in back-end
    CANCELED: 'canceled',
    ERROR: 'error',
    DONE: 'done',
};

export const BACKGROUND_TASK_STEP_STATUS = {
    NOT_STARTED: 'not_started',
    STARTED: 'started',
    RUNNING: 'running',
    CANCELED: 'canceled',
    ERROR: 'error',
    DONE: 'done',
};

export const BACKGROUND_TASK_POLLING_TIMEOUT = 2000;

export const BACKGROUND_TASK_ACTIONS = {
    ADD: 'backgroundTask/ADD',
    UPDATE: 'backgroundTask/UPDATE',
    POLL: 'backgroundTask/POLL',
    REMOVE: 'backgroundTask/REMOVE',
};

export const RESPONSE_STATUS_ERROR = 'error';

export const CLS_PREFIX = 'background-tasks-';
