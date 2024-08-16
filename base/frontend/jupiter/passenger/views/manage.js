/*
# passenger/views/manage.js                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/* eslint-disable camelcase */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/table",
        "cjt/util/parse",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/services/viewNavigationApi",
        "cjt/directives/quickFiltersDirective",
        "app/services/sseAPIService",
        "uiBootstrap",
    ],
    function(angular, _, LOCALE, Table, PARSE) {
        "use strict";

        var app = angular.module("cpanel.applicationManager");
        app.value("PAGE", PAGE);
        var controller = app.controller(
            "ManageApplicationsController",
            [
                "$scope",
                "$routeParams",
                "viewNavigationApi",
                "$uibModal",
                "Apps",
                "defaultInfo",
                "alertService",
                "sseAPIService",
                "PAGE",
                "$timeout",
                function(
                    $scope,
                    $routeParams,
                    viewNavigationApi,
                    $uibModal,
                    Apps,
                    defaultInfo,
                    alertService,
                    sseAPIService,
                    PAGE,
                    $timeout) {
                    var manage = this;

                    manage.is_loading = false;
                    manage.applications = [];
                    manage.loading_error = false;
                    manage.loading_error_message = "";
                    manage.user_home_dir = defaultInfo.homedir;
                    manage.change_in_progress = false;
                    manage.ensureDepList = [];

                    manage.secTokenPrefix = PAGE.securityToken; // Initialize with security token.
                    manage.sseObj = null;

                    // SSE events and config
                    var events = ["task_processing", "task_complete", "task_failed"];
                    var sseConfig = { json: true };

                    var table = new Table();

                    function searchByName(item, searchText) {
                        return item.name.indexOf(searchText) !== -1;
                    }
                    function searchByType(item, type) {
                        return item.type === type;
                    }

                    table.setSearchFunction(searchByName);
                    table.setFilterOptionFunction(searchByType);

                    manage.meta = table.getMetadata();
                    manage.filteredList = table.getList();
                    manage.paginationMessage = table.paginationMessage;
                    manage.render = function() {
                        manage.filteredList = table.update();
                    };
                    manage.sortList = function() {
                        manage.render();
                    };
                    manage.selectPage = function() {
                        manage.render();
                    };
                    manage.selectPageSize = function() {
                        manage.render();
                    };
                    manage.searchList = function() {
                        manage.render();
                    };

                    manage.quota_warning = function() {
                        return LOCALE.maketext("You can’t have more than [numf,_1] applications on your account.", Apps.get_maximum_number_of_apps());
                    };

                    manage.show_quota_warning = function() {
                        return Apps.exceeds_quota();
                    };

                    manage.dependenciesExist = function(appl) {
                        var exist = false;
                        if (appl) {
                            var deps = appl.deps;
                            exist = _.some(deps, function(key) {
                                if (key) {
                                    return true;
                                }
                            });
                        }
                        return exist;
                    };

                    /**
                     * Resets ensure deps state of application
                     * @method ensureDependencies
                     * @param {Object} app application object
                     * @returns {Object} Promise
                     */
                    manage.ensureDependencies = function(app) {
                        var types = _.keys(app.deps);
                        _.each(types, function(type) {
                            if (app.deps[type]) {
                                return Apps.ensureDependencies(type, app.path)
                                    .then(function(res) {
                                        var sseUrl = res.data.sse_url;
                                        var ensureStarted = true;
                                        app.ensureInProgress = ensureStarted;
                                        app.showEnsureView = ensureStarted;
                                        if (app.ensureDeps) {
                                            app.ensureDeps[type] = {
                                                taskId: res.data.task_id,
                                                inProgress: ensureStarted,
                                            };
                                        }

                                        if (!manage.sseURL && !manage.sseObj) {
                                            manage.sseURL = manage.secTokenPrefix + sseUrl;
                                            sseAPIService.initialize();
                                        }

                                        manage.ensureDepList.push(app);
                                    })
                                    .catch(function(error) {
                                        alertService.add({
                                            type: "danger",
                                            message: error,
                                            closeable: true,
                                            replace: false,
                                            group: "passenger",
                                        });
                                    });
                            }
                        });
                    };

                    /**
                     * Resets ensure deps state of application
                     * @method resetEnsureDependencyParams
                     * @param {Object} appObject application
                     * @returns {Object} updated application object
                     */
                    function resetEnsureDependencyParams(appObject) {
                        if (appObject) {
                            appObject.ensureDeps = {};
                            appObject.ensureState = "";
                            appObject.ensureInProgress = false;
                            appObject.showEnsureView = false;
                        }
                        return appObject;
                    }

                    /**
                     * Handles the close action of failed callout of ensure dependency.
                     * @method clearEnsureDepsTaskParams
                     * @param {Object} appObject application object
                     */
                    manage.clearEnsureDepsTaskParams = function(appObject) {
                        resetEnsureDependencyParams(appObject);
                    };

                    /**
                     * Return the appropriate message depending on application level ensure state.
                     *
                     * @method getAppLevelEnsureStateMessage
                     * @param {Object} appl application object
                     */
                    manage.getAppLevelEnsureStateMessage = function(appl) {
                        var msg = "";
                        switch (appl.ensureState) {
                            case "processing":
                                msg = LOCALE.maketext("Ensuring dependencies for your application …");
                                break;
                            case "complete":
                                msg = LOCALE.maketext("The system ensured the dependencies for your application.");
                                break;
                            case "failure":
                                msg = LOCALE.maketext("The system couldn’t ensure dependencies for your application. For more information, see the instructions below.");
                                break;
                            default:
                                msg = LOCALE.maketext("The system queued your application to ensure its dependencies …");
                                break;
                        }
                        return msg;
                    };

                    /**
                     * Determines font awesome icon to show based on individual package types' state
                     * (i.e. gem/pip/npm etc. types)
                     *
                     * @method getIconClassForEnsureState
                     * @param {String} ensureState ensure state of a package type.
                     */
                    manage.getIconClassForEnsureState = function(ensureState) {
                        var strClass = "";
                        switch (ensureState) {
                            case "complete":
                                strClass = "far fa-check-circle text-success";
                                break;
                            case "failure":
                                strClass = "fas fa-exclamation-circle text-danger";
                                break;
                            default:
                                strClass = "fas fa-spinner fa-spin";
                                break;
                        }
                        return strClass;
                    };

                    /**
                     * Retrieves the application object that owns the task given the task id.
                     *
                     * @method getTaskOwner
                     * @param {String} taskId the task id of the package type that is being ensured.
                     */
                    var getTaskOwner = function(taskId) {
                        var ensureType = "";
                        var applicationItem = _.find(manage.ensureDepList, function(app) {
                            var types = _.keys(app.ensureDeps);
                            if (types.length > 0) {
                                return _.some(app.ensureDeps, function(value, type) {
                                    if (value.taskId === taskId) {
                                        ensureType = type;
                                        return true;
                                    }
                                });
                            }
                        });

                        return { ensureType: ensureType, applicationItem: applicationItem };
                    };

                    /**
                     * Determines what is the application's ensure state
                     * depending on the individual package types state (i.e. gem/pip/npm etc. types)
                     *
                     * @method getAppLevelEnsureState
                     * @param {Object} app application object
                     * @return {String} ensureState - Final determined ensureState at the application level.
                     */
                    var getAppLevelEnsureState = function(app) {
                        var ensureState = app.ensureState;

                        // The ensure state at the application level will be marked as 'complete'
                        // only if all types in a given application are complete. But if at least one
                        // type fails, then the application's ensure state is failure.
                        var type = _.findKey(app.ensureDeps, function(value) {
                            return value.ensureState !== "complete";
                        });
                        if (type) {
                            ensureState = app.ensureDeps[type].ensureState;
                        } else {
                            ensureState = "complete";
                        }
                        return ensureState;
                    };

                    /**
                     * Determines the progress of ensure process at the application level
                     * depending on the individual package types progress state (i.e. gem/pip/npm etc. types)
                     *
                     * @method getAppLevelEnsureProgress
                     * @param {Object} app application object
                     * @return {Boolean} ensureProgress - Final determined progress state at the application level.
                     */
                    var getAppLevelEnsureProgress = function(app) {
                        var ensureProgress = app.ensureInProgress;
                        var typeInProgress = _.findKey(app.ensureDeps, function(value) {
                            return value.inProgress;
                        });
                        if (typeInProgress) {
                            ensureProgress = true;
                        } else {
                            ensureProgress = false;
                        }
                        return ensureProgress;
                    };

                    /**
                     * Handles task_processing.
                     *
                     * @method
                     * @param {sse:task_processing} event - Task processing event.
                     * @param {Object} data - Data
                     * @listens sse:task_processing
                     */
                    $scope.$on("sse:task_processing", function(event, data) {
                        var taskID = data.task_id;
                        var taskOwner = getTaskOwner(taskID);

                        if (taskOwner.applicationItem) {
                            var unfilteredIndex = _.indexOf(manage.filteredList, taskOwner.applicationItem);

                            if (unfilteredIndex !== -1) {
                                taskOwner.applicationItem.ensureDeps[taskOwner.ensureType].ensureState = "processing";

                                // Application level ensureState is set to processing if at least one of the types is in processing.
                                taskOwner.applicationItem.ensureInProgress = true;
                                taskOwner.applicationItem.ensureState = "processing";
                                _.extend(manage.filteredList[unfilteredIndex], taskOwner.applicationItem);
                                $scope.$apply(manage.render);
                            }
                        }
                    });

                    /**
                     * Close and reset the SSE connection
                     *
                     * @method close_and_reset_SSE
                     */
                    var close_and_reset_SSE = function() {
                        if (manage.sseObj) {
                            sseAPIService.close(manage.sseObj);
                            manage.sseObj = null;
                            manage.sseURL = "";
                        }
                    };

                    /**
                     * Update the params that are used in the ensure dependency view.
                     *
                     * @method updateEnsureViewParams
                     * @param {Object} taskOwner - { ensureType, applicationItem }
                     * @param {String} eventState
                     */
                    var updateEnsureViewParams  = function(taskOwner, eventState) {
                        var unfilteredIndex = _.indexOf(manage.filteredList, taskOwner.applicationItem);

                        if (unfilteredIndex !== -1) {
                            taskOwner.applicationItem.ensureDeps[taskOwner.ensureType].ensureState = eventState;
                            taskOwner.applicationItem.ensureDeps[taskOwner.ensureType].inProgress = false;
                            var appLevelEnsureProgress = getAppLevelEnsureProgress(taskOwner.applicationItem);
                            taskOwner.applicationItem.ensureInProgress = appLevelEnsureProgress;

                            // This means all types are processed and should be either success or failure at this point.
                            if (!appLevelEnsureProgress) {
                                taskOwner.applicationItem.ensureState = getAppLevelEnsureState(taskOwner.applicationItem);
                            }
                            if (eventState === "failure") {
                                taskOwner.applicationItem.ensureDeps[taskOwner.ensureType].command = taskOwner.applicationItem.deps[taskOwner.ensureType];
                            }
                            _.extend(manage.filteredList[unfilteredIndex], taskOwner.applicationItem);
                            $scope.$apply(manage.render);
                        }

                        // removing object from ensure list after the action is done (success or failure)
                        if (!taskOwner.applicationItem.ensureInProgress &&
                            (taskOwner.applicationItem.ensureState === "complete" || taskOwner.applicationItem.ensureState === "failure")) {
                            _.remove(manage.ensureDepList, taskOwner.applicationItem);
                            if (taskOwner.applicationItem.ensureState === "complete") {
                                $timeout(function() {

                                    // updating the ensure view with new information so that the row is active
                                    _.extend(manage.filteredList[unfilteredIndex], resetEnsureDependencyParams(taskOwner.applicationItem));
                                    $scope.$apply(manage.render);
                                }, 5000);
                            }
                        }
                        if (manage.ensureDepList.length === 0) {
                            close_and_reset_SSE();
                        }
                    };

                    /**
                     * Handles task_complete.
                     *
                     * @method
                     * @param {sse:task_complete} event - Task complete event.
                     * @param {Object} data - Data
                     * @listens sse:task_complete
                     */
                    $scope.$on("sse:task_complete", function(event, data) {
                        var taskID = data.task_id;
                        var taskOwner = getTaskOwner(taskID);

                        if (taskOwner.applicationItem) {

                            // The failed tasks are triggering 'complete' event as well. Skipping them here since
                            // failures are handled in 'sse:failure'.
                            if (taskOwner.applicationItem.ensureDeps[taskOwner.ensureType].ensureState === "failure") {
                                return;
                            }

                            updateEnsureViewParams(taskOwner, "complete");
                            close_and_reset_SSE();
                        }
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
                        var taskID = data.task_id;
                        var taskOwner = getTaskOwner(taskID);

                        if (taskOwner.applicationItem) {
                            updateEnsureViewParams(taskOwner, "failure");
                            close_and_reset_SSE();
                        }
                    });

                    /**
                     * Handles ready.
                     *
                     * @method
                     * @param {sse:ready} event - Task ready event.
                     * @listens sse:ready
                     */
                    $scope.$on("sse:ready", function(event) {
                        manage.sseObj = sseAPIService.connect(manage.sseURL, events, sseConfig);
                    });

                    /**
                     * Handles destroy.
                     *
                     * @method
                     * @listens $destroy
                     */
                    $scope.$on("$destroy", function() {
                        close_and_reset_SSE();
                    });

                    manage.configure_details = function(appl) {
                        if (appl === void 0) {
                            viewNavigationApi.loadView("/details");
                        } else {
                            viewNavigationApi.loadView("/details/" + appl.name);
                        }
                    };

                    manage.toggle_status = function(app) {
                        manage.change_in_progress = true;

                        return Apps.toggle_application_status(app)
                            .then(function(application_data) {
                                if (application_data.enabled) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully enabled your application."),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "passenger",
                                    });
                                } else {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully disabled your application."),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "passenger",
                                    });
                                }
                                app.enabled = PARSE.parsePerlBoolean(application_data.enabled);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    replace: false,
                                    group: "passenger",
                                });
                            })
                            .finally(function() {
                                manage.change_in_progress = false;
                            });
                    };

                    function RemoveRecordModalController($uibModalInstance, appl_name) {
                        var ctrl = this;

                        ctrl.confirm_msg = LOCALE.maketext("Are you sure that you want to unregister your application (“[_1]”)?", appl_name);

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return Apps.remove_application(appl_name)
                                .then(function() {
                                    table.setSort("name", "asc");
                                    _.remove(manage.applications, function(app) {
                                        return app.name === appl_name;
                                    });
                                    manage.render();
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully unregistered your application."),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "passenger",
                                    });
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        replace: false,
                                        group: "passenger",
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });

                        };
                    }

                    RemoveRecordModalController.$inject = ["$uibModalInstance", "appl_name"];

                    manage.confirm_delete_record = function(applName) {
                        manage.change_in_progress = true;
                        var instance = $uibModal.open({
                            templateUrl: "confirm_delete.html",
                            controller: RemoveRecordModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                appl_name: function() {
                                    return applName;
                                },
                            },
                        });
                        instance.result.finally(function() {
                            manage.change_in_progress = false;
                        });
                    };

                    manage.refresh = function() {
                        return load(true);
                    };

                    function load(force) {
                        if ($routeParams.hasOwnProperty("forceLoad") &&
                        $routeParams.forceLoad === 1) {
                            force = true;
                        } else if (force === void 0) {
                            force = false;
                        }

                        manage.is_loading = true;
                        return Apps.fetch(force)
                            .then(function(data) {
                                manage.applications = data;
                                if (manage.applications) {
                                    manage.applications = _.map(manage.applications, function(app) {

                                        // Init ensure dependency related data.
                                        app = resetEnsureDependencyParams(app);
                                        return app;
                                    });
                                }

                                table.setSort("name", "asc");
                                table.load(manage.applications);
                                manage.render();
                            })
                            .catch(function(error) {

                                // If we get an error at this point, we assume that the user
                                // should not be able to do anything on the page.
                                manage.loading_error = true;
                                manage.loading_error_message = error;
                            })
                            .finally(function() {
                                manage.is_loading = false;
                            });
                    }

                    manage.init = function() {
                        alertService.clear(void 0, "passenger");
                        load();
                    };

                    manage.init();
                },
            ]);

        return controller;
    }
);
