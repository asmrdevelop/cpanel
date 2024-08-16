// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

import { Component, Fragment, createElement } from 'react';
import PropTypes from 'prop-types';
import {
    Icon,
    Translate,
    Action,
} from '@plesk/ui-library';
import { connect } from 'react-redux';
import classNames from 'classnames';
import { BACKGROUND_TASK_STATUS, BACKGROUND_TASK_STEP_STATUS, CLS_PREFIX } from '../constants';
import {
    isBackgroundTaskCompleted,
    isBackgroundTaskDone,
    isBackgroundTaskFailed,
    getBackgroundTask,
} from '../helper';
import {
    removeBackgroundTask,
    removeCompletedBackgroundTasks,
    pollBackgroundTasks,
} from '../actions';
import BackgroundTaskItem from './BackgroundTaskItem';
import BackgroundTaskDetails from './BackgroundTaskDetails';

import './BackgroundTasks.less';

class BackgroundTasksComponent extends Component {
    constructor(props) {
        super(props);

        this.state = {
            isCollapsed: false,
            showDetailsTaskId: null,
        };
    }

    componentDidMount() {
        const {
            tasks,
            pollBackgroundTasks,
        } = this.props;
        if (tasks.length === 0) {
            return;
        }

        const activeTasks = tasks.filter(task => !isBackgroundTaskCompleted(task));
        if (activeTasks.length === 0) {
            return;
        }

        pollBackgroundTasks(activeTasks);
    }

    isNeedToRender = () => this.props.tasks.length > 0;

    handleToggleCollaps = () => this.setState(prevState => ({
        isCollapsed: !prevState.isCollapsed,
    }));

    // eslint-disable-next-line max-params
    hasSeveralStatusesOrTasks = (runningTasksCount, doneTasksCount, warningTasksCount, failedTasksCount) => {
        const {
            hasSeveralStatusesOrTasks,
        } = [runningTasksCount, doneTasksCount, warningTasksCount, failedTasksCount].reduce((acc, element) => {
            if (element <= 0) {
                return acc;
            }
            if (acc.wasOneMoreThanZero || element > 1) {
                acc.hasSeveralStatusesOrTasks = true;
            }
            acc.wasOneMoreThanZero = true;
            return acc;
        }, { hasSeveralStatusesOrTasks: false, wasOneMoreThanZero: false });
        return hasSeveralStatusesOrTasks;
    };

    handleCloseItem = task => this.props.removeBackgroundTask(this.props.removeTaskApi, task.id, task.code);

    handleOpenDetails = task => this.setState({
        showDetailsTaskId: task.id,
    });

    handleCloseDetails = () => this.setState({
        showDetailsTaskId: null,
    });

    renderHideCompletedAction = hasSeveralStatusesOrTasks => {
        if (!hasSeveralStatusesOrTasks) {
            return null;
        }

        const {
            baseClassName,
            removeCompletedBackgroundTasks,
            removeTasksApi,
        } = this.props;
        const handleOnClick = () => removeCompletedBackgroundTasks(removeTasksApi);
        return (
            <Action className={`${baseClassName}__hide-completed`} onClick={handleOnClick}>
                <Translate content="backgroundTasks.hideCompleted" fallback="Hide completed" />
            </Action>
        );
    };

    renderTitle = () => {
        const {
            baseClassName,
            tasks,
        } = this.props;

        const runningTasksCount = tasks.filter(task => isBackgroundTaskCompleted(task) === false).length;
        const doneTasksCount = tasks.filter(task => isBackgroundTaskDone(task) && task.errors.length === 0).length;
        const warningTasksCount = tasks.filter(task => isBackgroundTaskDone(task) && task.errors.length > 0).length;
        const failedTasksCount = tasks.filter(task => isBackgroundTaskFailed(task)).length;

        let runningTasksTitle = null;
        if (runningTasksCount > 0) {
            runningTasksTitle = (
                <Fragment>
                    <Icon className={`${baseClassName}__title__icon`} name="reload" animation="spin" intent="info" />
                    <Translate
                        content="backgroundTasks.tasksInProgress"
                        params={{ count: runningTasksCount }}
                        className={`${baseClassName}__title__text`}
                        fallback="All %%count%% tasks in progress"
                    />
                    <span className={`${baseClassName}__title__count`}>{runningTasksCount}</span>
                </Fragment>
            );
        }

        let doneTasksTitle = null;
        if (doneTasksCount > 0) {
            doneTasksTitle = (
                <Fragment>
                    <Icon className={`${baseClassName}__title__icon`} name="check-mark-circle-filled" intent="success" />
                    <Translate
                        content="backgroundTasks.tasksDone"
                        params={{ count: doneTasksCount }}
                        className={`${baseClassName}__title__text`}
                        fallback="All %%count%% tasks were successfully completed"
                    />
                    <span className={`${baseClassName}__title__count`}>{doneTasksCount}</span>
                </Fragment>
            );
        }

        let warningTasksTitle = null;
        if (warningTasksCount > 0) {
            warningTasksTitle = (
                <Fragment>
                    <Icon className={`${baseClassName}__title__icon`} name="check-mark-circle-filled" intent="warning" />
                    <Translate
                        content="backgroundTasks.tasksWarning"
                        params={{ count: warningTasksCount }}
                        className={`${baseClassName}__title__text`}
                        fallback="All %%count%% tasks was performed with errors"
                    />
                    <span className={`${baseClassName}__title__count`}>{warningTasksCount}</span>
                </Fragment>
            );
        }

        let failedTasksTitle = null;
        if (failedTasksCount > 0) {
            failedTasksTitle = (
                <Fragment>
                    <Icon className={`${baseClassName}__title__icon`} name="cross-mark-circle-filled" intent="danger" />
                    <Translate
                        content="backgroundTasks.tasksFailed"
                        params={{ count: failedTasksCount }}
                        className={`${baseClassName}__title__text`}
                        fallback="All %%count%% tasks failed"
                    />
                    <span className={`${baseClassName}__title__count`}>{failedTasksCount}</span>
                </Fragment>
            );
        }

        const hasSeveralStatusesOrTasks = this.hasSeveralStatusesOrTasks(runningTasksCount, doneTasksCount, warningTasksCount, failedTasksCount);

        return (
            <div
                className={classNames(
                    `${baseClassName}__title`,
                    {
                        [`${baseClassName}__title--several-statuses`]: hasSeveralStatusesOrTasks,
                    }
                )}
            >
                {runningTasksTitle}
                {doneTasksTitle}
                {warningTasksTitle}
                {failedTasksTitle}
                {this.renderHideCompletedAction(hasSeveralStatusesOrTasks)}
            </div>
        );
    };

    renderTaskDetails = () => {
        const {
            showDetailsTaskId,
        } = this.state;
        if (!showDetailsTaskId) {
            return null;
        }

        const {
            tasks,
        } = this.props;
        const task = getBackgroundTask(showDetailsTaskId, tasks);
        if (!task) {
            return null;
        }

        return (
            <BackgroundTaskDetails
                task={task}
                onClose={this.handleCloseDetails}
            />
        );
    };

    render() {
        if (!this.isNeedToRender()) {
            return null;
        }

        const {
            baseClassName,
            tasks,
        } = this.props;
        const {
            isCollapsed,
        } = this.state;
        return (
            <div
                className={classNames(
                    `${baseClassName}__container`,
                    {
                        [`${baseClassName}__container--collapsed`]: isCollapsed,
                    }
                )}
            >
                <div className={`${baseClassName}__wrapper`}>
                    <div className={`${baseClassName}__header`} onClick={this.handleToggleCollaps}>
                        <div className={`${baseClassName}__control`}>
                            {isCollapsed
                                ? <Icon name="chevron-up" intent="info" />
                                : <Icon name="chevron-down" intent="info" />
                            }
                        </div>
                        {this.renderTitle()}
                    </div>
                    <div className={`${baseClassName}__body`}>
                        <ul className={`${baseClassName}__list`}>
                            {tasks.sort((taskA, taskB) => taskA.id > taskB.id ? -1 : 1).map(task => (
                                <li key={task.id} className={`${baseClassName}__item`}>
                                    <BackgroundTaskItem task={task} onClose={this.handleCloseItem} onShowDetails={this.handleOpenDetails} />
                                </li>
                            ))}
                        </ul>
                    </div>
                </div>
                {this.renderTaskDetails()}
            </div>
        );
    }
}

BackgroundTasksComponent.propTypes = {
    tasks: PropTypes.arrayOf(
        PropTypes.shape({
            id: PropTypes.number,
            code: PropTypes.string,
            title: PropTypes.string,
            status: PropTypes.oneOf(Object.keys(BACKGROUND_TASK_STATUS).map(key => BACKGROUND_TASK_STATUS[key])),
            progress: PropTypes.number,
            errors: PropTypes.arrayOf(PropTypes.string),
            steps: PropTypes.oneOf([
                PropTypes.arrayOf(
                    PropTypes.shape({
                        title: PropTypes.string,
                        icon: PropTypes.string,
                        progress: PropTypes.number,
                        status: PropTypes.oneOf(Object.keys(BACKGROUND_TASK_STEP_STATUS).map(key => BACKGROUND_TASK_STEP_STATUS[key])),
                        hint: PropTypes.string,
                    })
                ),
                PropTypes.objectOf(
                    PropTypes.shape({
                        title: PropTypes.string,
                        icon: PropTypes.string,
                        progress: PropTypes.number,
                        status: PropTypes.oneOf(Object.keys(BACKGROUND_TASK_STEP_STATUS).map(key => BACKGROUND_TASK_STEP_STATUS[key])),
                        hint: PropTypes.string,
                    })
                ),
            ]),
            publicParams: PropTypes.oneOfType([
                PropTypes.object,
                PropTypes.array,
            ]),
        })
    ),
    removeTaskApi: PropTypes.func.isRequired,
    removeTasksApi: PropTypes.func.isRequired,
    removeBackgroundTask: PropTypes.func.isRequired,
    removeCompletedBackgroundTasks: PropTypes.func.isRequired,
    pollBackgroundTasks: PropTypes.func.isRequired,
    baseClassName: PropTypes.string,
};

BackgroundTasksComponent.defaultProps = {
    tasks: [],
    baseClassName: `${CLS_PREFIX}background-tasks`,
};

const mapStateToProps = state => ({
    tasks: state.backgroundTasks.tasks,
});

const mapDispatchToProps = {
    removeBackgroundTask,
    removeCompletedBackgroundTasks,
    pollBackgroundTasks,
};

export const BackgroundTasks = connect(mapStateToProps, mapDispatchToProps)(BackgroundTasksComponent);
