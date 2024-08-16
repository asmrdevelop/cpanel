// Copyright 1999-2019. Plesk International GmbH. All rights reserved.
/* eslint-disable react/prefer-stateless-function */

import { Component, createElement } from 'react';
import PropTypes from 'prop-types';
import {
    Dialog,
    Progress,
    Translate,
    ProgressStep,
    Action,
    Alert,
} from '@plesk/ui-library';
import { CLS_PREFIX } from '../constants';
import { getIntent, isBackgroundTaskCompleted } from '../helper';

import './BackgroundTaskDetails.less';

class BackgroundTaskDetails extends Component {
    isErrorsVisible = () => {
        const {
            task,
        } = this.props;
        return isBackgroundTaskCompleted(task) && task.errors.length > 0;
    };

    render() {
        const {
            task,
            onClose,
            baseClassName,
        } = this.props;

        const steps = [];
        Object.keys(task.steps).forEach(stepCode => {
            const step = task.steps[stepCode];
            if (!step) {
                return;
            }

            const progressStep = (
                <ProgressStep
                    key={stepCode}
                    title={step.title}
                    status={step.status}
                    progress={step.progress}
                >
                    {isBackgroundTaskCompleted(task) === false && step.hint}
                </ProgressStep>
            );
            steps.push(progressStep);
        });

        return (
            <Dialog
                actions={[
                    <Action key="minimize" onClick={onClose}>
                        <Translate content="backgroundTasks.minimizeDetails" fallback="minimize" />
                    </Action>,
                ]}
                className={baseClassName}
                title={task.title}
                size="xs"
                onClose={onClose}
                closable={false}
                isOpen
            >
                <Progress className={`${baseClassName}__content`}>
                    {steps}
                </Progress>
                {this.isErrorsVisible() && (
                    <Alert className={`${baseClassName}__errors`} intent={getIntent(task)}>
                        {task.errors.map(error => (
                            <span key={error}>
                                {error}
                                <br />
                            </span>
                        ))}
                    </Alert>
                )}
            </Dialog>
        );
    }
}

BackgroundTaskDetails.propTypes = {
    task: PropTypes.object.isRequired,
    onClose: PropTypes.func.isRequired,
    baseClassName: PropTypes.string,
};

BackgroundTaskDetails.defaultProps = {
    baseClassName: `${CLS_PREFIX}background-task-details`,
};

export default BackgroundTaskDetails;
