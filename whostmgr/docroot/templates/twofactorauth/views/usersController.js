/*
# templates/twofactorauth/views/configController.js
#                                                  Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "cjt/util/locale",
        "lodash",
        "uiBootstrap",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/growlDecorator",
        "app/services/tfaData"
    ],
    function(angular, $, LOCALE, _) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "usersController",
            ["$scope", "$uibModal", "TwoFactorData", "growl", "$timeout",
                function($scope, $uibModal, TwoFactorData, growl, $timeout) {

                    var UC = this;
                    UC.users = [];

                    UC.usersToDisable = [];
                    UC.disableInProgress = false;
                    UC.isSingleDisable = false;

                    UC.modalInstance = null;

                    UC.loadingUsers = true;

                    UC.meta = {
                        sortDirection: "asc",
                        sortBy: "user_name",
                        sortType: "",
                        maxPages: 0,
                        totalRows: UC.users.length || 0,
                        pageNumber: 1,
                        pageNumberStart: 0,
                        pageNumberEnd: 0,
                        pageSize: 20,
                        pageSizes: [20, 50, 100],
                        filteredList: []
                    };

                    UC.resetPagination = function() {
                        UC.meta.pageNumber = 1;
                        UC.fetchPage();
                    };

                    UC.fetchPage = function() {
                        UC.clearSelection();

                        var pageSize = UC.meta.pageSize;
                        var beginIndex = ((UC.meta.pageNumber - 1) * pageSize) + 1;
                        var endIndex = beginIndex + pageSize - 1;
                        if (endIndex > UC.users.length) {
                            endIndex = UC.users.length;
                        }

                        UC.meta.totalRows = UC.users.length;
                        UC.meta.filteredList = UC.users.slice(beginIndex - 1, endIndex);
                        UC.meta.pageNumberStart = ( UC.meta.filteredList.length > 0 ) ? beginIndex : 0;
                        UC.meta.pageNumberEnd = endIndex;
                    };

                    UC.paginationMessage = function() {
                        return LOCALE.maketext("Displaying [numf,_1] to [numf,_2] out of [quant,_3,item,items]", UC.meta.pageNumberStart, UC.meta.pageNumberEnd, UC.meta.totalRows);
                    };

                    UC.sortList = function(meta) {
                        UC.clearSelection();
                        var sortedArray = UC.users;
                        sortedArray = _.sortBy(sortedArray, meta.sortBy);
                        if (meta.sortDirection !== "asc") {
                            sortedArray.reverse();
                        }
                        UC.users = sortedArray;
                        UC.resetPagination();
                    };

                    UC.selectAllUsers = function() {
                        if (UC.users.length === 0) {
                            return;
                        }

                        $(".userSelect").prop("checked", true);
                        $("#selectAllCheckbox").prop("checked", true);
                    };

                    UC.toggleSelectAll = function() {
                        if ($("#selectAllCheckbox").is(":checked")) {
                            $(".userSelect").prop("checked", true);
                        } else {
                            $(".userSelect").prop("checked", false);
                        }
                    };

                    UC.clearSelection = function() {
                        if (UC.users.length === 0) {
                            return;
                        }

                        $(".userSelect").prop("checked", false);
                        $("#selectAllCheckbox").prop("checked", false);
                    };

                    UC.atLeastOneUserIsSelected = function() {
                        return $(".userSelect:checked").length > 0;
                    };

                    UC.allUsersSelected = function() {
                        return $(".userSelect:checked").length === UC.users.length;
                    };

                    UC.confirmDisableTFAFor = function(user) {
                        if (UC.users.length === 0) {
                            return false;
                        }

                        UC.disableInProgress = true;
                        if (typeof (user) !== "undefined") {
                            UC.usersToDisable = [user];
                            UC.isSingleDisable = true;
                        } else {
                            var selected_items = [],
                                $selected_dom_nodes = $(".userSelect:checked");

                            if ($selected_dom_nodes.length === 0) {
                                return false;
                            }

                            $selected_dom_nodes.each( function() {
                                selected_items.push($(this).data("user"));
                            });
                            UC.usersToDisable = selected_items;
                        }

                        UC.modalInstance = $uibModal.open({
                            templateUrl: "confirm_disable.html",
                            controller: "disablePromptController",
                            controllerAs: "dc",
                            resolve: {
                                users: function() {
                                    return UC.usersToDisable;
                                },
                                mode: function() {
                                    return "disableSelected";
                                }
                            }
                        });

                        return UC.modalInstance.result.then(function(usersToRemove, mode) {
                            return UC.removeUsers(usersToRemove, mode);
                        });
                    };

                    UC.confirmDisableAll = function() {
                        if (UC.users.length === 0) {
                            return;
                        }

                        UC.modalInstance = $uibModal.open({
                            templateUrl: "confirm_disable.html",
                            controller: "disablePromptController",
                            controllerAs: "dc",
                            resolve: {
                                users: function() {
                                    return UC.users;
                                },
                                mode: function() {
                                    return "disableAll";
                                }
                            }
                        });

                        return UC.modalInstance.result.then(function(usersToRemove, mode) {
                            return UC.removeUsers(usersToRemove, mode);
                        });
                    };

                    UC.removeUsers = function(users, mode) {
                        if (users === void 0) {
                            return;
                        }

                        return TwoFactorData.disableFor(users)
                            .then(function(result) {

                            // Handle failures
                                var failures = Object.keys(result.failed);
                                if (failures.length === 1) {
                                    growl.error(LOCALE.maketext("The system failed to remove two-factor authentication for “[_1]”.", failures[0]));
                                } else if (failures.length > 1) {
                                    growl.error(LOCALE.maketext("The system failed to remove two-factor authentication for [quant,_1,user,users].", failures.length));
                                }

                                if (mode === "disableSelected") {
                                    if (result.users_modified.length === 1) {
                                        growl.success(LOCALE.maketext("The system successfully removed two-factor authentication for “[_1]”.", result.users_modified[0]));
                                    } else if (result.users_modified.length > 1) {
                                        growl.success(LOCALE.maketext("The system successfully removed two-factor authentication for [quant,_1,user,users].", result.users_modified.length));
                                    }
                                } else if (mode === "disableAll") {
                                    if (result.users_modified.length > 0) {
                                        growl.success(LOCALE.maketext("The system successfully removed two-factor authentication for all users."));
                                    }
                                }

                                if (result.users_modified.length > 0) {
                                    UC.users = result.list;
                                    UC.sortList(UC.meta);
                                }
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    UC.getUsers = function() {
                        UC.loadingUsers = true;
                        return TwoFactorData.getUsers()
                            .then(
                                function(result) {
                                    UC.users = result;
                                    UC.sortList(UC.meta);
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally( function() {
                                UC.loadingUsers = false;
                            });
                    };

                    UC.forceReload = function() {
                        UC.users = [];
                        return UC.getUsers();
                    };

                    UC.getUsers();
                }]);

        return controller;
    }
);
