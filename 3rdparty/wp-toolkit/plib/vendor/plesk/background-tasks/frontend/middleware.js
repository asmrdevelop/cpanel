// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

import { BACKGROUND_TASK_ACTIONS } from './constants';
import Poller from './poller';

/**
 * @param {Array} actions Array of action codes which have 'task' key inside
 * @param {CallableFunction} getTasksData Callback for receiving tasks from back-end
 * @returns {function(*=): function(*): function(*=): boolean}
 */
export const backgroundTasksMiddleware = (actions, getTasksData) => store => next => action => {
    // Will apply all changes to store, so we can work with last state
    next(action);

    const getTasks = () => store.getState().backgroundTasks.tasks;
    const addTask = task => store.dispatch({ type: BACKGROUND_TASK_ACTIONS.ADD, task });
    const updateTask = task => store.dispatch({ type: BACKGROUND_TASK_ACTIONS.UPDATE, task });
    const poller = new Poller(getTasks, addTask, updateTask, getTasksData);
    const startPolling = task => {
        poller.startPolling(task);

        /**
         * This code is necessary only for Plesk extensions.
         * We must call update once for each task, Plesk will start
         * polling and rendering all tasks by own mechanism.
         */
        if (typeof Jsw !== 'undefined') {
            const progressBar = Jsw.getComponent('asyncProgressBarWrapper');
            if (progressBar) {
                progressBar.update();
            }
        }
    };

    if (BACKGROUND_TASK_ACTIONS.POLL === action.type || actions.includes(action.type)) {
        startPolling(action.task);
    }

    return true;
};
