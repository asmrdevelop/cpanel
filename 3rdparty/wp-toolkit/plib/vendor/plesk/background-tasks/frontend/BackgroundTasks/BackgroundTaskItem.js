// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

import { Component, Fragment, createElement } from 'react';
import PropTypes from 'prop-types';
import {
    Grid,
    GridCol,
    Icon,
    Text,
    Action,
    ProgressStep,
    Translate,
} from '@plesk/ui-library';
import { CLS_PREFIX } from '../constants';
import { isBackgroundTaskCompleted, isBackgroundTaskDone, isBackgroundTaskFailed } from '../helper';

import './BackgroundTaskItem.less';

class BackgroundTaskItem extends Component {
    renderStatusIcon = task => {
        if (!isBackgroundTaskCompleted(task)) {
            return <Icon name="reload" animation="spin" intent="info" />;
        }
        if (isBackgroundTaskFailed(task)) {
            return <Icon name="cross-mark-circle-filled" intent="danger" />;
        }
        if (task.errors.length > 0) {
            return <Icon name="check-mark-circle-filled" intent="warning" />;
        }
        return <Icon name="check-mark-circle-filled" intent="success" />;
    };

    renderDetails = task => {
        const {
            baseClassName,
            onShowDetails,
        } = this.props;

        if (!isBackgroundTaskCompleted(task)) {
            const hasSteps = Object.keys(task.steps).length > 0;
            return (
                <Fragment>
                    {task.title}
                    <ProgressStep className={`${baseClassName}__progress-bar`} progress={task.progress} status={task.status} />
                    <div className={`${baseClassName}__progress-footer`}>
                        {hasSteps && (
                            <div className={`${baseClassName}__progress-control`}>
                                <Action onClick={() => onShowDetails(task)}>
                                    <Translate content="backgroundTasks.showDetails" fallback="show details" />
                                </Action>
                            </div>
                        )}
                        <Translate
                            content="backgroundTasks.completedProgress"
                            params={{ progress: task.progress }}
                            fallback="%%progress%%% completed"
                        />
                    </div>
                </Fragment>
            );
        }

        if (isBackgroundTaskDone(task) && task.errors.length === 0) {
            return task.title;
        }

        return (
            <Fragment>
                <Text>{task.title}</Text>
                <br />
                <Text className={`${baseClassName}__errors`}>
                    {task.errors.map(error => (
                        <span key={error}>
                            {error}
                            <br />
                        </span>
                    ))}
                </Text>
            </Fragment>
        );
    };

    renderAction = task => {
        if (!isBackgroundTaskCompleted(task)) {
            return null;
        }

        const {
            onClose,
        } = this.props;
        return <Action icon="cross-mark" onClick={() => onClose(task)} />;
    };

    render() {
        const {
            task,
            baseClassName,
        } = this.props;

        if (!isBackgroundTaskCompleted(task)) {
            return (
                <div className={baseClassName}>
                    <Grid xs={1}>
                        <GridCol xs={12}>
                            {this.renderDetails(task)}
                        </GridCol>
                    </Grid>
                </div>
            );
        }

        return (
            <div className={baseClassName}>
                <Grid xs={3}>
                    <GridCol xs={1}>
                        {this.renderStatusIcon(task)}
                    </GridCol>
                    <GridCol xs={10}>
                        {this.renderDetails(task)}
                    </GridCol>
                    <GridCol xs={1} className={`${baseClassName}__action`}>
                        {this.renderAction(task)}
                    </GridCol>
                </Grid>
            </div>
        );
    }
}

BackgroundTaskItem.propTypes = {
    task: PropTypes.object.isRequired,
    onClose: PropTypes.func.isRequired,
    onShowDetails: PropTypes.func.isRequired,
    baseClassName: PropTypes.string,
};

BackgroundTaskItem.defaultProps = {
    baseClassName: `${CLS_PREFIX}background-task-item`,
};

export default BackgroundTaskItem;
