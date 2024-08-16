/*
# templates/tls_wizard_redirect/services/indexService.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/services/indexService',[
        "angular",
        "cjt/io/api",
        "cjt/util/query", // XXX FIXME remove when batch is in
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function(angular, API, QUERY, APIREQUEST) {

        var app = angular.module("App");
        var NO_MODULE = "";

        function indexServiceFactory($q, PAGE) {
            var indexService = {};
            indexService.get_domains = function() {
                return PAGE.data.domains;
            };

            indexService.remove_account = function(account) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "removeacct");
                apiCall.addArgument("user", account.username);
                apiCall.addArgument("keepdns", account.keep_dns ? "1" : "0");
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            indexService.get_account_summary = function(username) {

                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "accountsummary");
                apiCall.addArgument("user", username);
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            return indexService;
        }

        indexServiceFactory.$inject = ["$q", "PAGE"];
        return app.factory("indexService", indexServiceFactory);
    });

/*
# templates/killacct/views/RemoveController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/RemoveController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller(
            "ModalInstanceCtrl", [
                "$scope",
                "$uibModalInstance",
                "selected_accounts",
                function($scope, $uibModalInstance, selected_accounts) {
                    $scope.selected_accounts = selected_accounts.map(function(item) {
                        return item.username;
                    });
                    $scope.get_selected_accounts_text = function() {
                        return LOCALE.maketext("Check this box to acknowledge that you are aware that this will permanently delete the following accounts: [list_and_quoted,_1]", $scope.selected_accounts);
                    };
                    $scope.closeModal = function() {
                        $uibModalInstance.close();
                    };

                    $scope.runIt = function() {
                        $uibModalInstance.close(true);
                    };
                }
            ]
        );

        // Setup the controller
        var controller = app.controller(
            "RemoveController", [
                "$scope",
                "$filter",
                "$routeParams",
                "indexService",
                "growl",
                "$uibModal",
                function($scope, $filter, $routeParams, indexService, growl, $uibModal) {
                    var _growl_error = function(err) {
                        growl.error(_.escape(err));
                    };

                    var domains = indexService.get_domains();
                    var accounts = [];
                    angular.forEach(domains, function(value, key) {
                        accounts.push({
                            "username": value.username,
                            "owner": value.owner,
                            "domain": key,
                            "suspended": value.suspended ? LOCALE.maketext("Suspended") : LOCALE.maketext("Active"),
                            "selected": false,
                            "keep_dns": false
                        });
                    });

                    $scope.accounts = accounts;
                    $scope.removing_multiple_accounts = false;
                    $scope.confirming_accounts_removal = false;
                    $scope.show_only_suspended_accounts = false;

                    $scope.meta = {

                        // sort settings
                        sortReverse: false,
                        sortBy: "username",
                        sortDirection: "desc",

                        // pager settings
                        maxPages: 5,
                        totalItems: $scope.accounts.length,
                        currentPage: 1,
                        pageSize: 10,
                        pageSizes: [10, 20, 50, 100],
                        start: 0,
                        limit: 10,

                        filterValue: ""
                    };
                    $scope.showPager = true;
                    $scope.LOCALE = LOCALE;

                    $scope.removal_queue = [];

                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                        startFrom: $filter("startFrom"),
                        limitTo: $filter("limitTo")
                    };

                    // update the table on sort
                    $scope.sortList = function() {
                        $scope.fetch();
                    };

                    // update table on pagination changes
                    $scope.selectPage = function() {
                        $scope.fetch();
                    };

                    // update table on page size changes
                    $scope.selectPageSize = function() {
                        $scope.fetch();
                    };

                    $scope.request_delete_account = function(account) {
                        account.delete_requested = true;
                        if (account.summary) {
                            return true;
                        }
                        account.requesting_summary = true;
                        return indexService.get_account_summary(account.username).then(function(result) {
                            account.summary = result.data.pop();
                        }, _growl_error).finally(function() {
                            account.requesting_summary = false;
                        });
                    };

                    $scope.request_multi_delete_confirmation = function() {
                        var $uibModalInstance = $uibModal.open({
                            templateUrl: "updateModalContent.tmpl",
                            controller: "ModalInstanceCtrl",
                            resolve: {
                                "selected_accounts": $scope.get_selected_accounts
                            }
                        });

                        $uibModalInstance.result.then(function(proceed) {
                            if (proceed) {
                                $scope.confirming_accounts_removal = false;
                                return $scope.remove_selected();
                            }
                        });
                    };

                    $scope.searchList = function() {
                        $scope.fetch();
                    };

                    $scope.remove = function(account) {

                        $scope.removal_queue.push(account);
                        account.removing = true;

                        if ($scope.removal_queue.length === 1) {
                            return $scope.remove_next_queued();
                        } else {
                            growl.info(LOCALE.maketext("The system has added the account [_1] to the removal queue.", account.username));
                            account.delete_requested = false;
                        }
                    };

                    $scope.get_selected_accounts = function() {
                        $scope.selected_accounts = $filter("filter")($scope.accounts, {
                            selected: 1
                        });
                        if ($scope.selected_accounts.length === 0 && $scope.confirming_accounts_removal) {
                            $scope.confirming_accounts_removal = false;
                        }
                        return $scope.selected_accounts;
                    };

                    $scope.get_selected_account_names = function() {
                        var accounts = [];
                        var _accounts = $scope.get_selected_accounts();
                        angular.forEach(_accounts, function(account) {
                            accounts.push(account.username);
                        });
                        return accounts;
                    };

                    $scope.remove_next_queued = function() {

                        /* prevent multiple running */
                        if ($scope.removing_multiple_accounts) {
                            return;
                        }

                        $scope.removing_multiple_accounts = true;

                        return _remove_next_queued();

                    };

                    function _remove_next_queued() {

                        var account = $scope.removal_queue.shift();

                        var acct_growl = growl.info(LOCALE.maketext("Starting removal of “[_1]”", account.username));

                        return indexService.remove_account(account).then(function() {
                            acct_growl.setText(LOCALE.maketext("Successfully removed “[_1]”", account.username));
                            acct_growl.severity = "success";
                            account.removing = false;
                            $scope.accounts = $filter("filter")($scope.accounts, function(acct, key) {
                                if (acct.username === account.username) {
                                    $scope.accounts[key].removing = false;
                                    return false;
                                }
                                return true;
                            });
                            $scope.fetch();

                            /* are there more to remove, go again */
                            if ($scope.removal_queue.length) {
                                return _remove_next_queued();
                            }

                            /* otherwise we're done */
                            $scope.removing_multiple_accounts = false;
                            return true;
                        }, function(error) {
                            account.removing = false;
                            _growl_error(error);
                            $scope.clear_removal_queue();
                            $scope.removing_multiple_accounts = false;
                        });
                    }

                    $scope.get_table_showing_text = function() {
                        return LOCALE.maketext("Showing [numf,_1] - [numf,_2] of [quant,_3,item,items]", $scope.meta.start, $scope.meta.limit, $scope.meta.totalItems);
                    };

                    $scope.selected_account_name_string = function() {
                        return LOCALE.maketext("[list_and_quoted,_1]", $scope.get_selected_account_names());
                    };

                    $scope.cancel_removal_label = function() {
                        return LOCALE.maketext("Cancel account removals ([_1])", $scope.removal_queue.length);
                    };

                    $scope.clear_removal_queue = function() {
                        var usernames = [];
                        angular.forEach($scope.removal_queue, function(acct) {
                            acct.removing = false;
                            usernames.push(acct.username);
                        });
                        $scope.removal_queue = [];
                        var accounts_being_removed = filters.filter($scope.accounts, {
                            removing: true
                        }).map(function(acct) {
                            return acct.username;
                        });
                        if (usernames.length) {
                            growl.info(LOCALE.maketext("The system will not remove the following [numerate,_1,user,users]: [list_and_quoted,_1]", usernames));
                        }
                        if (accounts_being_removed.length) {
                            growl.warning(LOCALE.maketext("The system cannot abort the deletion of the following [numerate,_1,user,users]: [list_and_quoted,_1]", accounts_being_removed));
                        }
                    };

                    $scope.remove_selected = function() {

                        var _accounts = $scope.get_selected_accounts();
                        if (!_accounts.length) {
                            return;
                        }
                        angular.forEach(_accounts, function(acct) {
                            acct.removing = true;
                            acct.selected = 0;
                            $scope.removal_queue.push(acct);
                        });

                        /* because all selected items are deselected return this to false */
                        $scope.account_checkbox_control = false;

                        $scope.remove_next_queued();
                        $scope.update_selected();

                    };

                    $scope.toggleCheckAll = function(arr, attr, val) {
                        arr.forEach(function(item, index) {

                            /* prevent an item from being selected if it's being removed */
                            if (attr === "selected" && val && arr[index].removing) {
                                return;
                            }
                            arr[index][attr] = val ? 1 : 0;
                        });
                        $scope.update_selected();
                    };

                    $scope.update_selected = function() {
                        $scope.get_selected_accounts();
                    };

                    var min_value_in_array = function(arr) {
                        var min_value = arr[0];
                        for (var x = 0; x < arr.length; x++) {
                            min_value = arr[x] < min_value ? arr[x] : min_value;
                        }

                        return min_value;
                    };

                    $scope.wrappedDeleteText = function(username) {
                        return LOCALE.maketext("Are you sure you want to remove the account “[_1]”?", username) + "<br />" + LOCALE.maketext("This will permanently remove all of the user’s data from the system.");
                    };

                    $scope.get_suspended_accounts = function() {
                        return $filter("filter")($scope.accounts, {
                            suspended: LOCALE.maketext("Suspended")
                        });
                    };

                    // update table
                    $scope.fetch = function() {
                        var filteredList = [];

                        // filter list based on search text
                        if ($scope.meta.filterValue !== "") {
                            filteredList = filters.filter($scope.accounts, $scope.meta.filterValue, false);
                        } else {
                            filteredList = $scope.accounts;
                        }

                        if ($scope.show_only_suspended_accounts) {
                            filteredList = $scope.get_suspended_accounts();
                        }

                        // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }

                        // update the total items after search
                        $scope.meta.totalItems = filteredList.length;

                        // filter list based on page size and pagination
                        if ($scope.meta.totalItems > min_value_in_array($scope.meta.pageSizes)) {
                            var start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                            var limit = $scope.meta.pageSize;

                            filteredList = filters.limitTo(filters.startFrom(filteredList, start), limit);
                            $scope.showPager = true;

                            // table statistics
                            $scope.meta.start = start + 1;
                            $scope.meta.limit = start + filteredList.length;

                        } else {

                            // hide pager and pagination
                            $scope.showPager = false;

                            if (filteredList.length === 0) {
                                $scope.meta.start = 0;
                            } else {

                                // table statistics
                                $scope.meta.start = 1;
                            }

                            $scope.meta.limit = filteredList.length;
                        }

                        $scope.filteredAccounts = filteredList;
                        $scope.update_selected();

                        return filteredList;
                    };

                    // first page load


                    if ($routeParams["user"]) {
                        angular.forEach($scope.accounts, function(acct) {
                            if (acct.username === $routeParams["user"]) {
                                $scope.meta.filterValue = acct.username;
                                $scope.request_delete_account(acct);
                            }
                        });
                    }

                    $scope.fetch();

                }
            ]
        );

        return controller;
    }
);

/* global define, require, PAGE */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute"
    ],
    function(angular, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "app/services/indexService",
                    "app/views/RemoveController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    app.config(["growlProvider", "$httpProvider",
                        function(growlProvider, $httpProvider) {
                            growlProvider.globalReversedOrder(true);
                            growlProvider.globalTimeToLive({ success: -1, warning: -1, info: -1, error: -1 });
                            $httpProvider.useApplyAsync(true);
                        }
                    ]);


                    // If using views
                    app.controller("BaseController", ["$rootScope", "$scope", "$route", "$location",
                        function($rootScope, $scope, $route, $location) {

                            $scope.loading = false;

                            // Convenience functions so we can track changing views for loading purposes
                            $rootScope.$on("$routeChangeStart", function() {
                                $scope.loading = true;
                            });
                            $rootScope.$on("$routeChangeSuccess", function() {
                                $scope.loading = false;
                            });
                            $rootScope.$on("$routeChangeError", function() {
                                $scope.loading = false;
                            });
                            $scope.current_route_matches = function(key) {
                                return $location.path().match(key);
                            };
                            $scope.go = function(path) {
                                $location.path(path);
                            };
                        }
                    ]);

                    // viewName

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup a route - copy this to add additional routes as necessary
                            $routeProvider.when("/:user?", {
                                controller: "RemoveController",
                                templateUrl: CJT.buildFullPath("killacct/views/RemoveView.ptt"),
                                resolve: {}
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": "/"
                            });

                        }
                    ]);

                    // end of using views

                    // Initialize the application
                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

