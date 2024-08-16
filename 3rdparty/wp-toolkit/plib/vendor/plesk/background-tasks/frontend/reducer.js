// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

import { BACKGROUND_TASK_ACTIONS } from './constants';
import { getBackgroundTask } from './helper';
import deepEqual from 'deep-equal';

export const getBackgroundTasksReducer = data => {
    const initialState = {
        tasks: [],
    };

    if (data.tasks !== undefined) {
        initialState.tasks = [...data.tasks];
    }

    return (state = initialState, action) => {
        switch (action.type) {
            case BACKGROUND_TASK_ACTIONS.ADD: {
                if (getBackgroundTask(action.task.id, state.tasks)) {
                    return state;
                }
                return {
                    ...state,
                    tasks: state.tasks.concat(action.task),
                };
            }
            case BACKGROUND_TASK_ACTIONS.UPDATE: {
                const task = getBackgroundTask(action.task.id, state.tasks);
                if (deepEqual(task, action.task, true)) {
                    return state;
                }
                return {
                    ...state,
                    tasks: state.tasks.map(task => {
                        if (task.id !== action.task.id) {
                            return task;
                        }
                        return action.task;
                    }),
                };
            }
            case BACKGROUND_TASK_ACTIONS.REMOVE: {
                const task = getBackgroundTask(action.taskId, state.tasks);
                if (!task) {
                    return state;
                }
                return {
                    ...state,
                    tasks: state.tasks.filter(task => task.id !== action.taskId),
                };
            }

            default: {
                return state;
            }
        }
    };
};
