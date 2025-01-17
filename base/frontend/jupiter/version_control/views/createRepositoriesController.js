/*
# version_control/views/CreateRepositoriesController.js      Copyright 2022 cPanel, L.L.C.
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
        "app/services/sshKeyVerification",
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/toggleSwitchDirective",
        "cjt/directives/toggleLabelInfoDirective",
        "app/services/versionControlService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/validator/ascii-data-validators",
        "cjt/validator/path-validators",
        "app/services/directoryLookupService",
        "app/directives/cloneURLValidator",
        "cjt/filters/htmlFilter",
        "cjt/decorators/uibTypeaheadDecorator",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        var app = angular.module("cpanel.versionControl");
        app.value("PAGE", PAGE);

        var controller = app.controller(
            "CreateRepositoriesController",
            ["$scope", "$location", "versionControlService", "sshKeyVerification", "PAGE", "alertService", "directoryLookupService",
                function($scope, $location, versionControlService, sshKeyVerification, PAGE, alertService, directoryLookupService) {

                    var repository = this;

                    // home directory path
                    repository.homeDirPath = PAGE.homeDir + "/";

                    repository.displaySuccessSummary = false;

                    // initialize form data
                    repository.formData = {
                        repoName: "",
                        repoPath: "",
                        clone: true,
                        cloneURL: "",
                        createAnother: false
                    };

                    repository.ssh = {};

                    repository.pathExcludeList = "[^'\":\\\\*?<>|@&=%#`$(){};\\[\\]\\s]+";// This is for angular input validation.
                    var directoryLookupFilter = /[%*{}()=?`$@:|[\]'"<>&#;\s\\]+/g;// This is the same regex for directory lookup service filter.

                    // Utility function
                    function _bothAreSameServer(obj1, obj2) {
                        return obj1
                            && obj2
                            && obj1.hostname === obj2.hostname
                            && obj2.port     === obj2.port;
                    }

                    /**
                     * When a user inputs a Clone URL, this method is fired to perform
                     * an API check against the user's knowns_hosts file.
                     *
                     * While some state is updated after the API check, the data mostly
                     * lays dormant until the createRepository method is called.
                     *
                     * All of the relevant state is stored on the repository.ssh object.
                     */
                    repository.checkKnownHosts = function() {

                        var cloneUrl = repository.formData.cloneURL;
                        var newServer = cloneUrl && sshKeyVerification.getHostnameAndPort(cloneUrl);

                        if (!newServer) {
                            repository.ssh = {};
                            return;
                        }

                        if ( _bothAreSameServer(repository.ssh, newServer) ) {
                            return;
                        }

                        repository.ssh.hostname = newServer.hostname;
                        repository.ssh.port = newServer.port;
                        repository.ssh.status = "verifying";
                        repository.ssh.keys = [];

                        function _updateScope(data) {

                            /**
                             * It's possible to have a race if there are multiple checks in flight
                             * simultaneously. This check ensures that we only update the scope if
                             * the finished request was initiated using the current input value.
                             */
                            if ( !_bothAreSameServer(repository.ssh, newServer) ) {
                                return;
                            }

                            repository.ssh.status = data.status;
                            repository.ssh.keys = data.keys;
                            return data.status;
                        }

                        return repository.ssh.promise = sshKeyVerification.verify(newServer.hostname, newServer.port).then(_updateScope, _updateScope);
                    };

                    /**
                     * Back to List View
                     * @method backToListView
                     */
                    repository.backToListView = function() {
                        $location.path("/list");
                    };

                    /**
                     * Reset Form Data
                     * @method resetFormData
                     * @param {Object} opts   An object of optional values.
                     * @param {Boolean} opts.isCreateAnother   If true, it will only be a partial reset for Create Another.
                     */
                    repository.resetFormData = function(opts) {
                        repository.formData = {
                            repoName: "",
                            repoPath: "",
                            clone: opts.isCreateAnother ? repository.formData.clone : true,
                            cloneURL: "",
                            createAnother: Boolean(opts.isCreateAnother),
                        };
                        repository.createRepoForm.$setPristine();
                    };

                    /**
                     * Create Repository
                     * @method createRepository
                     * @return {Promise} returns promise.
                     */
                    repository.createRepository = function() {

                        if (!repository.formData.repoName || !repository.formData.repoPath) {
                            return;
                        }

                        alertService.clear(null, "versionControl");

                        if (!repository.formData.clone) {
                            repository.formData.cloneURL = null;
                        }


                        if (repository.formData.cloneURL && (repository.ssh.status === "unrecognized-new" || repository.ssh.status === "unrecognized-changed")) {
                            _showKeyVerificationModal();
                            return;
                        } else if (repository.formData.cloneURL && repository.ssh.promise) {
                            return repository.ssh.promise.then(function(status) {
                                delete repository.ssh.promise;
                                return repository.createRepository();
                            });
                        } else {
                            return _createRepository();
                        }
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
                                message: LOCALE.maketext("The system [output,strong,cannot] clone this repository if you do not trust the host key for “[output,strong,_1]”. To create your repository, select one of the following options:", repository.ssh.hostname),
                                list: [
                                    LOCALE.maketext("Enter a clone URL that uses the HTTPS or Git protocols instead of SSH."),
                                    LOCALE.maketext("Enter a clone URL for a different, previously-trusted host."),
                                    LOCALE.maketext("Click [output,em,Create] again and choose to trust the remote server."),
                                ],
                                closeable: true,
                                replace: true,
                                group: "versionControl",
                                id: "known-hosts-verification-cancelled",
                            });
                        });
                    }

                    function _onAcceptKey(promise) {
                        return promise.then(
                            function success(newStatus) {
                                repository.ssh.status = newStatus;
                                return _createRepository();
                            },
                            function failure(error) {
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("The system failed to add the fingerprints from “[_1]” to the [asis,known_hosts] file: [_2]", repository.ssh.hostname, error),
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
                     * The common bits for actually creating the repo.
                     */
                    function _createRepository() {

                        var repositoryPath = repository.homeDirPath + repository.formData.repoPath;

                        return versionControlService.createRepository(
                            repository.formData.repoName,
                            repositoryPath,
                            repository.formData.cloneURL).then(function(response) {

                            // Clone Repository Success
                            if (repository.formData.cloneURL) {
                                alertService.add({
                                    type: "info",
                                    message: LOCALE.maketext("The system successfully initiated the clone process for the “[_1]” repository.", repository.formData.repoName) + " " + LOCALE.maketext("The system may require more time to clone large remote repositories."),
                                    closeable: true,
                                    replace: false,
                                    group: "versionControl",
                                    id: response.cloneTaskID,
                                    counter: false
                                });

                                if (!repository.formData.createAnother) {
                                    repository.backToListView();
                                } else {
                                    repository.resetFormData({ isCreateAnother: true });
                                }

                            } else {

                                // Create repository Success
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully created the “[_1]” repository.", repository.formData.repoName),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "versionControl"
                                });

                                if (!repository.formData.createAnother) {
                                    var repoSummary = response;
                                    var cloneURL = repoSummary.cloneURL;

                                    if (typeof cloneURL !== "undefined" && cloneURL) {
                                        repository.displaySuccessSummary = true;

                                        repository.summary = {};
                                        repository.summary.remoteURL = cloneURL;
                                        var parts = repository.summary.remoteURL.split("/");

                                        if (parts && parts.length > 0) {
                                            repository.summary.directoryName = parts[parts.length - 1];
                                        } else {
                                            repository.summary.directoryName = "";
                                        }

                                        repository.summary.readOnly = repoSummary.clone_urls.read_write.length === 0 ? true : false;
                                    } else {
                                        repository.backToListView();
                                    }
                                } else {
                                    repository.resetFormData({ isCreateAnother: true });
                                }
                            }

                        }, function(error) {
                            alertService.add({
                                type: "danger",
                                message: error,
                                closeable: true,
                                replace: false,
                                group: "versionControl"
                            });
                        });
                    }

                    /**
                     * Directory lookup
                     * @method completeDirectory
                     * @return {Promise} Returns an array of directory paths.
                     */
                    repository.completeDirectory = function(prefix) {
                        var directoryLookupPromise = directoryLookupService.complete(prefix);
                        var outputDirectories = [];

                        return directoryLookupPromise.then(function(directories) {

                            for ( var i = 0, len = directories.length; i < len; i++ ) {

                                var directoryName = directories[i];

                                if ( directoryName.search(directoryLookupFilter) === -1 ) {
                                    outputDirectories.push(directoryName);
                                }
                            }

                            return outputDirectories;
                        });
                    };

                    /**
                     * Toggle Status
                     * @method toggleStatus
                     * @return {Boolean} Returns true.
                     */
                    repository.toggleStatus = function() {
                        repository.formData.clone = !repository.formData.clone;
                        return true;
                    };

                    /**
                     * Autofill Repository path and name based on clone url
                     * @method autoFillPathAndName
                     */
                    repository.autoFillPathAndName = function() {
                        if (!repository.formData.repoName && !repository.formData.repoPath) {
                            if (repository.createRepoForm.repoCloneURL.$valid && repository.formData.cloneURL) {
                                var cloneUrl = repository.formData.cloneURL;
                                var repoPathPrefix = "repositories/";

                                // Removing training slash
                                cloneUrl = cloneUrl.replace(/\/+$/, "");

                                // finding last part of the url and replacing .git if present
                                var repoDirectory = cloneUrl.substr(cloneUrl.lastIndexOf("/") + 1).replace(".git", "");
                                repoDirectory = repoDirectory.replace(directoryLookupFilter, "_");

                                var repositoryPath = repoPathPrefix + repoDirectory;
                                repository.formData.repoPath = repositoryPath;
                                repository.formData.repoName = repoDirectory;
                            }
                        }
                    };
                }
            ]
        );

        return controller;
    }
);
