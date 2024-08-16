/*
 * templates/tomcat/services/configService.js           Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/services/configService',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/whm-v1-request",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1",
        "cjt/services/APIService"
    ],
    function(angular, _, LOCALE, APIREQUEST, PARSE) {

        "use strict";

        var app = angular.module("whm.tomcat.configService", []);
        app.factory(
            "TomcatApi",
            ["$q", "APIService", function($q, APIService) {

                var TomcatApiService = function() { };
                TomcatApiService.prototype = new APIService();

                var isEmptyObject = function(obj) {
                    for (var key in obj) {
                        if (obj.hasOwnProperty(key)) {
                            return false;
                        }
                    }
                    return true;
                };

                var userList = {};
                angular.extend(TomcatApiService.prototype, {

                    /**
                     * Returns a list of cPanel & WHM users.
                     *
                     * @method - getUsers
                     * @param {Boolean} force - If true, will force load the data into the cached object.
                     * @returns {Promise} - When fulfilled, will return list of users.
                     */
                    getUsers: function getUsers(force) {
                        if (force || isEmptyObject(userList)) {
                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("", "list_users");

                            return this.deferred(apiCall).promise
                                .then(function(response) {
                                    userList = response.data;
                                    return userList;
                                })
                                .catch(function(error) {
                                    return $q.reject(error);
                                });
                        } else {
                            return $q.when(userList);
                        }
                    },

                    /**
                     * Returns a list of users for whom Tomcat is enabled.
                     *
                     * @method getTomcatList
                     * @returns {Promise} When fulfilled, will return the list of Tomcat enabled users.
                     */
                    getTomcatList: function getTomcatList() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("", "ea4_tomcat85_list");

                        return this.deferred(apiCall).promise
                            .then(function(response) {
                                userList = response.data;
                                return userList;
                            })
                            .catch(function(error) {
                                return $q.reject(error);
                            });
                    },

                    /**
                     * The service used to enable or disable Tomcat for selected user.
                     *
                     * @method enableDisableTomcat
                     * @param {Array} userList - List of selected users.
                     * @param {boolean} enable - Toggle flag ? true to enable : false to disable.
                     */
                    enableDisableTomcat: function enableDisableTomcat(userList, enable) {
                        var apiCall = new APIREQUEST.Class();
                        if (enable) {
                            apiCall.initialize("", "ea4_tomcat85_add");
                        } else {
                            apiCall.initialize("", "ea4_tomcat85_rem");
                        }

                        _.each(userList, function(user, index) {
                            apiCall.addArgument("user-" + index, user);
                        });

                        return this.deferred(apiCall).promise
                            .then(function(response) {
                                return response.data;
                            })
                            .catch(function(error) {
                                return $q.reject(error);
                            });
                    },
                });

                return new TomcatApiService();
            }
            ]);
    });

/*
 * templates/tomcat/views/config.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/views/config',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/table",
        "uiBootstrap",
        "cjt/filters/qaSafeIDFilter",
        "cjt/decorators/growlDecorator",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/directives/toggleSortDirective",
        "cjt/services/viewNavigationApi",
        "cjt/directives/autoFocus"
    ],
    function(angular, _, LOCALE, Table) {

        "use strict";

        // Retrieve the current application
        var app = angular.module("whm.tomcat");

        var controller = app.controller(
            "config",
            ["$scope", "$q", "TomcatApi", "alertService", "$uibModal",
                function($scope, $q, TomcatApi, alertService, $uibModal) {
                    var tomcatVer = "Tomcat 8.5";
                    var memoryUsageWarning = LOCALE.maketext("Your server may run out of memory if you enable “[_1]” for multiple users.", tomcatVer);
                    $scope.config = this;

                    $scope.config.loading = false;
                    $scope.config.showFormToggleBtn = true;
                    $scope.config.tokenAdded = false;
                    $scope.config.loadingError = false;
                    $scope.config.loadingErrorMessage = "";
                    $scope.config.allChecked = false;
                    $scope.config.checkedCount = 0;
                    $scope.config.paginationMessage = "";

                    function search(item, searchText) {
                        return (item.user.toLowerCase().indexOf(searchText.toLowerCase()) !== -1) || (item.user.toLowerCase().indexOf(searchText.toLowerCase()) !== -1);
                    }

                    var table = new Table();
                    table.setSearchFunction(search);
                    table.setSort("user", "asc");
                    $scope.config.meta = table.getMetadata();
                    $scope.config.filteredList = table.getList();
                    $scope.config.allUsers = [];
                    $scope.config.render = function() {
                        $scope.config.resetCheckAll();
                        $scope.config.filteredList = table.update();
                        $scope.config.paginationMessage = table.paginationMessage();
                    };
                    $scope.config.sortList = function() {
                        $scope.config.render();
                    };
                    $scope.config.selectPage = function() {
                        $scope.config.render();
                    };
                    $scope.config.selectPageSize = function() {
                        $scope.config.render();
                    };
                    $scope.config.searchList = function() {
                        $scope.config.render();
                    };
                    $scope.config.toggleLabel = function(item) {
                        return item.tomcatEnabled ? LOCALE.maketext("Enabled") : LOCALE.maketext("Disabled");
                    };

                    $scope.config.resetCheckAll = function() {
                        $scope.config.allChecked = false;
                        $scope.config.toggleCheckAll();
                        $scope.config.checkedCount = 0;
                    };

                    $scope.config.getIndeterminateState = function() {
                        return $scope.config.checkedCount > 0 && !$scope.config.allChecked;
                    };

                    $scope.config.toggleCheckAll = function() {
                        if ($scope.config.filteredList.length === 0) {
                            return;
                        }
                        var i = 0, listLength = $scope.config.filteredList.length;
                        for (i; i < listLength; i++) {
                            $scope.config.filteredList[i].checked = $scope.config.allChecked;
                        }
                        if ($scope.config.allChecked) {
                            $scope.config.checkedCount = listLength;
                        } else {
                            $scope.config.checkedCount = 0;
                        }
                    };

                    $scope.config.syncCheckAll = function(listItem) {
                        if (listItem.checked) {
                            $scope.config.checkedCount++;
                        } else {
                            $scope.config.checkedCount--;
                        }
                        $scope.config.allChecked = $scope.config.checkedCount === $scope.config.filteredList.length;
                    };

                    $scope.config.checkAll = function() {
                        $scope.config.allChecked = true;
                        $scope.config.toggleCheckAll();
                    };


                    $scope.config.refreshList = function() {
                        $scope.config.filteredList = [];
                        $scope.config.allTokens = [];
                        return load();
                    };

                    $scope.config.toggleLabel = function(item) {
                        return (item.tomcatEnabled) ? LOCALE.maketext("Enabled") : LOCALE.maketext("Disabled");
                    };
                    $scope.config.toggleTitle = function(item) {
                        return (item.tomcatEnabled) ? LOCALE.maketext("Disable [asis,Tomcat] support.") : LOCALE.maketext("Enable [asis,Tomcat] support.");
                    };

                    $scope.config.toggleTomcatStatus = function(item) {
                        alertService.clear();
                        return TomcatApi.enableDisableTomcat([item.user], !item.tomcatEnabled)
                            .then(function(data) {
                                if (_.isEmpty(data[item.user])) {
                                    item.tomcatEnabled = !item.tomcatEnabled;

                                    var successMsg = (item.tomcatEnabled) ?
                                        LOCALE.maketext("“[_1]” support is enabled for “[_2]”.", tomcatVer, item.user) :
                                        LOCALE.maketext("“[_1]” support is disabled for “[_2]”.", tomcatVer, item.user);

                                    alertService.add({
                                        type: "success",
                                        message: _.escape(successMsg),
                                        autoclose: 1000,
                                        id: "alertSuccess",
                                        replace: true
                                    });
                                } else {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(data[item.user]),
                                        id: "alertError",
                                        replace: true
                                    });
                                }
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "alertError",
                                    replace: true
                                });
                            })
                            .finally(function() {
                                $scope.config.resetToggleSingle(item);
                            });
                    };

                    $scope.config.confirmToggleSingle = function(item) {
                        item.showAlert = true;
                        if (item.tomcatEnabled) {
                            item.elId = "confirmToggle_continue_disable_" + item.user;
                            item.alertActionTitle = LOCALE.maketext("Continue to disable.");
                            item.alertActionText = LOCALE.maketext("Disable");
                            item.alertMsg = LOCALE.maketext("If you disable “[_1]”, any URLs that “[_1]” handles will no longer work as expected.", tomcatVer);
                        } else {
                            item.elId = "confirmToggle_continue_enable_" + item.user;
                            item.alertActionTitle = LOCALE.maketext("Continue to enable.");
                            item.alertActionText = LOCALE.maketext("Enable");
                            item.alertMsg = memoryUsageWarning;
                        }
                        return;
                    };

                    $scope.config.resetToggleSingle = function(item) {
                        item.showAlert = false;
                        item.alertMsg = "";
                        return;
                    };

                    $scope.config.confirmToggleMultiple = function(userList, enable) {
                        $uibModal.open({
                            templateUrl: "confirm_enable_disable.tmpl",
                            controller: ToggleTomcatModalController,
                            controllerAs: "promptCtrl",
                            resolve: {
                                data: function() {
                                    return {
                                        "userList": userList,
                                        "enable": enable
                                    };
                                }
                            }
                        });
                    };

                    function load() {
                        $scope.config.loading = true;

                        // Get all users and the tomcat enabled users via ajax
                        // calls simultaneously and process the view.
                        return $q.all([
                            TomcatApi.getUsers(true),
                            TomcatApi.getTomcatList()])
                            .then(function(data) {
                                var tableData = [];
                                var userList = data[0];
                                var tomcatList = data[1];
                                if (userList !== null && typeof userList !== "undefined") {
                                    tableData = _.map(_.pull(userList, "root"), function(item) {
                                        return {
                                            user: item,
                                            tomcatEnabled: _.includes(tomcatList, item),
                                            showAlert: false,
                                            alertMsg: ""
                                        };
                                    });

                                    table.load(tableData);
                                    $scope.config.allUsers = tableData;
                                    $scope.config.render();
                                }
                            })
                            .catch(function(error) {
                                $scope.config.loadingError = true;
                                $scope.config.loadingErrorMessage = error;
                            })
                            .finally(function() {
                                $scope.config.loading = false;
                            });
                    }

                    $scope.config.getSelectedUsers = function() {
                        var selectedUsers = [];
                        selectedUsers = _.filter($scope.config.filteredList, [ "checked", true ]);
                        return selectedUsers;
                    };

                    function ToggleTomcatModalController($uibModalInstance, data) {
                        var promptCtrl = this;
                        promptCtrl.showActions = true;

                        promptCtrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };

                        // In the selected list there can be a mix of tomcat enabled and
                        // non enabled users.
                        // If the current toggle is to enable, let's filter out the users that are already enabled.
                        // Then we can send only the non enabled ones to the API.
                        var eligibleUsers = _.map(_.filter(data.userList, ["tomcatEnabled", !data.enable]), "user");
                        var disableWarningText = LOCALE.maketext("If you disable “[_1]”, any URLs that “[_1]” handles will no longer work as expected.", tomcatVer);

                        if (_.isEmpty(eligibleUsers)) {
                            promptCtrl.showActions = false;
                            if (data.enable) {
                                promptCtrl.prompt = LOCALE.maketext("“[_1]” is already enabled for the selected [numerate,_2,user,users]. Select other users to enable.", tomcatVer, eligibleUsers.length);
                            } else {
                                promptCtrl.prompt = LOCALE.maketext("“[_1]” is already disabled for the selected [numerate,_2,user,users]. Select other users to disable.", tomcatVer, eligibleUsers.length);
                            }
                        } else if (eligibleUsers.length > 0 && eligibleUsers.length === $scope.config.allUsers.length) {
                            if (data.enable) {
                                promptCtrl.prompt = memoryUsageWarning + " " + LOCALE.maketext("Are you certain that you want to enable “[_1]” for all of your users?", tomcatVer);
                            } else {
                                promptCtrl.prompt = disableWarningText;
                            }

                        } else if (eligibleUsers.length > 0) {
                            if (data.enable) {
                                promptCtrl.prompt = memoryUsageWarning + " " + LOCALE.maketext("Are you certain that you want to enable “[_1]” for the selected [numerate,_2,user,users]?", tomcatVer, eligibleUsers.length);
                            } else {
                                promptCtrl.prompt = disableWarningText;
                            }
                        }

                        promptCtrl.confirm = function() {
                            return TomcatApi.enableDisableTomcat(eligibleUsers, data.enable)
                                .then(function(response) {
                                    if (response) {
                                        var successList = [];
                                        _.each(_.keys(response), function(key) {
                                            if (_.isEmpty(response[key])) {
                                                successList.push(key);
                                            }
                                        });

                                        var failedDomains = _.omit(response, successList);
                                        var failedKeys = _.keys(failedDomains);
                                        if (failedKeys.length > 0) {
                                            _.each(failedKeys, function(key) {
                                                alertService.add({
                                                    type: "danger",
                                                    message: _.escape(failedDomains[key]),
                                                    replace: false
                                                });
                                            });
                                        }
                                        if (successList.length !== 0) {
                                            var successMsg = "";
                                            if (successList.length === $scope.config.allUsers.length) {
                                                if (data.enable) {
                                                    successMsg = LOCALE.maketext("You successfully enabled “[_1]” for all of your users.", tomcatVer);
                                                } else {
                                                    successMsg = LOCALE.maketext("You successfully disabled “[_1]” for all of your users.", tomcatVer);
                                                }
                                            } else if (Array.isArray(data.userList) && successList.length === data.userList.length) {
                                                if (data.enable) {
                                                    successMsg = LOCALE.maketext("You successfully enabled “[_1]” for the selected [numerate,_2,user,users].", tomcatVer, eligibleUsers.length);
                                                } else {
                                                    successMsg = LOCALE.maketext("You successfully disabled “[_1]” for the selected [numerate,_2,user,users].", tomcatVer, eligibleUsers.length);
                                                }
                                            } else {
                                                if (data.enable) {
                                                    successMsg = LOCALE.maketext("You successfully enabled “[_1]” for “[_2]” of “[_3]” [numerate,_3,user,users].", tomcatVer, successList.length, eligibleUsers.length);
                                                } else {
                                                    successMsg = LOCALE.maketext("You successfully disabled “[_1]” for “[_2]” of “[_3]” [numerate,_3,user,users].", tomcatVer, successList.length, eligibleUsers.length);
                                                }
                                            }
                                            alertService.add({
                                                type: "success",
                                                message: _.escape(successMsg),
                                                autoclose: 1000,
                                                replace: false
                                            });
                                        }
                                        $scope.config.refreshList();
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        replace: false
                                    });
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                    }

                    ToggleTomcatModalController.$inject = ["$uibModalInstance", "data"];

                    /**
                     * Sets up user interface data structures from loaded data.
                     */
                    $scope.$on("$viewContentLoaded", function() {
                        load();
                    });
                }
            ]);
        return controller;
    }
);

/*
* templates/tomcat/index.js                       Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "app/services/configService",
    ],
    function(angular, $, _, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("whm.tomcat", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "whm.tomcat.configService"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/config",
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.tomcat");

                    // Setup Routing
                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/config", {
                                controller: "config",
                                templateUrl: CJT.buildFullPath("tomcat/views/config.ptt"),
                                reloadOnSearch: false
                            })
                                .otherwise({
                                    "redirectTo": "/config"
                                });

                        }
                    ]);

                    BOOTSTRAP(document, "whm.tomcat");

                });

            return app;
        };
    }
);

