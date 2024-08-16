import { Component, Fragment, createElement } from 'react';
export { Component, Fragment, createElement } from 'react';
import PropTypes from 'prop-types';
import { Grid, GridCol, Icon, Text, Action, ProgressStep, Translate, Dialog, Progress, Alert } from '@plesk/ui-library';
import { connect } from 'react-redux';
import classNames from 'classnames';

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

var BACKGROUND_TASK_STATUS = {
    NOT_STARTED: 'not_started',
    STARTED: 'started',
    RUNNING: 'running',
    // TODO: currently isn't used in back-end
    CANCELED: 'canceled',
    ERROR: 'error',
    DONE: 'done'
};

var BACKGROUND_TASK_STEP_STATUS = {
    NOT_STARTED: 'not_started',
    STARTED: 'started',
    RUNNING: 'running',
    CANCELED: 'canceled',
    ERROR: 'error',
    DONE: 'done'
};

var BACKGROUND_TASK_POLLING_TIMEOUT = 2000;

var BACKGROUND_TASK_ACTIONS = {
    ADD: 'backgroundTask/ADD',
    UPDATE: 'backgroundTask/UPDATE',
    POLL: 'backgroundTask/POLL',
    REMOVE: 'backgroundTask/REMOVE'
};

var RESPONSE_STATUS_ERROR = 'error';

var CLS_PREFIX = 'background-tasks-';

var classCallCheck = function (instance, Constructor) {
  if (!(instance instanceof Constructor)) {
    throw new TypeError("Cannot call a class as a function");
  }
};

var createClass = function () {
  function defineProperties(target, props) {
    for (var i = 0; i < props.length; i++) {
      var descriptor = props[i];
      descriptor.enumerable = descriptor.enumerable || false;
      descriptor.configurable = true;
      if ("value" in descriptor) descriptor.writable = true;
      Object.defineProperty(target, descriptor.key, descriptor);
    }
  }

  return function (Constructor, protoProps, staticProps) {
    if (protoProps) defineProperties(Constructor.prototype, protoProps);
    if (staticProps) defineProperties(Constructor, staticProps);
    return Constructor;
  };
}();

var defineProperty = function (obj, key, value) {
  if (key in obj) {
    Object.defineProperty(obj, key, {
      value: value,
      enumerable: true,
      configurable: true,
      writable: true
    });
  } else {
    obj[key] = value;
  }

  return obj;
};

var _extends = Object.assign || function (target) {
  for (var i = 1; i < arguments.length; i++) {
    var source = arguments[i];

    for (var key in source) {
      if (Object.prototype.hasOwnProperty.call(source, key)) {
        target[key] = source[key];
      }
    }
  }

  return target;
};

var inherits = function (subClass, superClass) {
  if (typeof superClass !== "function" && superClass !== null) {
    throw new TypeError("Super expression must either be null or a function, not " + typeof superClass);
  }

  subClass.prototype = Object.create(superClass && superClass.prototype, {
    constructor: {
      value: subClass,
      enumerable: false,
      writable: true,
      configurable: true
    }
  });
  if (superClass) Object.setPrototypeOf ? Object.setPrototypeOf(subClass, superClass) : subClass.__proto__ = superClass;
};

var possibleConstructorReturn = function (self, call) {
  if (!self) {
    throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
  }

  return call && (typeof call === "object" || typeof call === "function") ? call : self;
};

var toConsumableArray = function (arr) {
  if (Array.isArray(arr)) {
    for (var i = 0, arr2 = Array(arr.length); i < arr.length; i++) arr2[i] = arr[i];

    return arr2;
  } else {
    return Array.from(arr);
  }
};

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

var isBackgroundTaskCompleted = function isBackgroundTaskCompleted(task) {
    return task && [BACKGROUND_TASK_STATUS.CANCELED, BACKGROUND_TASK_STATUS.ERROR, BACKGROUND_TASK_STATUS.DONE].includes(task.status);
};

var isBackgroundTaskDone = function isBackgroundTaskDone(task) {
    return task && task.status === BACKGROUND_TASK_STATUS.DONE;
};

var isBackgroundTaskFailed = function isBackgroundTaskFailed(task) {
    return task && task.status === BACKGROUND_TASK_STATUS.ERROR;
};

var getBackgroundTask = function getBackgroundTask(id, tasks) {
    return tasks.find(function (task) {
        return task.id === id;
    });
};

var convertStepsForProgressInDrawer = function convertStepsForProgressInDrawer(steps) {
    return Object.keys(steps).map(function (stepName) {
        var step = steps[stepName];
        return _extends({}, step, {
            stepName: stepName
        });
    });
};

var getIntent = function getIntent(task) {
    if (task.status === BACKGROUND_TASK_STATUS.ERROR) {
        return 'danger';
    }
    return 'warning';
};

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

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
var fetchBackgroundTask = function fetchBackgroundTask(getTaskData, id, code) {
    return function (dispatch, getState) {
        return getTaskData({ id: id, code: code }).then(function (_ref) {
            var response = _ref.data;

            if (response.status === RESPONSE_STATUS_ERROR) {
                // Task not found
                return null;
            }

            var task = response.data.task;
            var tasks = getState().backgroundTasks.tasks;


            if (!tasks.some(function (existedTask) {
                return existedTask.id === task.id;
            })) {
                // If task isn't currently polled, need to start polling
                dispatch({ type: BACKGROUND_TASK_ACTIONS.POLL, task: task });
            }

            return task;
        })
        // Unhandled error
        .catch(function () {
            return null;
        });
    };
};

/**
 * @param {function} getTasksData
 * @param {Object[]} tasks
 * @param {number} tasks[].id
 * @param {string} tasks[].code
 * @returns {function(function, function): Promise<BackgroundTask[]>}
 */
var fetchBackgroundTasks = function fetchBackgroundTasks(getTasksData, tasks) {
    return function (dispatch, getState) {
        return getTasksData(tasks).then(function (_ref2) {
            var response = _ref2.data;

            if (response.status === RESPONSE_STATUS_ERROR) {
                // Tasks not found
                return [];
            }

            var tasks = response.data.tasks;
            var existedTasks = getState().backgroundTasks.tasks;


            tasks.forEach(function (task) {
                if (!existedTasks.some(function (existedTask) {
                    return existedTask.id === task.id;
                })) {
                    // If task isn't currently polled, need to start polling
                    dispatch({ type: BACKGROUND_TASK_ACTIONS.POLL, task: task });
                }
            });

            return tasks;
        })
        // Unhandled error
        .catch(function () {
            return [];
        });
    };
};

/**
 * @param {function} removeTask
 * @param {number} id
 * @param {string} code
 * @returns {function(function): Promise}
 */
var removeBackgroundTask = function removeBackgroundTask(removeTask, id, code) {
    return function (dispatch) {
        dispatch({ type: BACKGROUND_TASK_ACTIONS.REMOVE, taskId: id });
        return removeTask({ id: id, code: code });
    };
};

/**
 * @param {function} removeTasks
 * @returns {function(function, function): Promise}
 */
var removeCompletedBackgroundTasks = function removeCompletedBackgroundTasks(removeTasks) {
    return function (dispatch, getState) {
        var existedTasks = getState().backgroundTasks.tasks;


        var tasksToRemove = [];
        existedTasks.forEach(function (task) {
            if (!isBackgroundTaskCompleted(task)) {
                return;
            }
            tasksToRemove.push(task);
            dispatch({ type: BACKGROUND_TASK_ACTIONS.REMOVE, taskId: task.id });
        });
        return removeTasks(tasksToRemove);
    };
};

var pollBackgroundTasks = function pollBackgroundTasks(tasks) {
    return function (dispatch) {
        return tasks.forEach(function (task) {
            if (isBackgroundTaskCompleted(task)) {
                return;
            }
            dispatch({ type: BACKGROUND_TASK_ACTIONS.POLL, task: task });
        });
    };
};

function styleInject(css, ref) {
  if ( ref === void 0 ) ref = {};
  var insertAt = ref.insertAt;

  if (!css || typeof document === 'undefined') { return; }

  var head = document.head || document.getElementsByTagName('head')[0];
  var style = document.createElement('style');
  style.type = 'text/css';

  if (insertAt === 'top') {
    if (head.firstChild) {
      head.insertBefore(style, head.firstChild);
    } else {
      head.appendChild(style);
    }
  } else {
    head.appendChild(style);
  }

  if (style.styleSheet) {
    style.styleSheet.cssText = css;
  } else {
    style.appendChild(document.createTextNode(css));
  }
}

var css = ".background-tasks-background-task-item__action {\n  padding-left: 10px;\n}\n.background-tasks-background-task-item__errors {\n  word-wrap: break-word;\n  white-space: pre-wrap;\n}\n.background-tasks-background-task-item__progress-footer {\n  margin-top: 4px;\n  font-size: 12px;\n  color: #ccc;\n}\n.background-tasks-background-task-item__progress-control {\n  float: right;\n}\n.background-tasks-background-task-item__progress-bar div {\n  padding-left: 0;\n}\n";
styleInject(css);

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

var BackgroundTaskItem = function (_Component) {
    inherits(BackgroundTaskItem, _Component);

    function BackgroundTaskItem() {
        var _ref;

        var _temp, _this, _ret;

        classCallCheck(this, BackgroundTaskItem);

        for (var _len = arguments.length, args = Array(_len), _key = 0; _key < _len; _key++) {
            args[_key] = arguments[_key];
        }

        return _ret = (_temp = (_this = possibleConstructorReturn(this, (_ref = BackgroundTaskItem.__proto__ || Object.getPrototypeOf(BackgroundTaskItem)).call.apply(_ref, [this].concat(args))), _this), _this.renderStatusIcon = function (task) {
            if (!isBackgroundTaskCompleted(task)) {
                return createElement(Icon, { name: 'reload', animation: 'spin', intent: 'info' });
            }
            if (isBackgroundTaskFailed(task)) {
                return createElement(Icon, { name: 'cross-mark-circle-filled', intent: 'danger' });
            }
            if (task.errors.length > 0) {
                return createElement(Icon, { name: 'check-mark-circle-filled', intent: 'warning' });
            }
            return createElement(Icon, { name: 'check-mark-circle-filled', intent: 'success' });
        }, _this.renderDetails = function (task) {
            var _this$props = _this.props,
                baseClassName = _this$props.baseClassName,
                onShowDetails = _this$props.onShowDetails;


            if (!isBackgroundTaskCompleted(task)) {
                var hasSteps = Object.keys(task.steps).length > 0;
                return createElement(
                    Fragment,
                    null,
                    task.title,
                    createElement(ProgressStep, { className: baseClassName + '__progress-bar', progress: task.progress, status: task.status }),
                    createElement(
                        'div',
                        { className: baseClassName + '__progress-footer' },
                        hasSteps && createElement(
                            'div',
                            { className: baseClassName + '__progress-control' },
                            createElement(
                                Action,
                                { onClick: function onClick() {
                                        return onShowDetails(task);
                                    } },
                                createElement(Translate, { content: 'backgroundTasks.showDetails', fallback: 'show details' })
                            )
                        ),
                        createElement(Translate, {
                            content: 'backgroundTasks.completedProgress',
                            params: { progress: task.progress },
                            fallback: '%%progress%%% completed'
                        })
                    )
                );
            }

            if (isBackgroundTaskDone(task) && task.errors.length === 0) {
                return task.title;
            }

            return createElement(
                Fragment,
                null,
                createElement(
                    Text,
                    null,
                    task.title
                ),
                createElement('br', null),
                createElement(
                    Text,
                    { className: baseClassName + '__errors' },
                    task.errors.map(function (error) {
                        return createElement(
                            'span',
                            { key: error },
                            error,
                            createElement('br', null)
                        );
                    })
                )
            );
        }, _this.renderAction = function (task) {
            if (!isBackgroundTaskCompleted(task)) {
                return null;
            }

            var onClose = _this.props.onClose;

            return createElement(Action, { icon: 'cross-mark', onClick: function onClick() {
                    return onClose(task);
                } });
        }, _temp), possibleConstructorReturn(_this, _ret);
    }

    createClass(BackgroundTaskItem, [{
        key: 'render',
        value: function render() {
            var _props = this.props,
                task = _props.task,
                baseClassName = _props.baseClassName;


            if (!isBackgroundTaskCompleted(task)) {
                return createElement(
                    'div',
                    { className: baseClassName },
                    createElement(
                        Grid,
                        { xs: 1 },
                        createElement(
                            GridCol,
                            { xs: 12 },
                            this.renderDetails(task)
                        )
                    )
                );
            }

            return createElement(
                'div',
                { className: baseClassName },
                createElement(
                    Grid,
                    { xs: 3 },
                    createElement(
                        GridCol,
                        { xs: 1 },
                        this.renderStatusIcon(task)
                    ),
                    createElement(
                        GridCol,
                        { xs: 10 },
                        this.renderDetails(task)
                    ),
                    createElement(
                        GridCol,
                        { xs: 1, className: baseClassName + '__action' },
                        this.renderAction(task)
                    )
                )
            );
        }
    }]);
    return BackgroundTaskItem;
}(Component);

BackgroundTaskItem.propTypes = {
    task: PropTypes.object.isRequired,
    onClose: PropTypes.func.isRequired,
    onShowDetails: PropTypes.func.isRequired,
    baseClassName: PropTypes.string
};

BackgroundTaskItem.defaultProps = {
    baseClassName: CLS_PREFIX + 'background-task-item'
};

var css$1 = ".background-tasks-background-task-details__errors {\n  word-wrap: break-word;\n  white-space: pre-wrap;\n}\n";
styleInject(css$1);

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

var BackgroundTaskDetails = function (_Component) {
    inherits(BackgroundTaskDetails, _Component);

    function BackgroundTaskDetails() {
        var _ref;

        var _temp, _this, _ret;

        classCallCheck(this, BackgroundTaskDetails);

        for (var _len = arguments.length, args = Array(_len), _key = 0; _key < _len; _key++) {
            args[_key] = arguments[_key];
        }

        return _ret = (_temp = (_this = possibleConstructorReturn(this, (_ref = BackgroundTaskDetails.__proto__ || Object.getPrototypeOf(BackgroundTaskDetails)).call.apply(_ref, [this].concat(args))), _this), _this.isErrorsVisible = function () {
            var task = _this.props.task;

            return isBackgroundTaskCompleted(task) && task.errors.length > 0;
        }, _temp), possibleConstructorReturn(_this, _ret);
    }

    createClass(BackgroundTaskDetails, [{
        key: 'render',
        value: function render() {
            var _props = this.props,
                task = _props.task,
                onClose = _props.onClose,
                baseClassName = _props.baseClassName;


            var steps = [];
            Object.keys(task.steps).forEach(function (stepCode) {
                var step = task.steps[stepCode];
                if (!step) {
                    return;
                }

                var progressStep = createElement(
                    ProgressStep,
                    {
                        key: stepCode,
                        title: step.title,
                        status: step.status,
                        progress: step.progress
                    },
                    isBackgroundTaskCompleted(task) === false && step.hint
                );
                steps.push(progressStep);
            });

            return createElement(
                Dialog,
                {
                    actions: [createElement(
                        Action,
                        { key: 'minimize', onClick: onClose },
                        createElement(Translate, { content: 'backgroundTasks.minimizeDetails', fallback: 'minimize' })
                    )],
                    className: baseClassName,
                    title: task.title,
                    size: 'xs',
                    onClose: onClose,
                    closable: false,
                    isOpen: true
                },
                createElement(
                    Progress,
                    { className: baseClassName + '__content' },
                    steps
                ),
                this.isErrorsVisible() && createElement(
                    Alert,
                    { className: baseClassName + '__errors', intent: getIntent(task) },
                    task.errors.map(function (error) {
                        return createElement(
                            'span',
                            { key: error },
                            error,
                            createElement('br', null)
                        );
                    })
                )
            );
        }
    }]);
    return BackgroundTaskDetails;
}(Component);

BackgroundTaskDetails.propTypes = {
    task: PropTypes.object.isRequired,
    onClose: PropTypes.func.isRequired,
    baseClassName: PropTypes.string
};

BackgroundTaskDetails.defaultProps = {
    baseClassName: CLS_PREFIX + 'background-task-details'
};

var css$2 = ".background-tasks-background-tasks__container {\n  position: fixed;\n  z-index: 1000;\n  right: 10px;\n  bottom: 24px;\n  width: 328px;\n  border-radius: 2px;\n  background-color: rgba(34, 34, 34, 0.9);\n  box-shadow: 0 3px 6px rgba(0, 0, 0, 0.3);\n}\n.background-tasks-background-tasks__container--collapsed .background-tasks-background-tasks__body {\n  overflow: hidden;\n  max-height: 0;\n  opacity: 0;\n}\n.background-tasks-background-tasks__header {\n  overflow: hidden;\n  margin: 0;\n  cursor: pointer;\n  border-bottom: 1px solid #222;\n}\n.background-tasks-background-tasks__control {\n  overflow: hidden;\n  width: 16px;\n  height: 16px;\n  float: right;\n  margin: 14px 16px 14px 4px;\n}\n.background-tasks-background-tasks__title {\n  overflow: hidden;\n  position: relative;\n  z-index: 0;\n  padding: 14px 0 14px 16px;\n  font-size: 14px;\n  font-weight: 400;\n  color: #fff;\n}\n.background-tasks-background-tasks__title__icon {\n  margin-right: 5px;\n  vertical-align: top;\n}\n.background-tasks-background-tasks__title__icon:nth-child(n+2) {\n  margin-left: 5px;\n}\n.background-tasks-background-tasks__title__count {\n  display: none;\n}\n.background-tasks-background-tasks__title__text {\n  display: inline-block;\n  width: 90%;\n}\n.background-tasks-background-tasks__title--several-statuses .background-tasks-background-tasks__title__count {\n  display: inline-block;\n}\n.background-tasks-background-tasks__title--several-statuses .background-tasks-background-tasks__title__text {\n  display: none;\n}\n.background-tasks-background-tasks__body {\n  overflow: auto;\n  max-height: 370px;\n  margin: 0;\n  padding: 0;\n  transition: all 0.3s linear;\n  opacity: 1;\n}\n.background-tasks-background-tasks__list {\n  margin: 0;\n  padding: 0 0 20px;\n  list-style: none;\n}\n.background-tasks-background-tasks__item {\n  position: relative;\n  margin: 0;\n  padding: 10px 16px;\n  word-wrap: break-word;\n  color: #fff;\n}\n.background-tasks-background-tasks__hide-completed {\n  margin-left: 5px;\n  font-size: 12px;\n}\n";
styleInject(css$2);

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

var BackgroundTasksComponent = function (_Component) {
    inherits(BackgroundTasksComponent, _Component);

    function BackgroundTasksComponent(props) {
        classCallCheck(this, BackgroundTasksComponent);

        var _this = possibleConstructorReturn(this, (BackgroundTasksComponent.__proto__ || Object.getPrototypeOf(BackgroundTasksComponent)).call(this, props));

        _this.isNeedToRender = function () {
            return _this.props.tasks.length > 0;
        };

        _this.handleToggleCollaps = function () {
            return _this.setState(function (prevState) {
                return {
                    isCollapsed: !prevState.isCollapsed
                };
            });
        };

        _this.hasSeveralStatusesOrTasks = function (runningTasksCount, doneTasksCount, warningTasksCount, failedTasksCount) {
            var _reduce = [runningTasksCount, doneTasksCount, warningTasksCount, failedTasksCount].reduce(function (acc, element) {
                if (element <= 0) {
                    return acc;
                }
                if (acc.wasOneMoreThanZero || element > 1) {
                    acc.hasSeveralStatusesOrTasks = true;
                }
                acc.wasOneMoreThanZero = true;
                return acc;
            }, { hasSeveralStatusesOrTasks: false, wasOneMoreThanZero: false }),
                hasSeveralStatusesOrTasks = _reduce.hasSeveralStatusesOrTasks;

            return hasSeveralStatusesOrTasks;
        };

        _this.handleCloseItem = function (task) {
            return _this.props.removeBackgroundTask(_this.props.removeTaskApi, task.id, task.code);
        };

        _this.handleOpenDetails = function (task) {
            return _this.setState({
                showDetailsTaskId: task.id
            });
        };

        _this.handleCloseDetails = function () {
            return _this.setState({
                showDetailsTaskId: null
            });
        };

        _this.renderHideCompletedAction = function (hasSeveralStatusesOrTasks) {
            if (!hasSeveralStatusesOrTasks) {
                return null;
            }

            var _this$props = _this.props,
                baseClassName = _this$props.baseClassName,
                removeCompletedBackgroundTasks$$1 = _this$props.removeCompletedBackgroundTasks,
                removeTasksApi = _this$props.removeTasksApi;

            var handleOnClick = function handleOnClick() {
                return removeCompletedBackgroundTasks$$1(removeTasksApi);
            };
            return createElement(
                Action,
                { className: baseClassName + '__hide-completed', onClick: handleOnClick },
                createElement(Translate, { content: 'backgroundTasks.hideCompleted', fallback: 'Hide completed' })
            );
        };

        _this.renderTitle = function () {
            var _this$props2 = _this.props,
                baseClassName = _this$props2.baseClassName,
                tasks = _this$props2.tasks;


            var runningTasksCount = tasks.filter(function (task) {
                return isBackgroundTaskCompleted(task) === false;
            }).length;
            var doneTasksCount = tasks.filter(function (task) {
                return isBackgroundTaskDone(task) && task.errors.length === 0;
            }).length;
            var warningTasksCount = tasks.filter(function (task) {
                return isBackgroundTaskDone(task) && task.errors.length > 0;
            }).length;
            var failedTasksCount = tasks.filter(function (task) {
                return isBackgroundTaskFailed(task);
            }).length;

            var runningTasksTitle = null;
            if (runningTasksCount > 0) {
                runningTasksTitle = createElement(
                    Fragment,
                    null,
                    createElement(Icon, { className: baseClassName + '__title__icon', name: 'reload', animation: 'spin', intent: 'info' }),
                    createElement(Translate, {
                        content: 'backgroundTasks.tasksInProgress',
                        params: { count: runningTasksCount },
                        className: baseClassName + '__title__text',
                        fallback: 'All %%count%% tasks in progress'
                    }),
                    createElement(
                        'span',
                        { className: baseClassName + '__title__count' },
                        runningTasksCount
                    )
                );
            }

            var doneTasksTitle = null;
            if (doneTasksCount > 0) {
                doneTasksTitle = createElement(
                    Fragment,
                    null,
                    createElement(Icon, { className: baseClassName + '__title__icon', name: 'check-mark-circle-filled', intent: 'success' }),
                    createElement(Translate, {
                        content: 'backgroundTasks.tasksDone',
                        params: { count: doneTasksCount },
                        className: baseClassName + '__title__text',
                        fallback: 'All %%count%% tasks were successfully completed'
                    }),
                    createElement(
                        'span',
                        { className: baseClassName + '__title__count' },
                        doneTasksCount
                    )
                );
            }

            var warningTasksTitle = null;
            if (warningTasksCount > 0) {
                warningTasksTitle = createElement(
                    Fragment,
                    null,
                    createElement(Icon, { className: baseClassName + '__title__icon', name: 'check-mark-circle-filled', intent: 'warning' }),
                    createElement(Translate, {
                        content: 'backgroundTasks.tasksWarning',
                        params: { count: warningTasksCount },
                        className: baseClassName + '__title__text',
                        fallback: 'All %%count%% tasks was performed with errors'
                    }),
                    createElement(
                        'span',
                        { className: baseClassName + '__title__count' },
                        warningTasksCount
                    )
                );
            }

            var failedTasksTitle = null;
            if (failedTasksCount > 0) {
                failedTasksTitle = createElement(
                    Fragment,
                    null,
                    createElement(Icon, { className: baseClassName + '__title__icon', name: 'cross-mark-circle-filled', intent: 'danger' }),
                    createElement(Translate, {
                        content: 'backgroundTasks.tasksFailed',
                        params: { count: failedTasksCount },
                        className: baseClassName + '__title__text',
                        fallback: 'All %%count%% tasks failed'
                    }),
                    createElement(
                        'span',
                        { className: baseClassName + '__title__count' },
                        failedTasksCount
                    )
                );
            }

            var hasSeveralStatusesOrTasks = _this.hasSeveralStatusesOrTasks(runningTasksCount, doneTasksCount, warningTasksCount, failedTasksCount);

            return createElement(
                'div',
                {
                    className: classNames(baseClassName + '__title', defineProperty({}, baseClassName + '__title--several-statuses', hasSeveralStatusesOrTasks))
                },
                runningTasksTitle,
                doneTasksTitle,
                warningTasksTitle,
                failedTasksTitle,
                _this.renderHideCompletedAction(hasSeveralStatusesOrTasks)
            );
        };

        _this.renderTaskDetails = function () {
            var showDetailsTaskId = _this.state.showDetailsTaskId;

            if (!showDetailsTaskId) {
                return null;
            }

            var tasks = _this.props.tasks;

            var task = getBackgroundTask(showDetailsTaskId, tasks);
            if (!task) {
                return null;
            }

            return createElement(BackgroundTaskDetails, {
                task: task,
                onClose: _this.handleCloseDetails
            });
        };

        _this.state = {
            isCollapsed: false,
            showDetailsTaskId: null
        };
        return _this;
    }

    createClass(BackgroundTasksComponent, [{
        key: 'componentDidMount',
        value: function componentDidMount() {
            var _props = this.props,
                tasks = _props.tasks,
                pollBackgroundTasks$$1 = _props.pollBackgroundTasks;

            if (tasks.length === 0) {
                return;
            }

            var activeTasks = tasks.filter(function (task) {
                return !isBackgroundTaskCompleted(task);
            });
            if (activeTasks.length === 0) {
                return;
            }

            pollBackgroundTasks$$1(activeTasks);
        }

        // eslint-disable-next-line max-params

    }, {
        key: 'render',
        value: function render() {
            var _this2 = this;

            if (!this.isNeedToRender()) {
                return null;
            }

            var _props2 = this.props,
                baseClassName = _props2.baseClassName,
                tasks = _props2.tasks;
            var isCollapsed = this.state.isCollapsed;

            return createElement(
                'div',
                {
                    className: classNames(baseClassName + '__container', defineProperty({}, baseClassName + '__container--collapsed', isCollapsed))
                },
                createElement(
                    'div',
                    { className: baseClassName + '__wrapper' },
                    createElement(
                        'div',
                        { className: baseClassName + '__header', onClick: this.handleToggleCollaps },
                        createElement(
                            'div',
                            { className: baseClassName + '__control' },
                            isCollapsed ? createElement(Icon, { name: 'chevron-up', intent: 'info' }) : createElement(Icon, { name: 'chevron-down', intent: 'info' })
                        ),
                        this.renderTitle()
                    ),
                    createElement(
                        'div',
                        { className: baseClassName + '__body' },
                        createElement(
                            'ul',
                            { className: baseClassName + '__list' },
                            tasks.sort(function (taskA, taskB) {
                                return taskA.id > taskB.id ? -1 : 1;
                            }).map(function (task) {
                                return createElement(
                                    'li',
                                    { key: task.id, className: baseClassName + '__item' },
                                    createElement(BackgroundTaskItem, { task: task, onClose: _this2.handleCloseItem, onShowDetails: _this2.handleOpenDetails })
                                );
                            })
                        )
                    )
                ),
                this.renderTaskDetails()
            );
        }
    }]);
    return BackgroundTasksComponent;
}(Component);

BackgroundTasksComponent.propTypes = {
    tasks: PropTypes.arrayOf(PropTypes.shape({
        id: PropTypes.number,
        code: PropTypes.string,
        title: PropTypes.string,
        status: PropTypes.oneOf(Object.keys(BACKGROUND_TASK_STATUS).map(function (key) {
            return BACKGROUND_TASK_STATUS[key];
        })),
        progress: PropTypes.number,
        errors: PropTypes.arrayOf(PropTypes.string),
        steps: PropTypes.oneOf([PropTypes.arrayOf(PropTypes.shape({
            title: PropTypes.string,
            icon: PropTypes.string,
            progress: PropTypes.number,
            status: PropTypes.oneOf(Object.keys(BACKGROUND_TASK_STEP_STATUS).map(function (key) {
                return BACKGROUND_TASK_STEP_STATUS[key];
            })),
            hint: PropTypes.string
        })), PropTypes.objectOf(PropTypes.shape({
            title: PropTypes.string,
            icon: PropTypes.string,
            progress: PropTypes.number,
            status: PropTypes.oneOf(Object.keys(BACKGROUND_TASK_STEP_STATUS).map(function (key) {
                return BACKGROUND_TASK_STEP_STATUS[key];
            })),
            hint: PropTypes.string
        }))]),
        publicParams: PropTypes.oneOfType([PropTypes.object, PropTypes.array])
    })),
    removeTaskApi: PropTypes.func.isRequired,
    removeTasksApi: PropTypes.func.isRequired,
    removeBackgroundTask: PropTypes.func.isRequired,
    removeCompletedBackgroundTasks: PropTypes.func.isRequired,
    pollBackgroundTasks: PropTypes.func.isRequired,
    baseClassName: PropTypes.string
};

BackgroundTasksComponent.defaultProps = {
    tasks: [],
    baseClassName: CLS_PREFIX + 'background-tasks'
};

var mapStateToProps = function mapStateToProps(state) {
    return {
        tasks: state.backgroundTasks.tasks
    };
};

var mapDispatchToProps = {
    removeBackgroundTask: removeBackgroundTask,
    removeCompletedBackgroundTasks: removeCompletedBackgroundTasks,
    pollBackgroundTasks: pollBackgroundTasks
};

var BackgroundTasks = connect(mapStateToProps, mapDispatchToProps)(BackgroundTasksComponent);

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

var Poller =

/**
 * @param {CallableFunction} getTasks Callback for receiving all tasks from storage
 * @param {CallableFunction} addTask Callback for adding task to storage
 * @param {CallableFunction} updateTask Callback for updating task in storage
 * @param {CallableFunction} getTasksData Callback for receiving tasks from back-end
 * @returns {this}
 */
function Poller(getTasks, addTask, updateTask, getTasksData) {
    var _this = this;

    classCallCheck(this, Poller);

    this.startPolling = function (task) {
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
        setTimeout(function () {
            return _this.addTask(task);
        });

        if (isBackgroundTaskCompleted(task)) {
            // Task was added to store, but it is completed and we shouldn't poll
            return;
        }

        if (!_this.polling.some(function (id) {
            return id === task.id;
        })) {
            _this.polling = _this.polling.concat(task.id);
        }

        if (!_this.isPollingActive) {
            _this.isPollingActive = true;
            _this.schedulePolling();
        }
    };

    this.schedulePolling = function () {
        if (!_this.isPollingActive) {
            return;
        }

        _this.timerId = setTimeout(function () {
            _this.timerId = null;
            _this.poll();
        }, BACKGROUND_TASK_POLLING_TIMEOUT);
    };

    this.stopPolling = function () {
        _this.isPollingActive = false;
        clearTimeout(_this.timerId);
    };

    this.poll = function () {
        var tasks = _this.getTasks();

        var pollingTasks = tasks.filter(function (taskData) {
            return _this.polling.some(function (id) {
                return taskData.id === id;
            });
        });
        if (pollingTasks.length === 0) {
            _this.stopPolling();
            return;
        }

        _this.getTasksData(pollingTasks).then(function (_ref) {
            var response = _ref.data;

            if (response.status === RESPONSE_STATUS_ERROR) {
                _this.stopPolling();
                return;
            }

            response.data.tasks.forEach(function (task) {
                _this.updateTask(task);

                if (isBackgroundTaskCompleted(task)) {
                    _this.polling = _this.polling.filter(function (id) {
                        return id !== task.id;
                    });
                }
            });

            _this.schedulePolling();
        });
    };

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


/**
 * @private
 */


/**
 * @private
 */


/**
 * @private
 */
;

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

/**
 * @param {Array} actions Array of action codes which have 'task' key inside
 * @param {CallableFunction} getTasksData Callback for receiving tasks from back-end
 * @returns {function(*=): function(*): function(*=): boolean}
 */
var backgroundTasksMiddleware = function backgroundTasksMiddleware(actions, getTasksData) {
    return function (store) {
        return function (next) {
            return function (action) {
                // Will apply all changes to store, so we can work with last state
                next(action);

                var getTasks = function getTasks() {
                    return store.getState().backgroundTasks.tasks;
                };
                var addTask = function addTask(task) {
                    return store.dispatch({ type: BACKGROUND_TASK_ACTIONS.ADD, task: task });
                };
                var updateTask = function updateTask(task) {
                    return store.dispatch({ type: BACKGROUND_TASK_ACTIONS.UPDATE, task: task });
                };
                var poller = new Poller(getTasks, addTask, updateTask, getTasksData);
                var startPolling = function startPolling(task) {
                    poller.startPolling(task);

                    /**
                     * This code is necessary only for Plesk extensions.
                     * We must call update once for each task, Plesk will start
                     * polling and rendering all tasks by own mechanism.
                     */
                    if (typeof Jsw !== 'undefined') {
                        var progressBar = Jsw.getComponent('asyncProgressBarWrapper');
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
        };
    };
};

function createCommonjsModule(fn, module) {
	return module = { exports: {} }, fn(module, module.exports), module.exports;
}

var keys = createCommonjsModule(function (module, exports) {
exports = module.exports = typeof Object.keys === 'function'
  ? Object.keys : shim;

exports.shim = shim;
function shim (obj) {
  var keys = [];
  for (var key in obj) keys.push(key);
  return keys;
}
});
var keys_1 = keys.shim;

var is_arguments = createCommonjsModule(function (module, exports) {
var supportsArgumentsClass = (function(){
  return Object.prototype.toString.call(arguments)
})() == '[object Arguments]';

exports = module.exports = supportsArgumentsClass ? supported : unsupported;

exports.supported = supported;
function supported(object) {
  return Object.prototype.toString.call(object) == '[object Arguments]';
}
exports.unsupported = unsupported;
function unsupported(object){
  return object &&
    typeof object == 'object' &&
    typeof object.length == 'number' &&
    Object.prototype.hasOwnProperty.call(object, 'callee') &&
    !Object.prototype.propertyIsEnumerable.call(object, 'callee') ||
    false;
}});
var is_arguments_1 = is_arguments.supported;
var is_arguments_2 = is_arguments.unsupported;

var deepEqual_1 = createCommonjsModule(function (module) {
var pSlice = Array.prototype.slice;



var deepEqual = module.exports = function (actual, expected, opts) {
  if (!opts) opts = {};
  // 7.1. All identical values are equivalent, as determined by ===.
  if (actual === expected) {
    return true;

  } else if (actual instanceof Date && expected instanceof Date) {
    return actual.getTime() === expected.getTime();

  // 7.3. Other pairs that do not both pass typeof value == 'object',
  // equivalence is determined by ==.
  } else if (!actual || !expected || typeof actual != 'object' && typeof expected != 'object') {
    return opts.strict ? actual === expected : actual == expected;

  // 7.4. For all other Object pairs, including Array objects, equivalence is
  // determined by having the same number of owned properties (as verified
  // with Object.prototype.hasOwnProperty.call), the same set of keys
  // (although not necessarily the same order), equivalent values for every
  // corresponding key, and an identical 'prototype' property. Note: this
  // accounts for both named and indexed properties on Arrays.
  } else {
    return objEquiv(actual, expected, opts);
  }
};

function isUndefinedOrNull(value) {
  return value === null || value === undefined;
}

function isBuffer (x) {
  if (!x || typeof x !== 'object' || typeof x.length !== 'number') return false;
  if (typeof x.copy !== 'function' || typeof x.slice !== 'function') {
    return false;
  }
  if (x.length > 0 && typeof x[0] !== 'number') return false;
  return true;
}

function objEquiv(a, b, opts) {
  var i, key;
  if (isUndefinedOrNull(a) || isUndefinedOrNull(b))
    return false;
  // an identical 'prototype' property.
  if (a.prototype !== b.prototype) return false;
  //~~~I've managed to break Object.keys through screwy arguments passing.
  //   Converting to array solves the problem.
  if (is_arguments(a)) {
    if (!is_arguments(b)) {
      return false;
    }
    a = pSlice.call(a);
    b = pSlice.call(b);
    return deepEqual(a, b, opts);
  }
  if (isBuffer(a)) {
    if (!isBuffer(b)) {
      return false;
    }
    if (a.length !== b.length) return false;
    for (i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }
  try {
    var ka = keys(a),
        kb = keys(b);
  } catch (e) {//happens when one is a string literal and the other isn't
    return false;
  }
  // having the same number of owned properties (keys incorporates
  // hasOwnProperty)
  if (ka.length != kb.length)
    return false;
  //the same set of keys (although not necessarily the same order),
  ka.sort();
  kb.sort();
  //~~~cheap key test
  for (i = ka.length - 1; i >= 0; i--) {
    if (ka[i] != kb[i])
      return false;
  }
  //equivalent values for every corresponding key, and
  //~~~possibly expensive deep test
  for (i = ka.length - 1; i >= 0; i--) {
    key = ka[i];
    if (!deepEqual(a[key], b[key], opts)) return false;
  }
  return typeof a === typeof b;
}
});

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

var getBackgroundTasksReducer = function getBackgroundTasksReducer(data) {
    var initialState = {
        tasks: []
    };

    if (data.tasks !== undefined) {
        initialState.tasks = [].concat(toConsumableArray(data.tasks));
    }

    return function () {
        var state = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : initialState;
        var action = arguments[1];

        switch (action.type) {
            case BACKGROUND_TASK_ACTIONS.ADD:
                {
                    if (getBackgroundTask(action.task.id, state.tasks)) {
                        return state;
                    }
                    return _extends({}, state, {
                        tasks: state.tasks.concat(action.task)
                    });
                }
            case BACKGROUND_TASK_ACTIONS.UPDATE:
                {
                    var task = getBackgroundTask(action.task.id, state.tasks);
                    if (deepEqual_1(task, action.task, true)) {
                        return state;
                    }
                    return _extends({}, state, {
                        tasks: state.tasks.map(function (task) {
                            if (task.id !== action.task.id) {
                                return task;
                            }
                            return action.task;
                        })
                    });
                }
            case BACKGROUND_TASK_ACTIONS.REMOVE:
                {
                    var _task = getBackgroundTask(action.taskId, state.tasks);
                    if (!_task) {
                        return state;
                    }
                    return _extends({}, state, {
                        tasks: state.tasks.filter(function (task) {
                            return task.id !== action.taskId;
                        })
                    });
                }

            default:
                {
                    return state;
                }
        }
    };
};

// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

export { BackgroundTasks, backgroundTasksMiddleware, getBackgroundTasksReducer, isBackgroundTaskCompleted, isBackgroundTaskDone, isBackgroundTaskFailed, getBackgroundTask, convertStepsForProgressInDrawer, getIntent, fetchBackgroundTask, fetchBackgroundTasks, removeBackgroundTask, removeCompletedBackgroundTasks, pollBackgroundTasks };
//# sourceMappingURL=index.es.js.map
