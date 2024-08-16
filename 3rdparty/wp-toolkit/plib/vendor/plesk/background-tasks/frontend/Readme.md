### Overview
Information about background tasks is stored globally at the Redux store.

Information about each background task is updated periodically by `./poller.js`.
 
Each React container could read information about each background task from the Redux store.

A special middleware is responsible for storing information (received from backend) 
about background tasks to the Redux store and starting periodical polling to keep the information up-to-date.

### Getting started: initial integration
- Combine your reducers with `./reducer.js`
- Apply middleware from `./middleware.js` to your store. 
- Add `BackgroundTasks` container to your main container (e.g. `MainContainer.js`). 
This is necessary to display tasks in UI globally:
```
render() {
    return (
        <ErrorBoundary>
            <App />
            <BackgroundTasks />
        </ErrorBoundary>
    );
}
```

### Work with background tasks in React component
Consider you have a React container with a form and a button. When you click the button, a request is sent to backend
and a new background task is started. Then the component watches for the background task status.

First, add current background task properties to component's own state (add code to `ExampleContainer.js`):
```
constructor(props) {
    super(props);
    this.state = {
        backgroundTaskId: null,
        backgroundTask: null,
    };
}
```

Then, add a "on click" handler for the button. It should dispatch an action which sends a request to backend.
The backend should start the task. Add code to `ExampleContainer.js`:
```
handleSubmitForm = formObject => {
    // 'actionForSubmittingForm' function is defined below
    actionForSubmittingForm(formObject).then(response => {
        const { status, data } = response;

        if (status === 'success') {
            // Form validation has passed, the background task has been started
            this.setState({
                // Store task ID to watch its status once it updates
                backgroundTaskId: data.task.id,
            });
        } else {
            // Handle form validation errors, and other errors before the background task is started
            this.handleFormErrors(response);
        }
    });
};
```

Add an action which actually sends a HTTP request to backend (add code to `action.js`):
```
export const actionForSubmittingForm = formObject => dispatch => {
    const formData = new FormData();
    // append data from formObject to formData

    return axios.post(formData).then(({ data: response }) => {
        if (response.status === 'success') {
            // Backend must return full task object 
            dispatch(concreteFormSubmittedSuccessfully(response.data.backgroundTask));        
        }
        return data;
    });
};

// The action below is dispatched immediately once the task is started by backend
export const concreteFormSubmittedSuccessfully = task => dispatch => dispatch({ type: CONCRETE_FORM_SUBMITTED, task });
```

To see the status of the background task in global UI, and get the actual status of the task immediately
as backend returns task data, add the following new case to middleware:
```
switch (action.type) {
    case CONCRETE_FORM_SUBMITTED: {
        poller.startPolling(action.task);
        break;
    }
}
```

To handle task progress and status in component's UI:
```
componentWillReceiveProps(nextProps) {
    const {
        backgroundTaskId,
        backgroundTask,
    } = this.state;

    if (!backgroundTaskId) {
        // No background task has been started yet
        return;
    }

    const activeTask = getBackgroundTask(backgroundTaskId, nextProps.tasks);
    if (activeTask && backgroundTask !== activeTask) {
        // The task information has been updated: for example, it 
        // finished (successfully or with failure), or a public property has
        // been updated, or task progress has been updated
    
        this.setState({
            // Store the task data to the component's state, so
            // you could use it in functions like 'render'
            backgroundTask: activeTask,
        }, () => {
            // You could check if the task has been successfully completed
            if (isBackgroundTaskDone(activeTask)) {
                // do some stuff
            } 
            
            // You could check if the task has failed
            if (isBackgroundTaskFailed(activeTask)) {
                // do some stuff
            }
            
            // You could read public properties of the task:
            if (activeTask.publicParams.customParameterFromTask) {
                // do some stuff
            }
        });
    }
}
```

If your form is inside of a `Drawer` component, you could add a progress states component, for example:
```
render() {
    return (
        ...
        <ProgressStatesInDrawer
            title={this.state.backgroundTask.title}
            steps={convertStepsForProgressInDrawer(this.state.backgroundTask.steps)}
            errors={this.getBackgroundTaskErrors(this.state.backgroundTask)}
        />
        ...
    );
}
```
