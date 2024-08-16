/*
# templates/mailbox_converter/services/indexService.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/indexService',[
        "angular",
    ],
    function(angular) {

        var app = angular.module("App");

        function indexServiceFactory() {
            var indexService = {};
            var _format;
            var _accounts;

            indexService.set_accounts = function(accounts) {
                _accounts = accounts;
                return _accounts;
            };

            indexService.get_accounts = function() {
                return _accounts;
            };

            indexService.set_format = function(format) {
                if (format !== _format && Array.isArray(_accounts)) {

                    // reset selected accounts in case we swap our maildir choice
                    _accounts.forEach(function(item) {
                        item.selected = 0;
                    });
                }
                _format = format;
                return _format;
            };

            indexService.get_format = function() {
                return _format;
            };

            return indexService;
        }

        return app.factory("indexService", indexServiceFactory);
    });

/*
# templates/mailbox_converter/views/selectAccountsController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/selectAccountsController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/triStateCheckbox",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "selectAccountsController", [
                "$scope",
                "$filter",
                "indexService",
                "$route",
                function($scope, $filter, indexService) {
                    $scope.$parent.ready = false;

                    var selected_mailbox_format = indexService.get_format();

                    // Get the stored accounts in case we've come back to this step after selecting
                    var _accounts = indexService.get_accounts();
                    var accounts = [];
                    angular.forEach(_accounts, function(value) {
                        value.selected = value.selected || 0;
                        accounts.push( value );
                    });

                    $scope.accounts = accounts;

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

                        filterValue: "",
                    };
                    $scope.showPager = true;

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

                    $scope.searchList = function() {
                        $scope.fetch();
                    };

                    $scope.toggleCheckAll = function(arr, attr, val) {
                        arr.forEach(function(item, index) {
                            arr[index][attr] = val;
                        });
                    };

                    var min_value_in_array = function(arr) {
                        var min_value = arr[0];
                        for (var x = 0; x < arr.length; x++) {
                            min_value = arr[x] < min_value ? arr[x] : min_value;
                        }

                        return min_value;
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

                        filteredList = filters.filter(filteredList, { "mailbox_format": "!" + selected_mailbox_format });

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

                        return filteredList;
                    };

                    // first page load
                    $scope.fetch();

                    $scope.$watch("accounts", function( newValue ) {
                        indexService.set_accounts(newValue);
                        var selected_accounts = filters.filter(newValue, { "selected": 1 });
                        if (selected_accounts.length) {
                            $scope.$parent.ready = true;
                        } else {
                            $scope.$parent.ready = false;
                        }
                    }, true
                    );

                    $scope.pagination_msg = function() {
                        return LOCALE.maketext("Showing [numf,_1] - [numf,_2] of [quant,_3,item,items]", $scope.meta.start, $scope.meta.limit, $scope.meta.totalItems);
                    };
                }
            ]
        );

        return controller;
    }
);

/*
# templates/killacct/views/selectFormatController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/selectFormatController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "selectFormatController", [
                "$scope",
                "indexService",
                function($scope, indexService) {

                    $scope.$parent.ready = false;
                    $scope.selected_format = indexService.get_format();
                    var _accounts = indexService.get_accounts();

                    if ($scope.selected_format) {
                        $scope.$parent.ready = true;
                    }

                    var _maildir_count = {};
                    _accounts.forEach(function(item) {
                        if (item.mailbox_format in _maildir_count) {
                            _maildir_count[item.mailbox_format] += 1;
                        } else {
                            _maildir_count[item.mailbox_format] = 1;
                        }
                    });

                    $scope.maildir_count = _maildir_count;

                    $scope.select = function(format) {
                        $scope.selected_format = indexService.set_format(format);
                        $scope.$parent.ready = true;
                    };

                    $scope.format_is = function(format) {
                        return format === $scope.selected_format;
                    };

                    $scope.number_of_accounts_msg = function(type) {
                        return LOCALE.maketext("[quant,_1,account,accounts,No accounts] [numerate,_1,uses,use] this format.", $scope.maildir_count[type] || 0);
                    };
                }
            ]
        );

        return controller;
    }
);

/*
# templates/mailbox_converter/views/confirmController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/confirmController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "confirmController", [
                "$scope",
                "$filter",
                "indexService",
                function($scope, $filter, indexService) {

                    $scope.$parent.ready = false;
                    var _accounts = indexService.get_accounts();

                    $scope.accounts = $filter("filter")(_accounts, { "selected": 1 });
                    $scope.chosen_mailbox_format = indexService.get_format();

                    if (!$scope.chosen_mailbox_format) {
                        $scope.$parent.go(0);
                    } else if (!$scope.accounts || !$scope.accounts.length) {
                        $scope.$parent.go(1);
                    }

                    $scope.selected_accounts_msg = LOCALE.maketext("You selected [quant,_1,account,accounts] to convert to [_2].", $scope.accounts.length, $scope.chosen_mailbox_format);
                }
            ]
        );

        return controller;
    }
);

/*
# templates/mailbox_converter/index.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute",
        "ngAnimate",
    ],
    function(angular, CJT, LOCALE) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "ngAnimate"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "cjt/services/whm/breadcrumbService",
                    "app/services/indexService",
                    "app/views/selectAccountsController",
                    "app/views/selectFormatController",
                    "app/views/confirmController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    var steps = [
                        {
                            route: "select_format",
                            breadcrumb: LOCALE.maketext("Select Format"),
                            templateUrl: CJT.buildFullPath("mailbox_converter/views/selectFormatView.ptt"),
                            controller: "selectFormatController",
                            default: true,
                            is_ready: function requires($q) {
                                return $q(function(resolve) {
                                    resolve("");
                                });
                            }
                        },
                        {
                            route: "select_accounts",
                            breadcrumb: LOCALE.maketext("Select Accounts"),
                            templateUrl: CJT.buildFullPath("mailbox_converter/views/selectAccountsView.ptt"),
                            controller: "selectAccountsController",
                            is_ready: function requires($q, service) {
                                return $q(function(resolve, reject) {
                                    if (!!service.get_format()) {
                                        resolve("");
                                    } else {
                                        reject("Missing necessary data");
                                    }
                                });
                            }
                        },
                        {
                            route: "finalize",
                            breadcrumb: LOCALE.maketext("Review and Finalize"),
                            templateUrl: CJT.buildFullPath("mailbox_converter/views/confirmView.ptt"),
                            controller: "confirmController",
                            is_ready: function requires($q, service) {
                                var _accounts = service.get_accounts();
                                var has_selected_account = false;
                                if (_accounts) {
                                    for (var x = 0; x < _accounts.length; x++) {
                                        if (_accounts[x].selected) {
                                            has_selected_account = true;
                                            break;
                                        }
                                    }
                                }
                                return $q(function(resolve, reject) {

                                    if (!!service.get_format() && has_selected_account) {
                                        resolve("");
                                    } else {
                                        reject("Missing necessary data");
                                    }
                                });
                            }
                        }
                    ];

                    // If using views
                    app.controller("BaseController", ["$rootScope", "$scope", "$route", "$location", "indexService", "$q", "PAGE", "$window",
                        function($rootScope, $scope, $route, $location, indexService, $q, PAGE, $window) {

                            $scope.steps = steps;
                            $scope.current_step = 0;
                            $scope.LOCALE = LOCALE;
                            var _loading = false;


                            indexService.set_accounts(PAGE.data.accounts);

                            // Convenience functions so we can track changing views for loading purposes
                            $rootScope.$on("$routeChangeStart", function(event, currentRoute, previousRoute) {

                                // If the user hits the back button we want to verify that we adjust the current_page
                                //  so the UI updates appropriately
                                if (previousRoute && typeof previousRoute.$$route !== "undefined" && previousRoute.$$route.page === $scope.current_step) {
                                    $scope.current_step = currentRoute.$$route.page;
                                }
                                _loading = true;
                            });
                            $rootScope.$on("$routeChangeSuccess", function() {
                                _loading = false;
                            });
                            $rootScope.$on("$routeChangeError", function(event, currentRoute, previousRoute) {
                                _loading = false;

                                // Handles the case where user uses forward button to get onto bad route
                                if (previousRoute) {
                                    $location.path(steps[previousRoute.$$route.page].route).replace();
                                    return;
                                }

                                // handles the case when user manually goes to bad route
                                $location.path(steps[$scope.current_step].route).replace();
                            });
                            $scope.current_route_matches = function(key) {
                                return $location.path().match(key);
                            };

                            $scope.get_view_styles = function() {
                                var _view_classes = [];
                                if (_loading) {
                                    _view_classes.push("view-disabled");
                                }
                                return _view_classes;
                            };

                            $scope.submit_form = function(form_id) {
                                document.getElementById(form_id).submit();
                            };

                            $scope.go_back = function(index, current_step) {
                                if (typeof index === "undefined") {
                                    $window.history.back();
                                    $scope.current_step = $scope.current_step - 1;
                                    return;
                                } else {
                                    var loop_counter = current_step - index;
                                    while (loop_counter > 0) {
                                        $window.history.back();
                                        loop_counter--;
                                    }
                                    $scope.current_step = index;
                                }
                            };

                            $scope.go = function(index, isValid) {
                                if (!isValid) {
                                    return;
                                }
                                steps[index].is_ready($q, indexService).then(function() {
                                    $location.path(steps[index].route);
                                    $scope.current_step = index;
                                }, function() {

                                    // don't do anything in the case they aren't allowed to go forward
                                });
                            };
                        }
                    ]);

                    app.config(["$routeProvider",
                        function($routeProvider) {
                            var page_number = 0;
                            steps.forEach(function(step) {
                                $routeProvider.when("/" + step.route, {
                                    controller: step.controller,
                                    templateUrl: step.templateUrl,
                                    breadcrumb: step.breadcrumb,
                                    resolve: {
                                        data: ["$q", "indexService", step.is_ready] // this is called twice on page change -- could be optimized
                                    },
                                    page: page_number++
                                });

                                if (step.hasOwnProperty("default") && step.default) {
                                    $routeProvider.otherwise({
                                        "redirectTo": "/" + step.route
                                    });
                                }
                            });
                        }
                    ]);

                    app.run([
                        "breadcrumbService",
                        function(breadcrumbService) {
                            breadcrumbService.initialize();
                        }
                    ]);

                    BOOTSTRAP();

                });

            return app;
        };
    }
);

