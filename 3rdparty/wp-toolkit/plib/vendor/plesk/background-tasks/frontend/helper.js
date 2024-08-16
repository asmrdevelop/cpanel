// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

import { BACKGROUND_TASK_STATUS } from './constants';

export const isBackgroundTaskCompleted = task => task && [
    BACKGROUND_TASK_STATUS.CANCELED,
    BACKGROUND_TASK_STATUS.ERROR,
    BACKGROUND_TASK_STATUS.DONE,
].includes(task.status);

export const isBackgroundTaskDone = task => task && task.status === BACKGROUND_TASK_STATUS.DONE;

export const isBackgroundTaskFailed = task => task && task.status === BACKGROUND_TASK_STATUS.ERROR;

export const getBackgroundTask = (id, tasks) => tasks.find(task => task.id === id);

export const convertStepsForProgressInDrawer = steps => Object.keys(steps).map(stepName => {
    const step = steps[stepName];
    return {
        ...step,
        stepName,
    };
});

export const getIntent = task => {
    if (task.status === BACKGROUND_TASK_STATUS.ERROR) {
        return 'danger';
    }
    return 'warning';
};
