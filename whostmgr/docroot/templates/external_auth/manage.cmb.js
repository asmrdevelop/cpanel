/*
# templates/external_auth/services/UsersService.js       Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    'app/services/UsersService',[
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/modules",
    ],
    function(angular, _, CJT, PARSE, API, APIREQUEST) {
        "use strict";

        var app = angular.module("App");

        function UsersServiceFactory($q) {
            var users = [];
            var UsersService = {};

            UsersService.get_users = function() {
                return users;
            };

            UsersService.fetch_users = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_users_authn_linked_accounts");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                deferred.promise.then(function(result) {
                    users = [];
                    angular.forEach(result.data, function(row) {
                        var user = UsersService.get_user_by_username(row.username);
                        if (!user) {
                            user = {
                                username: row.username,
                                links: {}
                            };
                            users.push(user);
                        }
                        if (!user.links[row.provider_protocol]) {
                            user.links[row.provider_protocol] = {};
                        }
                        if (!user.links[row.provider_protocol][row.provider_id]) {
                            user.links[row.provider_protocol][row.provider_id] = {};
                        }
                        user.links[row.provider_protocol][row.provider_id][row.subject_unique_identifier] = {
                            link_type: row.link_type,
                            preferred_username: row.preferred_username
                        };

                    });
                });

                return deferred.promise;
            };
            UsersService.get_user_by_username = function(username) {
                for (var i = 0; i < users.length; i++) {
                    if (users[i].username === username) {
                        return users[i];
                    }
                }
            };
            UsersService.unlink_provider = function(username, subject_unique_identifier, provider) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "unlink_user_authn_provider");
                apiCall.addArgument("username", username);
                apiCall.addArgument("subject_unique_identifier", subject_unique_identifier);
                apiCall.addArgument("provider_id", provider);

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

            return UsersService;
        }
        UsersServiceFactory.$inject = ["$q", "growl"];
        return app.factory("UsersService", UsersServiceFactory);
    });

/*
# templates/external_auth/services/ProvidersService.js   Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    'app/services/ProvidersService',[
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/decorators/growlDecorator",
        "cjt/modules",
    ],
    function(angular, _, CJT, PARSE, API, APIREQUEST) {
        "use strict";

        var app = angular.module("App");

        function ProvidersServiceFactory($q, growl) {
            var providers = [];
            var ProvidersService = {};

            function _build_batch_command(call, params) {
                var command_str = call;

                if (params) {
                    var command_params = [];
                    angular.forEach(params, function(value, key) {
                        command_params.push(key + "=" + encodeURIComponent(value));
                    });

                    command_str += "?" + command_params.join("&");
                }

                return command_str;
            }

            ProvidersService.get_providers = function() {
                return providers;
            };
            ProvidersService.get_enabled_providers = function(service) {
                var enabled_providers = [];
                angular.forEach(providers, function(provider) {
                    if (provider[service + "_enabled"]) {
                        enabled_providers.push(provider);
                    }
                });
                return enabled_providers;
            };

            ProvidersService.fetch_providers = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_available_authentication_providers");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                deferred.promise.then(function(result) {
                    providers = [];
                    angular.forEach(result.data, function(provider) {
                        provider = angular.extend(provider, {
                            enable: function(service) {
                                return ProvidersService.enable_provider(service, provider).then(function() {
                                    growl.success(LOCALE.maketext("The system has successfully enabled the “[_1]” provider in “[_2]”.", provider.display_name, service));
                                }, function(error) {
                                    growl.error(LOCALE.maketext("The system could not enable the “[_1]” provider in “[_2]”. The following error occurred: [_3]", provider.display_name, service, error));
                                });
                            },
                            disable: function(service) {
                                return ProvidersService.disable_provider(service, provider).then(function() {
                                    growl.success(LOCALE.maketext("The system has successfully disabled the “[_1]” provider in “[_2]”.", provider.display_name, service));
                                }, function(error) {
                                    growl.error(LOCALE.maketext("The system could not disable the “[_1]” provider in “[_2]”. The following error occurred: [_3]", provider.display_name, service, error));
                                });
                            },
                            toggle_status: function(service) {
                                return provider[service + "_enabled"] ? provider.disable(service) : provider.enable(service);
                            }
                        });
                        this.push(provider);
                    }, providers);
                });

                return deferred.promise;
            };
            ProvidersService.enable_provider = function(service, item) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "enable_authentication_provider");
                apiCall.addArgument("provider_id", item.id);
                apiCall.addArgument("service_name", service);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                            item[service + "_enabled"] = true;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };
            ProvidersService.disable_provider = function(service, item) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "disable_authentication_provider");
                apiCall.addArgument("provider_id", item.id);
                apiCall.addArgument("service_name", service);


                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                            item[service + "_enabled"] = false;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };
            ProvidersService.set_provider_display_configurations = function(provider_id, configurations) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "set_provider_display_configurations");
                apiCall.addArgument("service_name", "cpaneld");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addArgument("configurations", JSON.stringify(configurations));

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
            ProvidersService.set_provider_client_configurations = function(provider_id, configurations) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "set_provider_client_configurations");
                apiCall.addArgument("service_name", "cpaneld");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addArgument("configurations", JSON.stringify(configurations));

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
            ProvidersService.get_provider_client_configurations = function(provider_id) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_provider_client_configurations");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addArgument("service_name", "cpaneld");

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
            ProvidersService.get_provider_configuration_fields = function(provider_id) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_provider_configuration_fields");
                apiCall.addArgument("service_name", "cpaneld");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addSorting("display_order");

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
            ProvidersService.get_provider_by_id = function(provider_id) {
                for (var i = 0; i < providers.length; i++) {
                    var provider = providers[i];
                    if (provider.id === provider_id) {
                        return provider;
                    }
                }
            };

            ProvidersService.get_provider_display_configurations = function(provider_id) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_provider_display_configurations");
                apiCall.addArgument("provider_id", provider_id);

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

            /*
                client_configs: object of hashed keys to update
            */
            ProvidersService.save_provider_configurations = function(provider_id, client_configs, display_configs) {

                // This gets added to in the foreach loop. Format is necessary for batching.
                var params = {
                    command: []
                };

                if (display_configs) {

                    angular.forEach(display_configs, function(config) {
                        params.command.push(_build_batch_command("set_provider_display_configurations", {
                            provider_id: provider_id,
                            service_name: config.service_name,
                            configurations: JSON.stringify(config.configs)
                        }));
                    });
                }

                params.command.push(_build_batch_command("set_provider_client_configurations", {
                    provider_id: provider_id,
                    service_name: "cpaneld",
                    configurations: JSON.stringify(client_configs)
                }));

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "batch");
                apiCall.addArgument("command", params.command);

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

            return ProvidersService;
        }
        ProvidersServiceFactory.$inject = ["$q", "growl"];
        return app.factory("ProvidersService", ProvidersServiceFactory);
    });

/*
# templates/external_auth/views/UsersController.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W003 */

// Then load the application dependencies
define(
    'app/views/UsersController',[
        "angular",
        "lodash",
        "cjt/modules",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/decorators/paginationDecorator",
    ],
    function(angular, _) {

        var UsersController = function($scope, $filter, $location, UsersService, ProvidersService) {
            var _this = this;

            $scope.users = [];
            $scope.providers = [];

            // meta information
            $scope.meta = {

                // sort settings
                sortReverse: false,
                sortBy: "label",
                sortDirection: "asc",

                // pager settings
                maxPages: 5,
                totalItems: $scope.users.length,
                currentPage: 1,
                pageSize: 20,
                pageSizes: [20, 50, 100, 500],
                start: 0,
                limit: 10,

                filterValue: "",
            };

            // initialize filter list
            $scope.filteredList = $scope.users;
            $scope.showPager = true;

            /**
             * Initialize the variables required for
             * row selections in the table.
             */
            $scope.checkdropdownOpen = false;

            // This updates the selected tracker in the 'Selected' Badge.
            $scope.totalSelectedUsers = 0;
            var selectedUserList = [];

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

            $scope.configureUser = function(provider) {
                $location.path("/providers/" + provider.id);
            };

            // update table on search
            $scope.searchList = function() {
                $scope.fetch();
            };

            // have your filters all in one place - easy to use
            var filters = {
                filter: $filter("filter"),
                orderBy: $filter("orderBy"),
                startFrom: $filter("startFrom"),
                limitTo: $filter("limitTo")
            };

            $scope.manage_user = function(username) {
                $location.path("/users/" + username);
            };

            $scope.get_providers_for = function(user) {
                var providers = [];
                angular.forEach(user.links, function(provider_type) {
                    angular.forEach(provider_type, function(value, key) {
                        var provider = ProvidersService.get_provider_by_id(key);
                        if (provider) {
                            providers.push(provider);
                        }
                    });
                });
                return providers;
            };

            // update table
            $scope.fetch = function() {
                var filteredList = [];

                // filter list based on search text
                if ($scope.meta.filterValue !== "") {
                    filteredList = filters.filter($scope.users, $scope.meta.filterValue, false);
                } else {
                    filteredList = $scope.users;
                }

                // sort the filtered list
                if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                    filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                }

                // update the total items after search
                $scope.meta.totalItems = filteredList.length;

                // filter list based on page size and pagination
                if ($scope.meta.totalItems > _.min($scope.meta.pageSizes)) {
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

                var countNonSelected = 0;

                // Add rowSelected attribute to each item in the list to track selections.
                filteredList.forEach(function(item) {

                    // Select the rows if they were previously selected on this page.
                    if (selectedUserList.indexOf(item.id) !== -1) {
                        item.rowSelected = true;
                    } else {
                        item.rowSelected = false;
                        countNonSelected++;
                    }
                });

                $scope.filteredList = filteredList;

                // Clear the 'Select All' checkbox if at least one row is not selected.
                $scope.allRowsSelected = (filteredList.length > 0) && (countNonSelected === 0);

                return filteredList;
            };

            $scope.init = function() {
                $scope.users = UsersService.get_users();
                $scope.providers = ProvidersService.get_enabled_providers();
                $scope.fetch();
            };

            // first page load
            $scope.init();

            return _this;
        };

        var app = angular.module("App");

        UsersController.$inject = ["$scope", "$filter", "$location", "UsersService", "ProvidersService"];
        var controller = app.controller("UsersController", UsersController);

        return controller;
    }
);

/*
# templates/external_auth/views/ManageUserController.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    'app/views/ManageUserController',[
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "ngSanitize",
        "cjt/modules",
        "app/services/ProvidersService",
        "app/services/UsersService",
    ],
    function(angular, LOCALE) {

        var app = angular.module("App");

        function ManageUserController($scope, $routeParams, $location, $rootScope, $uibModal, ProvidersService, UsersService, growl) {
            $scope.user = false;
            $scope.LOCALE = LOCALE;

            $scope.init = function() {

                $scope.loadingUser = true;
                $scope.userID = $routeParams.userID;

                $scope.user = UsersService.get_user_by_username($scope.userID);
                $scope.user_links = $scope.get_user_links();

                $scope.loadingUser = false;

            };

            $scope.fetch = function() {
                $scope.user_links = [];
                $scope.loadingUser = true;
                UsersService.fetch_users().then(function() {
                    $scope.user = UsersService.get_user_by_username($scope.userID);
                    $scope.user_links = $scope.get_user_links();
                    if (!$scope.user_links.length) {
                        $location.path("/users");
                    }
                }, function(error) {
                    growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the users: [_1]", error));
                }).finally(function() {
                    $scope.loadingUser = false;
                });
            };

            $scope.unlink_provider = function(subject_unique_identifier, provider_id) {
                var provider = ProvidersService.get_provider_by_id(provider_id);
                var modalScope = $rootScope.$new();
                modalScope.provider = provider.display_name;
                modalScope.username = $scope.user.username;

                var preferred_username = $scope.user.links.openid_connect[provider_id][subject_unique_identifier].preferred_username;

                $scope.modalInstance = $uibModal.open({
                    templateUrl: "confirmproviderunlink.html",
                    scope: modalScope
                });
                return $scope.modalInstance.result.then(function() {
                    return UsersService.unlink_provider($scope.user.username, subject_unique_identifier, provider.id).then(function() {
                        growl.success(LOCALE.maketext("The system has removed the “[_1] ([_2])” authentication linkage for “[_3].”", provider.display_name, preferred_username, $scope.user.username));
                        $scope.fetch();
                    }, function(error) {
                        growl.error(LOCALE.maketext("The system could not remove the “[_1] ([_2])” authentication linkage for “[_3]” due to an error: [_4]", provider.display_name, preferred_username, $scope.user.username, error));
                    });
                }, function() {
                    $scope.clear_modal_instance();
                }).finally(function() {
                    $scope.clear_modal_instance();
                });
            };

            $scope.clear_modal_instance = function() {
                if ($scope.modalInstance) {
                    $scope.modalInstance.close();
                    $scope.modalInstance = null;
                }
            };
            $scope.get_user_links = function() {
                var providers = [];

                if (!$scope.user) {
                    return providers;
                }
                angular.forEach($scope.user.links, function(provider_type) {
                    angular.forEach(provider_type, function(links, key) {
                        var provider = ProvidersService.get_provider_by_id(key);
                        if (!providers[key]) {
                            providers.push(provider);
                        }

                        angular.forEach(links, function(subscriber_account, subject_unique_identifier) {
                            providers.push({
                                provider_key: provider.id,
                                display_name: subscriber_account.preferred_username,
                                subject_unique_identifier: subject_unique_identifier
                            });
                        });

                    });
                });
                return providers;
            };

            $scope.return_to_list = function() {
                $location.path("/users");
            };

            $scope.init();

        }
        ManageUserController.$inject = ["$scope", "$routeParams", "$location", "$rootScope", "$uibModal", "ProvidersService", "UsersService", "growl"];
        app.controller("ManageUserController", ManageUserController);


    });

/*
# templates/external_auth/views/ProvidersController.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    'app/views/ProvidersController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "ngSanitize",
        "cjt/modules",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/toggleSwitchDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
        "app/services/ProvidersService",
    ],
    function(angular, _, LOCALE) {

        var app = angular.module("App");

        function ProviderController($scope, $filter, $location, ProvidersService, PAGE) {

            $scope.providers = [];

            // meta information
            $scope.meta = {

                // sort settings
                sortReverse: false,
                sortBy: "label",
                sortDirection: "asc",

                // pager settings
                maxPages: 5,
                totalItems: $scope.providers.length,
                currentPage: 1,
                pageSize: 20,
                pageSizes: [20, 50, 100, 500],
                start: 0,
                limit: 10,

                filterValue: "",
            };

            // initialize filter list
            $scope.filteredList = $scope.providers;
            $scope.showPager = true;

            $scope.get_service_column_label = function(service) {
                return LOCALE.maketext("Status ([_1])", service);
            };

            $scope.allowed_authentication_services = PAGE.allowed_authentication_services;

            /**
             * Initialize the variables required for
             * row selections in the table.
             */
            $scope.checkdropdownOpen = false;

            // This updates the selected tracker in the 'Selected' Badge.
            $scope.totalSelectedProviders = 0;
            var selectedProviderList = [];

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

            // Select all providers on a page.
            $scope.selectAllProviders = function() {
                if ($scope.allRowsSelected) {
                    $scope.filteredList.forEach(function(item) {
                        item.rowSelected = true;

                        if (selectedProviderList.indexOf(item.id) !== -1) {
                            return;
                        }

                        selectedProviderList.push(item.id);
                    });
                } else {

                    // Extract the unselected items and remove them from the selected collection.
                    var unselectedList = $scope.filteredList.map(function(item) {
                        item.rowSelected = false;
                        return item.id;
                    });

                    selectedProviderList = _.difference(selectedProviderList, unselectedList);
                }

                // Update the selected count tracker.
                $scope.totalSelectedProviders = selectedProviderList.length;
            };

            $scope.configureProvider = function(provider) {
                $location.path("/providers/" + provider.id);
            };

            // Select an provider on a page.
            $scope.selectProvider = function(providerInfo) {
                if (typeof providerInfo !== "undefined") {
                    if (providerInfo.rowSelected) {
                        selectedProviderList.push(providerInfo.id);

                        // Sync 'Select All' checkbox status when a new selction/unselection
                        // is made.
                        $scope.allRowsSelected = $scope.filteredList.every(function(item) {
                            return item.rowSelected;
                        });
                    } else {
                        selectedProviderList = selectedProviderList.filter(function(item) {
                            return item !== providerInfo.id;
                        });

                        // Unselect Select All checkbox.
                        $scope.allRowsSelected = false;
                    }
                }

                // Update the selected count tracker.
                $scope.totalSelectedProviders = selectedProviderList.length;
            };

            // Clear all selections by unchecking all checkboxes in all pages.
            $scope.clearAllSelections = function(event) {
                event.preventDefault();
                event.stopPropagation();

                selectedProviderList = [];
                $scope.filteredList.forEach(function(item) {
                    item.rowSelected = false;
                });

                $scope.checkdropdownOpen = false;
                $scope.allRowsSelected = false;
                $scope.totalSelectedProviders = 0;
            };

            // update table on search
            $scope.searchList = function() {
                $scope.fetch();
            };

            // have your filters all in one place - easy to use
            var filters = {
                filter: $filter("filter"),
                orderBy: $filter("orderBy"),
                startFrom: $filter("startFrom"),
                limitTo: $filter("limitTo")
            };

            // update table
            $scope.fetch = function() {
                var filteredList = [];

                // filter list based on search text
                if ($scope.meta.filterValue !== "") {
                    filteredList = filters.filter($scope.providers, $scope.meta.filterValue, false);
                } else {
                    filteredList = $scope.providers;
                }

                // sort the filtered list
                if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                    filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                }

                // update the total items after search
                $scope.meta.totalItems = filteredList.length;

                // filter list based on page size and pagination
                if ($scope.meta.totalItems > _.min($scope.meta.pageSizes)) {
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

                var countNonSelected = 0;

                // Add rowSelected attribute to each item in the list to track selections.
                filteredList.forEach(function(item) {

                    // Select the rows if they were previously selected on this page.
                    if (selectedProviderList.indexOf(item.id) !== -1) {
                        item.rowSelected = true;
                    } else {
                        item.rowSelected = false;
                        countNonSelected++;
                    }
                });

                $scope.filteredList = filteredList;

                // Clear the 'Select All' checkbox if at least one row is not selected.
                $scope.allRowsSelected = (filteredList.length > 0) && (countNonSelected === 0);

                return filteredList;
            };

            $scope.init = function() {
                $scope.providers = ProvidersService.get_providers();
                $scope.fetch();
            };

            // first page load
            $scope.init();
        }
        ProviderController.$inject = ["$scope", "$filter", "$location", "ProvidersService", "PAGE"];
        app.controller("ProvidersController", ProviderController);


    });

/*
# templates/external_auth/views/ConfigureProviderController.js
#                                                        Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    'app/views/ConfigureProviderController',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "cjt/directives/actionButtonDirective",
        "cjt/validator/datatype-validators",
        "ngSanitize",
        "cjt/modules",
        "app/services/ProvidersService"
    ],
    function(angular, $, _, LOCALE) {
        "use strict";

        var app = angular.module("App");

        function ConfigureProviderController($scope, $routeParams, $location, ProvidersService, growl) {
            $scope.fields = {};
            $scope.configurations = {};
            $scope.provider = false;
            $scope.confirmed_redirects = false;
            $scope.savingProvider = false;
            $scope.services = {};
            $scope.service_names = {
                "webmaild": "Webmail",
                "whostmgrd": "WHM",
                "cpaneld": "cPanel"
            };

            function _growl_error(error) {
                growl.error( _.escape(error) );
            }

            $scope.init = function() {

                $scope.loadingProvider = true;

                var providerID = $routeParams.providerID;
                $scope.provider = ProvidersService.get_provider_by_id(providerID);

                if (!$scope.provider) {
                    $location.path("providers");
                }

                ProvidersService.get_provider_configuration_fields($scope.provider.id).then(function(result) {
                    $scope.fields = result.data;
                    return ProvidersService.get_provider_client_configurations($scope.provider.id);
                }).then(function(result) {
                    var baseObject = {};
                    angular.forEach($scope.fields, function(value) {
                        baseObject[value.field_id] = "";
                    }, baseObject);
                    $scope.configurations = angular.extend(baseObject, result.data.client_configurations);
                    return ProvidersService.get_provider_display_configurations($scope.provider.id);
                }, _growl_error).then(function(result) {
                    angular.forEach(result.data, function(service) {
                        $scope.services[service.service] = service;
                    });
                }, _growl_error).finally(function() {
                    $scope.loadingProvider = false;
                });

            };

            $scope.saveProviderConfigurations = function() {
                var saveable_configs = {};

                $scope.savingProvider = true;

                var display_configs = [];

                // Other possible, but not exposed params
                // "display_name" : "Test Google",
                // "documentation_url" : "docs_url",
                // "label" : "Log in with a Google+ Account",
                // "link" : ignore(),
                // "provider_name" : "testgoogle",
                angular.forEach($scope.services, function(service) {
                    display_configs.push({
                        "provider_id": $scope.provider.id,
                        "service_name": service.service,
                        "configs": {
                            "color": service.color,
                            "icon": service.icon,
                            "icon_type": service.icon_type,
                            "textcolor": service.textcolor,
                            "label": service.label
                        }
                    });
                });

                angular.forEach($scope.fields, function(value) {
                    saveable_configs[value.field_id] = $scope.configurations[value.field_id];
                });

                return ProvidersService.save_provider_configurations($scope.provider.id, saveable_configs, display_configs).then(function() {
                    $location.path("providers");
                    growl.success(LOCALE.maketext("The system successfully updated the configurations for “[_1].”", $scope.provider.display_name));
                }, function(error) {
                    growl.error(LOCALE.maketext("The system could not update the configurations for “[_1].” The following error occurred: “[_2]”", $scope.provider.display_name, error));
                }).finally(function() {
                    $scope.savingProvider = false;
                });
            };

            $scope.canSave = function(editorForm) {

                var field;
                for (var i = 0; i < $scope.fields.length; i++) {
                    field = $scope.fields[i];

                    if (!field.optional && !$scope.configurations[field.field_id]) {
                        return false;
                    }
                }

                if ($scope.configurations["redirect_uris"] && !editorForm.confirmed_redirects.$modelValue) {
                    return false;
                }

                return true;

            };

            $scope.init();
            window.scope = $scope;

        }
        ConfigureProviderController.$inject = ["$scope", "$routeParams", "$location", "ProvidersService", "growl"];
        app.controller("ConfigureProviderController", ConfigureProviderController);


    });

/*
# templates/external_auth/manage                       Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */

// Then load the application dependencies
define(
    'app/manage',[
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/locale",
        "cjt/modules",
    ],
    function(angular, _, CJT, LOCALE) {
        "use strict";

        angular.module("App", [
            "cjt2.config.whm.configProvider", // This needs to load first
            "ui.bootstrap",
            "cjt2.whm",
            "angular-growl"
        ]);

        var app = require(
            [
                "cjt/bootstrap",

                // Application Modules
                "uiBootstrap",
                "app/services/UsersService",
                "app/services/ProvidersService",
                "app/views/UsersController",
                "app/views/ManageUserController",
                "app/views/ProvidersController",
                "app/views/ConfigureProviderController",
                "cjt/decorators/growlDecorator",
            ],
            function(BOOTSTRAP) {

                var app = angular.module("App");
                app.value("PAGE", PAGE);

                app.controller("BaseController", ["$rootScope", "$scope", "$route", "$location",
                    function($rootScope, $scope, $route, $location) {

                        $scope.loading = false;
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

                app.config(["$routeProvider",
                    function($routeProvider) {

                        function _fetch_providers(ProvidersService, growl) {
                            return ProvidersService.fetch_providers().then(function() {

                                // providers loaded
                            }, function(error) {
                                growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the providers: [_1]", error));
                            });
                        }

                        function _fetch_users(UsersService, ProvidersService, growl) {
                            return UsersService.fetch_users().then(function() {

                                // users loaded
                                return ProvidersService.fetch_providers().then(function() {

                                    // providers Loaded
                                }, function(error) {
                                    growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the providers: [_1]", error));
                                });
                            }, function(error) {
                                growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the users: [_1]", error));
                            });
                        }

                        // Setup the routes
                        $routeProvider.when("/providers", {
                            controller: "ProvidersController",
                            templateUrl: CJT.buildFullPath("external_auth/views/providers.ptt"),
                            resolve: {
                                providers: ["ProvidersService", "growl", _fetch_providers]
                            }
                        });

                        $routeProvider.when("/providers/:providerID", {
                            controller: "ConfigureProviderController",
                            templateUrl: CJT.buildFullPath("external_auth/views/configure_provider.ptt"),
                            resolve: {
                                providers: ["ProvidersService", "growl", _fetch_providers]
                            }
                        });

                        // Setup the routes
                        $routeProvider.when("/users", {
                            controller: "UsersController",
                            templateUrl: CJT.buildFullPath("external_auth/views/users.ptt"),
                            resolve: {
                                providers: ["UsersService", "ProvidersService", "growl", _fetch_users]
                            }
                        });

                        $routeProvider.when("/users/:userID", {
                            controller: "ManageUserController",
                            templateUrl: CJT.buildFullPath("external_auth/views/manage_user.ptt"),
                            resolve: {
                                providers: ["UsersService", "ProvidersService", "growl", _fetch_users]
                            }
                        });

                        $routeProvider.otherwise({
                            "redirectTo": "/users"
                        });

                    }
                ]);

                BOOTSTRAP(document);
            });

        return app;
    }
);

