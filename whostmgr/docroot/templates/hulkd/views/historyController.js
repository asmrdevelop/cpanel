/*
# templates/hulkd/views/historyController.js      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/growlDecorator",
        "app/services/FailedLoginService",
        "app/services/HulkdDataSource"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "historyController",
            ["$scope", "$filter", "$q", "$timeout", "FailedLoginService", "HulkdDataSource", "growl",
                function($scope, $filter, $q, $timeout, FailedLoginService, HulkdDataSource, growl) {

                    function updatePagination(scopeObj, apiResults) {
                        var page_size = parseInt(apiResults.meta.paginate.page_size, 10);
                        if (page_size === 0) {
                            scopeObj.pageSize = $scope.meta.pageSizes[0];
                        } else {
                            scopeObj.pageSize = page_size;
                        }
                        scopeObj.totalRows = apiResults.meta.paginate.total_records;
                        scopeObj.pageNumber = apiResults.meta.paginate.current_page;
                        scopeObj.pageNumberStart = apiResults.meta.paginate.current_record;

                        if (scopeObj.totalRows === 0) {
                            scopeObj.pageNumberStart = 0;
                        }

                        scopeObj.pageNumberEnd = (scopeObj.pageNumber * page_size);


                        if (scopeObj.pageNumberEnd > scopeObj.totalRows) {
                            scopeObj.pageNumberEnd = scopeObj.totalRows;
                        }
                    }

                    $scope.changePageSize = function(type) {
                        if (type === "logins") {
                            if ($scope.logins.length > 0) {
                                return $scope.fetchFailedLogins({ isUpdate: true });
                            }
                        } else if (type === "users") {
                            if ($scope.users.length > 0) {
                                return $scope.fetchBlockedUsers({ isUpdate: true });
                            }
                        } else if (type === "brutes") {
                            if ($scope.brutes.length > 0) {
                                return $scope.fetchBrutes({ isUpdate: true });
                            }
                        } else if (type === "excessiveBrutes") {
                            if ($scope.excessiveBrutes.length > 0) {
                                return $scope.fetchExcessiveBrutes({ isUpdate: true });
                            }
                        }
                    };

                    $scope.fetchPage = function(type, page) {
                        if (type === "logins") {
                            if (page && angular.isNumber(page)) {
                                $scope.meta.logins.currentPage = page;
                            }
                            return $scope.fetchFailedLogins({ isUpdate: true });
                        } else if (type === "users") {
                            if (page && angular.isNumber(page)) {
                                $scope.meta.users.currentPage = page;
                            }
                            return $scope.fetchBlockedUsers({ isUpdate: true });
                        } else if (type === "brutes") {
                            if (page && angular.isNumber(page)) {
                                $scope.meta.brutes.currentPage = page;
                            }
                            return $scope.fetchBrutes({ isUpdate: true });
                        } else if (type === "excessiveBrutes") {
                            if (page && angular.isNumber(page)) {
                                $scope.meta.excessiveBrutes.currentPage = page;
                            }
                            return $scope.fetchExcessiveBrutes({ isUpdate: true });
                        }
                    };

                    $scope.sortBruteList = function(meta) {
                        $scope.meta.brutes.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        return $scope.fetchBrutes({ isUpdate: true });
                    };

                    $scope.sortExcessiveBruteList = function(meta) {
                        $scope.meta.excessiveBrutes.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        return $scope.fetchExcessiveBrutes({ isUpdate: true });
                    };

                    $scope.sortLoginList = function(meta) {
                        $scope.meta.logins.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        return $scope.fetchFailedLogins({ isUpdate: true });
                    };

                    $scope.sortBlockedUsers = function(meta) {
                        $scope.meta.users.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        return $scope.fetchBlockedUsers({ isUpdate: true });
                    };

                    $scope.search = function(type) {
                        if (type === "logins") {
                            return $scope.fetchFailedLogins({ isUpdate: true });
                        } else if (type === "users") {
                            return $scope.fetchBlockedUsers({ isUpdate: true });
                        } else if (type === "brutes") {
                            return $scope.fetchBrutes({ isUpdate: true });
                        } else if (type === "excessiveBrutes") {
                            return $scope.fetchExcessiveBrutes({ isUpdate: true });
                        }
                    };

                    $scope.loadTable = function() {
                        $scope.loadingPageData = true;
                        var table = $scope.selectedTable;
                        if (table === "failedLogins") {
                            $scope.logins = [];
                            return $q.all([
                                $scope.fetchConfig(),
                                $scope.fetchFailedLogins()
                            ]).finally(function() {
                                $scope.loadingPageData = false;
                            });
                        } else if (table === "users") {
                            $scope.users = [];
                            return $q.all([
                                $scope.fetchConfig(),
                                $scope.fetchBlockedUsers()
                            ]).finally(function() {
                                $scope.loadingPageData = false;
                            });
                        } else if (table === "brutes") {
                            $scope.brutes = [];
                            return $q.all([
                                $scope.fetchConfig(),
                                $scope.fetchBrutes()
                            ]).finally(function() {
                                $scope.loadingPageData = false;
                            });
                        } else if (table === "excessiveBrutes") {
                            $scope.excessiveBrutes = [];
                            return $q.all([
                                $scope.fetchConfig(),
                                $scope.fetchExcessiveBrutes()
                            ]).finally(function() {
                                $scope.loadingPageData = false;
                            });
                        } else {
                            $scope.logins = [];
                            $scope.brutes = [];
                            $scope.excessiveBrutes = [];
                            $scope.users = [];
                            return $q.all([
                                $scope.fetchConfig(),
                                $scope.fetchFailedLogins(),
                                $scope.fetchBlockedUsers(),
                                $scope.fetchBrutes(),
                                $scope.fetchExcessiveBrutes()
                            ]).finally(function() {
                                $scope.loadingPageData = false;
                            });
                        }
                    };

                    $scope.refreshLogins = function() {
                        return $scope.loadTable();
                    };

                    $scope.clearHistory = function() {
                        $scope.clearingHistory = true;
                        return FailedLoginService.clearHistory()
                            .then(function(results) {
                                growl.success(LOCALE.maketext("The system cleared the tables."));
                                $scope.logins = [];
                                $scope.brutes = [];
                                $scope.excessiveBrutes = [];
                                $scope.users = [];

                                // update the pagination
                                updatePagination($scope.meta.logins, results);
                                updatePagination($scope.meta.brutes, results);
                                updatePagination($scope.meta.excessiveBrutes, results);
                                updatePagination($scope.meta.users, results);

                                // clear the filter
                                $scope.meta.logins.filterValue = "";
                                $scope.meta.brutes.filterValue = "";
                                $scope.meta.excessiveBrutes.filterValue = "";
                                $scope.meta.users.filterValue = "";

                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.clearingHistory = false;
                            });
                    };

                    $scope.fetchConfig = function() {
                        if (_.isEmpty(HulkdDataSource.config_settings)) {
                            HulkdDataSource.load_config_settings()
                                .then(function(data) {
                                    $scope.config_settings = data;
                                }, function(error) {
                                    growl.error(error);
                                });
                        } else {
                            $scope.config_settings = HulkdDataSource.config_settings;
                        }
                    };

                    $scope.fetchFailedLogins = function(options) {
                        if (options && options.isUpdate) {
                            $scope.updatingPageData = true;
                        } else {
                            $scope.loadingPageData = true;
                        }

                        return FailedLoginService.getFailedLogins($scope.meta.logins)
                            .then(function(results) {
                                $scope.logins = results.data;
                                updatePagination($scope.meta.logins, results);
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updatingPageData = false;
                            });
                    };

                    $scope.fetchBrutes = function(options) {
                        if (options && options.isUpdate) {
                            $scope.updatingPageData = true;
                        } else {
                            $scope.loadingPageData = true;
                        }

                        return FailedLoginService.getBrutes($scope.meta.brutes)
                            .then(function(results) {
                                $scope.brutes = results.data;
                                updatePagination($scope.meta.brutes, results);
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updatingPageData = false;
                            });
                    };

                    $scope.fetchExcessiveBrutes = function(options) {
                        if (options && options.isUpdate) {
                            $scope.updatingPageData = true;
                        } else {
                            $scope.loadingPageData = true;
                        }

                        return FailedLoginService.getExcessiveBrutes($scope.meta.excessiveBrutes)
                            .then(function(results) {
                                $scope.excessiveBrutes = results.data;
                                updatePagination($scope.meta.excessiveBrutes, results);
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updatingPageData = false;
                            });
                    };

                    $scope.fetchBlockedUsers = function(options) {
                        if (options && options.isUpdate) {
                            $scope.updatingPageData = true;
                        } else {
                            $scope.loadingPageData = true;
                        }

                        return FailedLoginService.getBlockedUsers($scope.meta.users)
                            .then(function(results) {
                                $scope.users = results.data;
                                updatePagination($scope.meta.users, results);
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updatingPageData = false;
                            });
                    };

                    $scope.unBlockAddress = function(address, $event) {
                        var element = $event.target;
                        if (element) {
                            if (/disabled/.test(element.className)) {

                            // do not run this again if the link is disabled
                                return;
                            } else {
                                element.className += " disabled";
                            }
                        }

                        return FailedLoginService.unBlockAddress(address)
                            .then(function(results) {
                                if (results.records_removed > 0) {

                                // remove from the one day block and blocked ip address lists
                                    $scope.removeBrute(address);
                                    growl.success(LOCALE.maketext("The system removed the block for: [_1]", address));
                                }
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.removeBrute = function(address) {
                        var item = _.find($scope.brutes, { ip: address });
                        if (item) {
                            $scope.brutes = _.difference($scope.brutes, [item]);
                            return true;
                        }

                        item = _.find($scope.excessiveBrutes, { ip: address });
                        if (item) {
                            $scope.excessiveBrutes = _.difference($scope.excessiveBrutes, [item]);
                            return true;
                        }

                        return false;
                    };

                    $scope.meta = {
                        pageSizes: [20, 50, 100],
                        maxPages: 0,
                        "brutes": {
                            sortDirection: "asc",
                            sortBy: "logintime",
                            sortType: "",
                            filterBy: "*",
                            filterCompare: "contains",
                            filterValue: "",
                            pageNumber: 1,
                            pageNumberStart: 0,
                            pageNumberEnd: 0,
                            pageSize: 20,
                            totalRows: 0
                        },
                        "excessiveBrutes": {
                            sortDirection: "asc",
                            sortBy: "logintime",
                            sortType: "",
                            filterBy: "*",
                            filterCompare: "contains",
                            filterValue: "",
                            pageNumber: 1,
                            pageNumberStart: 0,
                            pageNumberEnd: 0,
                            pageSize: 20,
                            totalRows: 0
                        },
                        "logins": {
                            sortDirection: "asc",
                            sortBy: "user",
                            sortType: "",
                            filterBy: "*",
                            filterCompare: "contains",
                            filterValue: "",
                            pageNumber: 1,
                            pageNumberStart: 0,
                            pageNumberEnd: 0,
                            pageSize: 20,
                            totalRows: 0
                        },
                        "users": {
                            sortDirection: "asc",
                            sortBy: "user",
                            sortType: "",
                            filterBy: "*",
                            filterCompare: "contains",
                            filterValue: "",
                            pageNumber: 1,
                            pageNumberStart: 0,
                            pageNumberEnd: 0,
                            pageSize: 20,
                            totalRows: 0
                        }
                    };

                    $scope.loadingPageData = true;
                    $scope.updatingPageData = false;
                    $scope.clearingHistory = false;

                    // this is the default table that we will show first
                    $scope.selectedTable = "failedLogins";

                    $scope.$on("$viewContentLoaded", function() {
                        $timeout(function() {
                            $scope.refreshLogins();
                        });
                    });

                    $scope.lookbackPeriodMinsDescription = function(config_settings) {
                        if (typeof config_settings === "undefined") {
                            return;
                        }

                        return LOCALE.maketext("The system counts Failed Logins for the duration of the specified period, which is currently set to [quant,_1,minute,minutes].", config_settings.lookback_period_min);
                    };

                    $scope.blockedUsersDescription = function(config_settings) {
                        if (typeof config_settings === "undefined") {
                            return;
                        }

                        return LOCALE.maketext("The system blocks users for [quant,_1,minute,minutes]. You can configure this value with the “[_2]” option.", config_settings.brute_force_period_mins, LOCALE.maketext("Brute Force Protection Period (in minutes)"));
                    };

                    $scope.blockedIPsDescription = function(config_settings) {
                        if (typeof config_settings === "undefined") {
                            return;
                        }

                        return LOCALE.maketext("The system blocks [asis,IP] addresses for [quant,_1,minute,minutes]. You can configure this value with the “[_2]” option.", config_settings.ip_brute_force_period_mins, LOCALE.maketext("IP Address-based Brute Force Protection Period (in minutes)"));
                    };

                }
            ]);

        return controller;
    }
);
