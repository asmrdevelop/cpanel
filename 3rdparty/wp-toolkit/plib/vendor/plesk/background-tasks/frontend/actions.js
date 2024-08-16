// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

import { BACKGROUND_TASK_ACTIONS, RESPONSE_STATUS_ERROR } from './constants';
import { isBackgroundTaskCompleted } from './helper';

/**
 * @typedef BackgroundTask
 * @property {number} id
 * @property {string} code
 * @property {string} title
 * @property {string} status
 * @property {number} progress
 * @property {Array} errors
 * @property {Array} steps
 * @property {Array} publicParams
 */

/**
 * @param {function} getTaskData
 * @param {number} id
 * @param {string} code
 * @returns {function(function, function): Promise<BackgroundTask | null>}
 */
export const fetchBackgroundTask = (getTaskData, id, code) => (dispatch, getState) => getTaskData({ id, code })
    .then(({ data: response }) => {
        if (response.status === RESPONSE_STATUS_ERROR) {
            // Task not found
            return null;
        }

        const {
            task,
        } = response.data;

        const {
            tasks,
        } = getState().backgroundTasks;

        if (!tasks.some(existedTask => existedTask.id === task.id)) {
            // If task isn't currently polled, need to start polling
            dispatch({ type: BACKGROUND_TASK_ACTIONS.POLL, task });
        }

        return task;
    })
    // Unhandled error
    .catch(() => null);

/**
 * @param {function} getTasksData
 * @param {Object[]} tasks
 * @param {number} tasks[].id
 * @param {string} tasks[].code
 * @returns {function(function, function): Promise<BackgroundTask[]>}
 */
export const fetchBackgroundTasks = (getTasksData, tasks) => (dispatch, getState) => getTasksData(tasks)
    .then(({ data: response }) => {
        if (response.status === RESPONSE_STATUS_ERROR) {
            // Tasks not found
            return [];
        }

        const {
            tasks,
        } = response.data;

        const {
            tasks: existedTasks,
        } = getState().backgroundTasks;

        tasks.forEach(task => {
            if (!existedTasks.some(existedTask => existedTask.id === task.id)) {
                // If task isn't currently polled, need to start polling
                dispatch({ type: BACKGROUND_TASK_ACTIONS.POLL, task });
            }
        });

        return tasks;
    })
    // Unhandled error
    .catch(() => []);

/**
 * @param {function} removeTask
 * @param {number} id
 * @param {string} code
 * @returns {function(function): Promise}
 */
export const removeBackgroundTask = (removeTask, id, code) => dispatch => {
    dispatch({ type: BACKGROUND_TASK_ACTIONS.REMOVE, taskId: id });
    return removeTask({ id, code });
};

/**
 * @param {function} removeTasks
 * @returns {function(function, function): Promise}
 */
export const removeCompletedBackgroundTasks = removeTasks => (dispatch, getState) => {
    const {
        tasks: existedTasks,
    } = getState().backgroundTasks;

    const tasksToRemove = [];
    existedTasks.forEach(task => {
        if (!isBackgroundTaskCompleted(task)) {
            return;
        }
        tasksToRemove.push(task);
        dispatch({ type: BACKGROUND_TASK_ACTIONS.REMOVE, taskId: task.id });
    });
    return removeTasks(tasksToRemove);
};

export const pollBackgroundTasks = tasks => dispatch => tasks.forEach(task => {
    if (isBackgroundTaskCompleted(task)) {
        return;
    }
    dispatch({ type: BACKGROUND_TASK_ACTIONS.POLL, task });
});
