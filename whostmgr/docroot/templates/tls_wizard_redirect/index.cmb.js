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
        "cjt/util/query",   // XXX FIXME remove when batch is in
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

            indexService.get_enabled_provider_count = function() {
                return PAGE.data.enabled_provider_count;
            };

            indexService.get_default_theme = function() {
                return PAGE.data.default_theme;
            };

            indexService.check_account_has_feature = function(username, feature) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "verify_user_has_feature");
                apiCall.addArgument("user", username);
                apiCall.addArgument("feature", feature);
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

            indexService.check_user_has_features = function(user, features) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "batch");

                var calls = {};
                features.forEach( function(p, i) {
                    calls["command-" + i] = {
                        feature: p,
                    };
                } );

                for (var query_key in calls) {
                    if ( calls.hasOwnProperty(query_key) ) {
                        calls[query_key].user = user;

                        var this_call_query = QUERY.make_query_string( calls[query_key] );
                        apiCall.addArgument(query_key, "verify_user_has_feature?" + this_call_query);
                    }
                }

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

            indexService.force_enable_features_for_user = function(user, features) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "add_override_features_for_user");
                apiCall.addArgument("user", user);
                apiCall.addArgument("features", JSON.stringify(features));
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

            indexService.create_user_session = function(user) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "create_user_session");
                apiCall.addArgument("user", user);
                apiCall.addArgument("service", "cpaneld");
                apiCall.addArgument("app", "SSL_TLS_Wizard");
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

            indexService.enable_cpstore_provider = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "enable_market_provider");
                apiCall.addArgument("name", "cPStore");
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

            indexService.set_user_theme_to_default_theme = function(user) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                var defaultTheme = PAGE.data.default_theme;

                apiCall.initialize(NO_MODULE, "modifyacct");
                apiCall.addArgument("user", user);
                apiCall.addArgument("RS", defaultTheme);
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

            indexService.set_user_style_to_retro = function(user) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "cpanel");
                apiCall.addArgument("user", user);
                apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                apiCall.addArgument("cpanel_jsonapi_module", "Styles");
                apiCall.addArgument("cpanel_jsonapi_func", "update");
                apiCall.addArgument("name", "retro");
                apiCall.addArgument("type", "default");
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


            indexService.get_user_account_info = function(user) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "accountsummary");
                apiCall.addArgument("user", user);
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
# templates/tls_wizard_redirect/views/purchaseRedirectController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/purchaseRedirectController',[
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

        // Setup the controller
        var controller = app.controller(
            "purchaseRedirectController", [
                "$scope",
                "$filter",
                "indexService",
                "growl",
                function($scope, $filter, indexService, growl) {
                    var _growl_error = function(err) {
                        growl.error(_.escape(err));
                    };
                    var defaultTheme = indexService.get_default_theme();

                    var domains = indexService.get_domains();
                    var accounts = [];
                    var need_to_enable_provider = indexService.get_enabled_provider_count() ? false : true;
                    angular.forEach(domains, function(value, key) {
                        accounts.push( { "username": value, "domain": key } );
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
                        limitTo: $filter("limitTo"),
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

                        // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }

                        // update the total items after search
                        $scope.meta.totalItems = filteredList.length;

                        // filter list based on page size and pagination
                        if ($scope.meta.totalItems > min_value_in_array($scope.meta.pageSizes)) {
                            var start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                            var limit = ( $scope.meta.pageSize > 0 ) ? $scope.meta.pageSize : $scope.meta.totalItems;

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

                    $scope.process_user_and_generate_login_url = function(user, domain) {

                        if (need_to_enable_provider) {

                            // Do this immediately so fast clickers don't trigger multiple updates
                            need_to_enable_provider = false;
                            return indexService.enable_cpstore_provider().then(function(success) {
                                growl.success(LOCALE.maketext("Because no other providers are enabled, the system enabled the [asis,cPanel Store] provider."));
                                return check_user_has_features_then_generate_session(user, domain);
                            }, function(error) {
                                need_to_enable_provider = true;
                                _growl_error(error);
                            });
                        } else {
                            return check_user_has_features_then_generate_session(user, domain);
                        }
                    };

                    $scope.get_pagination_msg = function() {
                        return LOCALE.maketext("Displaying [numf,_1] to [numf,_2] out of [quant,_3,item,items]", $scope.meta.start, $scope.meta.limit, $scope.meta.totalItems);
                    };

                    var check_user_has_features_then_generate_session = function(user, domain) {
                        var required_features = ["market", "tls_wizard", "sslinstall"];
                        var features_to_enable = {};

                        return indexService.check_user_has_features(user, required_features).then(function(success) {
                            for (var x = 0; x < success.data.length; x++) {
                                var return_data = success.data[x].parsedResponse.data;
                                if (!return_data.has_feature) {

                                    // For every query push the feature we asked about into a store if the user doesn't have it
                                    features_to_enable[return_data.query_feature] = 1;
                                    features_to_enable["should_be_set"] = true;
                                }
                            }
                            if (features_to_enable.should_be_set) {
                                delete features_to_enable.should_be_set;
                                return indexService.force_enable_features_for_user(user, features_to_enable).then(function(success) {
                                    var features = Object.keys(features_to_enable).sort();

                                    growl.success(LOCALE.maketext("The system enabled the [numerate,_1,feature,features] [list_and_quoted,_2] for the user “[_3]” to ensure access to the “[_4]”.", features.length, features, user, LOCALE.maketext("[asis,SSL]/[asis,TLS] Wizard")));
                                    return get_user_session(user, domain);
                                }, _growl_error);
                            } else {
                                return get_user_session(user, domain);
                            }
                        }, _growl_error);
                    };

                    var get_user_session = function(user, domain) {

                        var _create_user_session = function() {
                            return indexService.create_user_session(user).then(function(success) {
                                var generated_url = success.data.url + "#/purchase-certificates/" + domain;

                                // Try to open but will most likely be blocked by browser default pop-up blocker - that's ok!
                                window.open(generated_url, "_blank");
                                growl.success(LOCALE.maketext("Click to continue as the “[_1]” user and purchase an [asis,SSL] certificate.", _.escape(user)), {
                                    ttl: -1,
                                    variables: {
                                        buttonLabel: "Purchase SSL",
                                        showAction: true,
                                        action: function() {

                                            // your callback function goes here
                                            window.open(generated_url, "_blank");
                                        },
                                    },
                                });
                            }, _growl_error);
                        };

                        return indexService.get_user_account_info(user).then(function(success) {

                            // if theme is x3 we should set the theme to retro so the redirect works properly
                            if (success.data[0].theme === "x3") {

                                // set the theme to the default theme
                                return indexService.set_user_theme_to_default_theme(user).then(function(success) {

                                    // ...and the style to retro
                                    return indexService.set_user_style_to_retro(user).then(function(success) {

                                        // if we succeed let the user know we updated the targeted users styles/theme
                                        growl.success(LOCALE.maketext("The system changed the theme for user “[_1]” to “[_2]”, with the “[asis,Retro]” style, to support this feature.", _.escape(user)), {
                                            ttl: -1,
                                        }, defaultTheme);

                                        // ...and make a call to create the user session
                                        return _create_user_session();
                                    }, function(error) {

                                        // failed to set the style but we have an updated theme, should roll back theme to x3 then give an error
                                        growl.error(LOCALE.maketext("You cannot redirect to this account because it does not have theme support for this feature."));
                                    });
                                }, function(error) {

                                    // we were unable to set the user theme to the default theme so lets let them know why we won't proceed
                                    growl.error(LOCALE.maketext("You cannot redirect to this account because it does not have theme support for this feature."));
                                });
                            } else {

                                // if they don't have x3 we assume they have support
                                return _create_user_session();
                            }
                        }, function(error) {

                            // ...if we fail to fetch user info there is probably something bad going on so lets bail out early
                            growl.error(LOCALE.maketext("The system failed to fetch the user’s account information because of the following error: [_1]", _.escape(error)));
                            return;
                        });
                    };
                },
            ]
        );

        return controller;
    }
);

/*
# templates/tls_wizard_redirect/index.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */


define(
    'app/index',[
        "angular",
        "cjt/core",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute"
    ],
    function(angular, CJT) {

        CJT.config.html5Mode = false;

        return function() {

            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
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
                    "app/views/purchaseRedirectController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

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
                            $routeProvider.when("/purchaseRedirect", {
                                controller: "purchaseRedirectController",
                                templateUrl: CJT.buildFullPath("tls_wizard_redirect/views/purchaseRedirectView.ptt"),
                                resolve: {}
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": "/purchaseRedirect"
                            });

                        }
                    ]);

                    // end of using views

                    BOOTSTRAP();

                });

            return app;
        };
    }
);

