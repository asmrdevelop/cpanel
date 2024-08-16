// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

import { isBackgroundTaskCompleted } from './helper';
import { BACKGROUND_TASK_POLLING_TIMEOUT } from './constants';
import { RESPONSE_STATUS_ERROR } from './constants';

export default class Poller {
    static instance;

    /**
     * @param {CallableFunction} getTasks Callback for receiving all tasks from storage
     * @param {CallableFunction} addTask Callback for adding task to storage
     * @param {CallableFunction} updateTask Callback for updating task in storage
     * @param {CallableFunction} getTasksData Callback for receiving tasks from back-end
     * @returns {this}
     */
    constructor(getTasks, addTask, updateTask, getTasksData) {
        if (Poller.instance) {
            return Poller.instance;
        }

        this.getTasks = getTasks;
        this.addTask = addTask;
        this.updateTask = updateTask;
        this.getTasksData = getTasksData;

        // Ids of current polling tasks
        this.polling = [];
        this.isPollingActive = false;
        this.timerId = null;

        Poller.instance = this;
    }

    /**
     * @param {Object} task Full task object from backend
     */
    startPolling = task => {
        /**
         * Workflow:
         * componentFunction: actionSubmitInstallForm -> dispatchActionInstallStarted -> middlewareReactingOnInstallStarted -> startPolling(installTask)
         *                                            -> thenOfAction(response => componentSetState(backgroundTaskId: installTask.id))
         * componentWillReceiveProps: nextPropsInstallTask.id === state.backgroundTaskId -> update task in local state and do other stuff
         *
         * Middleware are listening for concrete actions (sync and async),
         * when such action received it call current method to save task in store and start polling.
         *
         * Task must be added to store ASAP to avoid UI problem when something started, but progress/steps is not visible yet,
         * so we must receive full task object except of just 'id' and 'code'.
         *
         * To avoid workflow problems (incorrect order of calling 'componentSetState' and 'componentWillReceiveProps')
         * when saving task to store, need to do that in setTimeout, so 'componentSetState' will be called before
         * than task will be saved in store (see more: JS event loop)
         */
        setTimeout(() => this.addTask(task));

        if (isBackgroundTaskCompleted(task)) {
            // Task was added to store, but it is completed and we shouldn't poll
            return;
        }

        if (!this.polling.some(id => id === task.id)) {
            this.polling = this.polling.concat(task.id);
        }

        if (!this.isPollingActive) {
            this.isPollingActive = true;
            this.schedulePolling();
        }
    };

    /**
     * @private
     */
    schedulePolling = () => {
        if (!this.isPollingActive) {
            return;
        }

        this.timerId = setTimeout(() => {
            this.timerId = null;
            this.poll();
        }, BACKGROUND_TASK_POLLING_TIMEOUT);
    };

    /**
     * @private
     */
    stopPolling = () => {
        this.isPollingActive = false;
        clearTimeout(this.timerId);
    };

    /**
     * @private
     */
    poll = () => {
        const tasks = this.getTasks();

        const pollingTasks = tasks.filter(taskData => this.polling.some(id => taskData.id === id));
        if (pollingTasks.length === 0) {
            this.stopPolling();
            return;
        }

        this.getTasksData(pollingTasks)
            .then(({ data: response }) => {
                if (response.status === RESPONSE_STATUS_ERROR) {
                    this.stopPolling();
                    return;
                }

                response.data.tasks.forEach(task => {
                    this.updateTask(task);

                    if (isBackgroundTaskCompleted(task)) {
                        this.polling = this.polling.filter(id => id !== task.id);
                    }
                });

                this.schedulePolling();
            });
    };
}
