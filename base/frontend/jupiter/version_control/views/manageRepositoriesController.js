/*
# version_control/views/manageRepositoriesController.js      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "app/services/versionControlService",
        "app/services/sseAPIService",
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "cjt/directives/actionButtonDirective",
        "jquery-chosen",
        "angular-chosen",
        "cjt/decorators/angularChosenDecorator",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        var app = angular.module("cpanel.versionControl");
        app.value("PAGE", PAGE);

        var controller = app.controller(
            "ManageRepositoriesController",
            ["$scope", "$window", "$location", "$timeout", "versionControlService", "sseAPIService", "PAGE", "$routeParams", "alertService", "sshKeyVerification", "$q",
                function($scope, $window, $location, $timeout, versionControlService, sseAPIService, PAGE, $routeParams, alertService, sshKeyVerification, $q) {

                    var repository = this;

                    // RTL check for chosen
                    repository.isRTL = false;
                    var html = document.querySelector("html");
                    if (html) {
                        repository.isRTL = html.getAttribute("dir") === "rtl";
                    }

                    // Page defaults
                    repository.isLoading = true;

                    repository.deployInProgress = false;
                    repository.deployState = "";
                    repository.deployedTaskInformation = null;
                    repository.deployCalloutType = "info";

                    // SSE events and config
                    var deploySSEURL = "";
                    var sseObj;
                    var events = [ "log_update", "task_complete", "task_failed" ];
                    var config = { json: true };

                    var tabs = [
                        "basic-info",
                        "deploy"
                    ];

                    var tabToSelect = 0;

                    // Get the variables from the URL
                    var requestedRepoPath = decodeURIComponent($routeParams.repoPath);
                    var tabName = decodeURIComponent($routeParams.tabname);

                    selectActiveTab(tabName);

                    /**
                     * Selects Active Tab
                     * @method selectActiveTab
                     * @param {String} tabName Tab Name
                     */
                    function selectActiveTab(tabName) {

                        // Selecting tab based on route parameter
                        if (tabName) {
                            tabToSelect = tabs.indexOf(tabName);
                            if ( tabToSelect !== -1) {
                                $scope.activeTabIndex = tabToSelect;
                            } else {
                                $location.path("/list/");
                            }
                        } else {
                            $location.path("/list/");
                        }
                    }

                    retrieveRepositoryInfo(requestedRepoPath);

                    /**
                    * Changes active tab
                    *
                    * @method changeActiveTab
                    * @param {String} name name of the tab.
                    */
                    $scope.changeActiveTab = function(name) {
                        var url = $location.url();
                        var lastPart = url.split( "/" ).pop().toLowerCase();

                        if (name) {
                            $scope.activeTabIndex = tabs.indexOf(name);

                            // lastpart other than name
                            if (lastPart !== name) {
                                $location.path("/manage/" + encodeURIComponent(requestedRepoPath) + "/" + name);
                            }
                        }
                    };

                    /**
                    * Checks to see if the user came from the VersionControl List View
                    *
                    * @method retrieveRepositoryInfo
                    * @param {String} requestedRepoPath Represents the path of the repository to be loaded on the page.
                    */
                    function retrieveRepositoryInfo(requestedRepoPath) {

                        var repoInfo;
                        return versionControlService.getRepositoryInformation(requestedRepoPath, "name,tasks,clone_urls,branch,last_update,source_repository,last_deployment,deployable")
                            .then(function(response) {
                                repoInfo = response;
                                var branchPromise = _retrieveAvailableBranches(requestedRepoPath);

                                /**
                                 * If we fail to retrieve the available branches, we will let the UI
                                 * go ahead and display in its mostly broken state, while performing
                                 * this SSH key check in the background for later use with the Try
                                 * Again button.
                                 */
                                branchPromise.catch(function() {
                                    var sshServer = sshKeyVerification.getHostnameAndPort(response && response.source_repository && response.source_repository.url);
                                    if (sshServer) {
                                        repository.ssh = {};
                                        repository.ssh.hostname = sshServer.hostname;
                                        repository.ssh.port = sshServer.port;
                                        repository.ssh.promise = sshKeyVerification.verify(sshServer.hostname, sshServer.port);
                                    }
                                });

                                return branchPromise;
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "versionControl"
                                });
                                $location.path("/list/");

                            })
                            .finally(function() {
                                setFormData(repoInfo);
                                repository.isLoading = false;
                            });
                    }

                    function _retrieveAvailableBranches(requestedRepoPath) {
                        return versionControlService.getRepositoryInformation(requestedRepoPath, "available_branches")
                            .then(function(response) {
                                repository.branchList = response && response.available_branches || [];
                            }, function(error) {
                                repository.unableToRetrieveAvailableBranches = true;
                                return $q.reject(error);
                            });
                    }

                    /**
                     * We don't want to show an alert if there are issues fetching the branches during the
                     * initial page load, but if it's in response to a user action it's good to have feedback.
                     */
                    function _retrieveAvailableBranchesTryAgain() {
                        return _retrieveAvailableBranches( repository.repoPath ).catch(function() {
                            alertService.add({
                                type: "danger",
                                id: "retrieve-branches-again-error",
                                message: _.escape(LOCALE.maketext("The system cannot update information for the repository at “[_1]” because it cannot access the remote repository.", repository.repoPath)),
                                closeable: true,
                                replace: true,
                                group: "versionControl"
                            });
                        });
                    }

                    /**
                     * Changes the text for the callout that's used when unableToRetrieveAvailableBranches = true.
                     *
                     * @param  {Boolean} hasRemote   True when the repository was cloned from a remote repo.
                     */
                    $scope.$watch("repository.hasRemote", function(hasRemote) {
                        if (hasRemote) {
                            repository._noConnectionText = LOCALE.maketext("The system could not contact the remote repository.");
                            repository._tryAgainTooltipText = LOCALE.maketext("Attempt to contact the remote repository again.");
                        } else {
                            repository._noConnectionText = LOCALE.maketext("The system could not read from the repository.");
                            repository._tryAgainTooltipText = LOCALE.maketext("Attempt to read from the repository again.");
                        }
                    });

                    /**
                     * Try to fetch the list of available_branches again.
                     *
                     * @return {Promise}                    Resolves if it successfully retrieves the available branches.
                     *                                      Rejects otherwise.
                     */
                    repository.tryAgain = function tryAgain() {
                        alertService.removeById("retrieve-branches-again-error", "versionControl");
                        if (!repository.ssh.promise) {
                            return _retrieveAvailableBranchesTryAgain();
                        }

                        return repository.ssh.promise.then(
                            function success() {

                                // SSH host key verification is not the problem, so just try again
                                return _retrieveAvailableBranchesTryAgain();
                            },
                            function failure(data) {
                                repository.ssh.status = data.status;
                                repository.ssh.keys = data.keys;

                                _showKeyVerificationModal();
                            }
                        );
                    };

                    /**
                     * Opens up the modal for SSH key verification.
                     */
                    function _showKeyVerificationModal() {
                        alertService.clear(null, "versionControl");

                        repository.ssh.modal = sshKeyVerification.openModal({
                            hostname: repository.ssh.hostname,
                            port: repository.ssh.port,
                            type: repository.ssh.status,
                            keys: repository.ssh.keys,
                            onAccept: _onAcceptKey,
                        });

                        /**
                         * Handle the case where the modal is dismissed, rather than closed.
                         * Dismissal is when the user clicks the cancel button or if they click
                         * outside of the modal, causing it to disappear.
                         */
                        repository.ssh.modal.result.catch(function() {
                            alertService.add({
                                type: "danger",
                                message: _.escape(LOCALE.maketext("The system [output,strong,cannot] connect to the remote repository if you do not accept the host key for “[output,strong,_1].”", repository.ssh.hostname)),
                                closeable: true,
                                replace: true,
                                group: "versionControl",
                                id: "known-hosts-verification-cancelled",
                            });
                        });

                        return repository.ssh.modal;
                    }

                    function _onAcceptKey(promise) {
                        return promise.then(
                            function success(newStatus) {
                                repository.ssh.status = newStatus;
                                return _retrieveAvailableBranchesTryAgain();
                            },
                            function failure(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(LOCALE.maketext("The system failed to add the fingerprints from “[_1]” to the [asis,known_hosts] file: [_2]", repository.ssh.hostname, error)),
                                    closeable: true,
                                    replace: true,
                                    group: "versionControl",
                                    id: "known-hosts-verification-failure",
                                });
                            }
                        ).finally(function() {
                            repository.ssh.modal.close();
                            delete repository.ssh.modal;
                        });
                    }

                    /**
                    * Set Manage Form Data
                    *
                    * @method setFormData
                    * @param {object} data Represents the single repository data object.
                    */
                    function setFormData(data) {
                        repository.name = data.name;
                        repository.repoPath = data.repository_root;
                        repository.cloneURL = data.clone_urls.read_write[0];

                        repository.branch = data.branch;
                        repository.checkedoutBranch = data.branch;

                        repository.hasActiveBranch = data.hasActiveBranch;

                        repository.hasHeadInformation = data.hasHeadInformation;
                        repository.lastUpdateSHA = data.lastUpdateSHA;
                        repository.lastUpdateDate = data.lastUpdateDate;
                        repository.commitMessage = data.commitMessage;
                        repository.author = data.author;

                        if (data.available_branches) {
                            repository.branchList = data.available_branches;
                        }

                        repository.hasRemote = data.hasRemote;
                        repository.remoteInformation = data.source_repository;

                        repository.gitWebURL = data.gitWebURL;
                        repository.fileManagerRedirectURL = data.fileManagerRedirectURL;

                        repository.fullRepoPath = repository.repoPath;

                        repository.qaSafeSuffix = data.qaSafeSuffix;

                        repository.deployInProgress = data.deployInProgress;

                        repository.deployable = data.deployable;
                        repository.hasDeploymentInformation = data.hasDeploymentInformation;
                        repository.lastDeployedDate = data.lastDeployedDate;
                        repository.lastDeployedSHA = data.lastDeployedSHA;
                        repository.lastDeployedAuthor = data.lastDeployedAuthor;
                        repository.lastDeployedCommitDate = data.lastDeployedCommitDate;
                        repository.lastDeployedCommitMessage = data.lastDeployedCommitMessage;

                        repository.changesAvailableToDeploy = data.lastDeployedSHA !== data.lastUpdateSHA;

                        repository.deployTasks = getDeployTasks(data.tasks);

                        if (typeof sseObj === "undefined" && repository.deployInProgress) {
                            initializeSSE();
                        }
                    }

                    function getDeployTasks(tasks) {
                        var deployTasks =  _.map(tasks, function(task) {
                            if (task.action === "deploy") {
                                var timestampInfo = getDeployTimestamp(task.args.log_file);
                                return {
                                    task_id: task.task_id,
                                    log_file: task.args.log_file,
                                    sse_url: task.sse_url,
                                    timeStamp: timestampInfo,
                                    humanReadableDate: LOCALE.local_datetime(timestampInfo, "datetime_format_medium")
                                };
                            }
                        });

                        return _.sortBy(deployTasks, [function(o) {
                            return o.log_file;
                        }]);
                    }

                    /**
                     * @method getQueuedTaskString
                     * @param {Number} taskCount TaskCount
                     * @returns {String} Additional tasks display string
                     */
                    function getQueuedTaskString(taskCount) {
                        return LOCALE.maketext("[quant,_1,additional task,additional tasks] queued", taskCount);
                    }

                    /**
                     * Gets Deployment timestamp
                     * @method getDeployTimestamp
                     * @param {String} logFilePath LogFile path
                     * @returns {String} deployment timestamp
                     */
                    function getDeployTimestamp(logFilePath) {
                        var timeStamp;
                        if (logFilePath) {
                            var logFileName = logFilePath.split("/").pop();
                            timeStamp = logFileName.match(/\d+(\.\d+)/g);
                        }
                        return timeStamp[0];
                    }

                    /**
                     * Update Repository
                     * @method updateRepository
                     * @return {Promise} Returns a promise from the VersionControlService.updateRepository method for success/error handling when the user requests to update a repository.
                     */
                    repository.updateRepository = function() {

                        var branch = repository.branch === repository.checkedoutBranch ? "" : repository.branch;

                        return versionControlService.updateRepository(
                            repository.repoPath,
                            repository.name,
                            branch
                        ).then(function(response) {

                            alertService.add({
                                type: "success",
                                message: _.escape(LOCALE.maketext("The system successfully updated the “[_1]” repository.", repository.name)),
                                closeable: true,
                                replace: true,
                                autoClose: 10000,
                                group: "versionControl"
                            });

                            setFormData(response.data);

                        }, function(error) {
                            alertService.add({
                                type: "danger",
                                message: _.escape(error),
                                closeable: true,
                                replace: false,
                                group: "versionControl"
                            });
                        });
                    };

                    /**
                     * Pull from remote repository
                     * @method pullFromRemote
                     * @return {Promise} Returns a promise from the VersionControlService.updateRepository method for success/error handling when the user requests to pull from remote repository.
                     */
                    repository.pullFromRemote = function() {

                        return versionControlService.updateFromRemote(
                            repository.repoPath,
                            repository.branch
                        ).then(function(response) {

                            var data = response.data;

                            if (repository.lastUpdateSHA === data.lastUpdateSHA) {
                                alertService.add({
                                    type: "info",
                                    message: _.escape(LOCALE.maketext("The “[_1]” repository is up-to-date.", repository.name)),
                                    closeable: true,
                                    replace: true,
                                    autoClose: 10000,
                                    group: "versionControl"
                                });
                            } else {
                                alertService.add({
                                    type: "success",
                                    message: _.escape(LOCALE.maketext("The system successfully updated the “[_1]” repository.", repository.name)),
                                    closeable: true,
                                    replace: true,
                                    autoClose: 10000,
                                    group: "versionControl"
                                });

                                repository.hasHeadInformation = data.hasHeadInformation;
                                repository.lastUpdateSHA = data.lastUpdateSHA;
                                repository.lastUpdateDate = data.lastUpdateDate;
                                repository.commitMessage = data.commitMessage;
                                repository.author = data.author;

                                repository.newCommits = true;

                                $timeout( function() {
                                    repository.newCommits = false;
                                }, 10000 );
                            }
                        }, function(error) {
                            alertService.add({
                                type: "danger",
                                message: _.escape(error),
                                closeable: true,
                                replace: false,
                                group: "versionControl"
                            });
                        });
                    };

                    /**
                     * Reset deployment and sse flags
                     * @method resetSSEState
                     */
                    function resetSSEState() {
                        repository.deployState = "";
                        repository.deployCalloutType = "info";
                        repository.deployedTaskInformation = null;

                        sseObj = null;
                    }

                    /**
                     * Initialize SSE
                     * @method initializeSSE
                     */
                    function initializeSSE() {

                        repository.queuedDeployTasksCount = repository.deployTasks.length - 1;

                        if (repository.queuedDeployTasksCount) {
                            repository.queuedTaskString = getQueuedTaskString(repository.queuedDeployTasksCount);
                        }

                        repository.firstDeployTask = repository.deployTasks[0];
                        deploySSEURL = repository.firstDeployTask.sse_url;

                        repository.deployProgress = LOCALE.maketext("The deployment that you triggered on [_1] is in progress …", repository.firstDeployTask.humanReadableDate);
                        repository.deployComplete = LOCALE.maketext("The deployment that you triggered on [_1] is complete. Updating last deployment information …", repository.firstDeployTask.humanReadableDate);
                        repository.deployQueued =  LOCALE.maketext("The deployment that you triggered on [_1] is queued …", repository.firstDeployTask.humanReadableDate);
                        sseAPIService.initialize();
                    }

                    /**
                     * Handles ready.
                     *
                     * @method
                     * @param {sse:ready} event - ready event.
                     * @listens sse:ready
                     */
                    $scope.$on("sse:ready", function(event) {
                        deploySSEURL = PAGE.securityToken + deploySSEURL;
                        sseObj = sseAPIService.connect(deploySSEURL, events, config);
                    });

                    /**
                     * Handles destroy event.
                     *
                     * @method
                     * @listens $destroy
                     */
                    $scope.$on("$destroy", function() {
                        if (sseObj) {
                            sseAPIService.close(sseObj);
                        }
                    });

                    /**
                     * Handles log_update.
                     *
                     * @method
                     * @param {sse:log_update} event - Task log update event.
                     * @param {String} data - log data
                     * @listens sse:log_update
                     */
                    $scope.$on("sse:log_update", function(event, data) {
                        repository.deployState = "processing";
                        $scope.$apply();
                    });

                    /**
                     * Handles task_complete.
                     *
                     * @method
                     * @param {sse:task_complete} event - Task complete event.
                     * @param {Object} data - Data
                     * @listens sse:task_complete
                     */
                    $scope.$on("sse:task_complete", function(event, data) {
                        var taskData = data;
                        sseAPIService.close(sseObj);
                        repository.deployCalloutType = "success";
                        repository.deployState = "complete";

                        $scope.$apply();

                        $timeout(function() {
                            return versionControlService.getRepositoryInformation(repository.repoPath, "last_deployment,tasks")
                                .then(function(data) {
                                    repository.lastDeployedDate = data.lastDeployedDate;
                                    repository.lastDeployedSHA = data.lastDeployedSHA;
                                    repository.lastDeployedAuthor = data.lastDeployedAuthor;
                                    repository.lastDeployedCommitDate = data.lastDeployedCommitDate;
                                    repository.lastDeployedCommitMessage = data.lastDeployedCommitMessage;

                                    repository.hasDeploymentInformation = true;

                                    repository.changesAvailableToDeploy = data.lastDeployedSHA !== repository.lastUpdateSHA;

                                    repository.deployTasks = getDeployTasks(data.tasks);

                                    resetSSEState();

                                    if (repository.deployTasks && repository.deployTasks.length > 0) {
                                        repository.deployInProgress = true;
                                        initializeSSE();
                                    } else {
                                        repository.deployInProgress = false;
                                    }

                                    repository.newDeployCommit = true;

                                    $timeout( function() {
                                        repository.newDeployCommit = false;
                                    }, 5000 );
                                }, function(error) {

                                    // display error
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error.message),
                                        closeable: true,
                                        replace: false,
                                        group: "versionControl"
                                    });
                                });
                        }, 5000);
                    });

                    /**
                     * Handles task_failed.
                     *
                     * @method
                     * @param {sse:task_failed} event - Task failed event.
                     * @param {Object} data - Data
                     * @listens sse:task_failed
                     */
                    $scope.$on("sse:task_failed", function(event, data) {
                        sseAPIService.close(sseObj);
                        var deployedTaskInfo = repository.deployedTaskInformation;
                        var logFileInfo = getLogFileDetails(deployedTaskInfo.log_path);

                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("Error occurred while deploying.") +
                                    " " +
                                    LOCALE.maketext("You can view the log file: [output,url,_1,_2,target,_3]", logFileInfo.fileManagerURL, logFileInfo.fileName, "_blank"),
                            closeable: true,
                            replace: false,
                            group: "versionControl"
                        });

                        $scope.$apply();

                        return versionControlService.getRepositoryInformation(repository.repoPath, "tasks")
                            .then(function(data) {
                                repository.deployTasks = getDeployTasks(data.tasks);

                                resetSSEState();

                                if (repository.deployTasks && repository.deployTasks.length > 0) {
                                    repository.deployInProgress = true;
                                    initializeSSE();
                                } else {
                                    repository.deployInProgress = false;
                                }

                            }, function(error) {

                            // display error
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error.message),
                                    closeable: true,
                                    replace: false,
                                    group: "versionControl"
                                });
                            });
                    });

                    /**
                     * Get log file details
                     * @method getLogFileDetails
                     *
                     * @param {Object} logFilePath logfile path
                     * @return {Object} Log file details
                     */
                    function getLogFileDetails(logFilePath) {
                        var logFileInfo = {};

                        if (logFilePath) {

                            // construct the file manager url for log file
                            var fileName = logFilePath.split( "/" ).pop();
                            var dirPath = PAGE.homeDir + "/.cpanel/logs";
                            var fileManangerURL = PAGE.deprefix + "filemanager/showfile.html?file=" + encodeURIComponent(fileName) + "&dir=" + encodeURIComponent(dirPath);

                            logFileInfo.fileName = fileName;
                            logFileInfo.fileManagerURL =  fileManangerURL;
                        }

                        return logFileInfo;
                    }

                    /**
                     * Deploy repository
                     * @method deployRepository
                     * @return {Promise} Returns a promise from the VersionControlService.deployRepository method for success/error handling when the user requests to deploy their repository.
                     */
                    repository.deployRepository = function() {
                        return versionControlService.deployRepository(
                            repository.repoPath
                        ).then(function(response) {
                            var data = response.data || {};

                            /**
                             * We have to fake the task object, since the task data returned from the
                             * VersionControlDeployment::create and VersionControlDeployment::retrieveAPI calls don't match.
                             */
                            repository.deployTasks = getDeployTasks([
                                {
                                    action: "deploy",
                                    task_id: data.task_id,
                                    sse_url: data.sse_url,
                                    args: {
                                        log_file: data.log_path,
                                    },
                                }
                            ]);

                            if (repository.deployTasks && repository.deployTasks.length > 0) {
                                repository.deployInProgress = true;
                                initializeSSE();
                            } else {
                                repository.deployInProgress = false;
                            }

                        }, function(error) {
                            repository.deployInProgress = false;
                            alertService.add({
                                type: "danger",
                                message: _.escape(error) +
                                         " " +
                                         LOCALE.maketext("For more information, read our [output,url,_1,documentation,target,_2].", "https://go.cpanel.net/GitDeployment", "_blank"),
                                closeable: true,
                                replace: false,
                                group: "versionControl"
                            });
                        });
                    };


                    /**
                     * Back to List View
                     * @method backToListView
                     */
                    repository.backToListView = function() {
                        $location.path("/list");
                    };

                    /**
                     * Opens repository in gitWeb
                     * @method redirectToGitWeb
                     * @param {String} gitWebURL gitWebURL for the repository
                     * @param {String} repoName Repository name
                     */
                    repository.redirectToGitWeb = function(gitWebURL, repoName) {

                        if (gitWebURL) {
                            $window.open(gitWebURL, repoName + "GitWeb");
                        } else {
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("The system could not find the repository’s [asis,Gitweb] [output,acronym,URL,Universal Resource Locator]."),
                                closeable: true,
                                replace: false,
                                group: "versionControl"
                            });
                        }
                    };

                    /**
                     * Opens repository path in file manager
                     * @method redirectToFileManager
                     * @param {String} fileManagerURL file Manager url for the repository path
                     * @param {String} repoName Repository name
                     */
                    repository.redirectToFileManager = function(fileManagerURL, repoName) {

                        if (fileManagerURL) {
                            $window.open(fileManagerURL, repoName + "FileManager");
                        } else {
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("The system could not redirect you to the File Manager interface."),
                                closeable: true,
                                replace: false,
                                group: "versionControl"
                            });
                        }
                    };

                    /**
                     * Copies the repo's clone link to your machine's clipboard
                     * @method cloneToClipboard
                     * @param {String} cloneUrl The URL to be used to clone repos.
                     */
                    repository.cloneToClipboard = function(cloneUrl) {
                        try {
                            var result = versionControlService.cloneToClipboard(cloneUrl);
                            if (result) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully copied the “[_1]” clone [output,acronym,URL,Uniform Resource Locator] to the clipboard.", cloneUrl),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "versionControl"
                                });
                            }
                        } catch (error) {
                            alertService.add({
                                type: "danger",
                                message: _.escape(error),
                                closeable: true,
                                replace: false,
                                group: "versionControl"
                            });
                        }
                    };

                    /**
                     *  Checks if there are available branches or not.
                     *  @method hasAvailableBranches
                     *  @return {Boolean} Returns if there are any branches in the branchList.
                     */
                    repository.hasAvailableBranches = function() {
                        return Boolean(repository.branchList && repository.branchList.length !== 0);
                    };


                }
            ]
        );

        return controller;
    }
);
