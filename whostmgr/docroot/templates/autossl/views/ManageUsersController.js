/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/toggleSwitchDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
        "ngSanitize",
    ],
    function(angular, LOCALE, _) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "ManageUsersController", [
                "$scope", "$filter", "AutoSSLConfigureService", "ssl_users", "growl",
                function($scope, $filter, $service, ssl_users, growl) {
                    function _growl_error(error) {
                        if (!error) {
                            return;
                        }
                        return growl.error(_.escape(error));
                    }

                    $scope.users = ssl_users;
                    $scope.items = $scope.users;
                    $scope.selected_items = [];
                    $scope.filteredList = [];
                    $scope.showPager = true;
                    $scope.all_rows_selected = false;

                    $scope.meta = {

                        // sort settings
                        sortReverse: false,
                        sortBy: "user",
                        sortDirection: "asc",

                        // pager settings
                        maxPages: 0,
                        totalItems: $scope.items.length,
                        currentPage: 1,
                        pageSize: 10,
                        pageSizes: [10, 20, 50, 100],
                        start: 0,
                        limit: 10,

                        filterValue: "",
                    };

                    $scope.fetch = function() {
                        var filteredList = [];

                        // filter list based on search text
                        if ($scope.meta.filterValue !== "") {
                            filteredList = $filter("filter")($scope.items, $scope.meta.filterValue, false);
                        } else {
                            filteredList = $scope.items;
                        }

                        // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            filteredList = $filter("orderBy")(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? false : true);
                        }

                        // update the total items after search
                        $scope.meta.totalItems = filteredList.length;

                        // filter list based on page size and pagination
                        if ($scope.meta.totalItems > _.min($scope.meta.pageSizes)) {
                            var start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                            var limit = $scope.meta.pageSize;

                            filteredList = $filter("limitTo")($filter("startFrom")(filteredList, start), limit);
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

                        var countNonSelected = $filter("filter")(filteredList, function(item) {
                            if (item.rowSelected) {
                                return false;
                            }
                            return true;
                        }).length;

                        $scope.filteredList = filteredList;

                        // Clear the 'Select All' checkbox if at least one row is not selected.
                        $scope.all_rows_selected = (filteredList.length > 0) && (countNonSelected === 0);

                        return filteredList;
                    };

                    $scope.can_run_check = function(user) {
                        if (user.auto_ssl_enabled === "enabled" || (user.auto_ssl_enabled === "inherit" && user.auto_ssl_settings.feature_list_setting.toString() === "1")) {
                            return true;
                        }
                    };

                    $scope.filter_table = function() {
                        $scope.fetch();
                        $scope.get_settings_for_current_users();
                    };

                    $scope.sort_table = function() {
                        $scope.fetch();
                        $scope.get_settings_for_current_users();
                    };

                    $scope.set_page = function() {
                        $scope.fetch();
                        $scope.get_settings_for_current_users();
                    };

                    $scope.set_page_size = function() {
                        $scope.fetch();
                        $scope.get_settings_for_current_users();
                    };

                    $scope.get_settings_for_current_users = function() {
                        $service.fetch_users_features_settings($scope.filteredList).then($scope.fetch, _growl_error);
                    };

                    $scope.showing_text = function() {
                        var first_item = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                        first_item += 1;
                        var last_item = $scope.meta.currentPage * $scope.meta.pageSize;
                        last_item = Math.min(last_item, $scope.items.length);
                        return LOCALE.maketext("[output,strong,Showing] [numf,_1] - [numf,_2] of [quant,_3,item,items]", first_item, last_item, $scope.items.length);
                    };

                    $scope.enable_auto_ssl = function(items) {

                        // These are items that are "disabled" or "inherit"
                        var not_enabled_items = $filter("filter")(items, function(item) {
                            return item.auto_ssl_enabled !== "enabled";
                        });
                        if (not_enabled_items.length === 0) {
                            growl.info(LOCALE.maketext("No users needed to be updated."));
                            return;
                        }
                        return $service.enable_auto_ssl_for_users(not_enabled_items).then(function() {
                            $scope.items = $scope.users = $service.get_users();
                            var flat_user_list = not_enabled_items.map(function(item) {
                                return item.user;
                            });
                            if (flat_user_list.length > 5) {
                                growl.success(LOCALE.maketext("[quant,_1,user has had its,users have had their] feature list “[asis,autossl]” setting overridden and [numerate,_1,is,are] now set to “[_2]”", flat_user_list.length, LOCALE.maketext("enabled")));
                            } else {
                                growl.success(LOCALE.maketext("You forcibly enabled the [asis,autossl] feature for the following [numerate,_1,user,users]: [list_and_quoted,_2]", flat_user_list.length, flat_user_list));
                            }
                        }, _growl_error);
                    };

                    $scope.disable_auto_ssl = function(items) {

                        // These are items that are "enabled" or "inherit"
                        var not_disabled_items = $filter("filter")(items, function(item) {
                            return item.auto_ssl_enabled !== "disabled";
                        });
                        if (not_disabled_items.length === 0) {
                            growl.info(LOCALE.maketext("No users needed to be updated."));
                            return;
                        }
                        return $service.disable_auto_ssl_for_users(not_disabled_items).then(function() {
                            $scope.items = $scope.users = $service.get_users();
                            var flat_user_list = not_disabled_items.map(function(item) {
                                return item.user;
                            });
                            if (flat_user_list.length > 5) {
                                growl.success(LOCALE.maketext("[quant,_1,user has had its,users have had their] feature list “[asis,autossl]” setting overridden and [numerate,_1,is,are] now set to “[_2]”", flat_user_list.length, LOCALE.maketext("disabled")));
                            } else {
                                growl.success(LOCALE.maketext("You forcibly disabled the [asis,autossl] feature for the following [numerate,_1,user,users]: [list_and_quoted,_2]", flat_user_list.length, flat_user_list));
                            }
                        }, _growl_error);
                    };

                    $scope.reset_auto_ssl = function(items) {
                        items = $filter("filter")(items, function(item) {

                            /* no point in resetting reset ones */
                            if (item.auto_ssl_enabled === "inherit") {
                                return false;
                            }
                            return true;
                        });
                        if (items.length === 0) {
                            growl.info(LOCALE.maketext("No users needed to be updated."));
                            return;
                        }
                        return $service.reset_auto_ssl_for_users(items).then(function() {
                            $scope.items = $scope.users = $service.get_users();
                            var flat_user_list = items.map(function(item) {
                                return item.user;
                            });
                            if (flat_user_list.length > 5) {
                                growl.success(LOCALE.maketext("[quant,_1,user has had its,users have had their] feature list “[asis,autossl]” setting reset to use the setting established by [numerate,_1,its,their] feature [numerate,_1,list,lists]", flat_user_list.length));
                            } else {
                                growl.success(LOCALE.maketext("You reset the [asis,autossl] feature to the feature list setting for the following [numerate,_1,user,users]: [list_and_quoted,_2]", flat_user_list.length, flat_user_list));
                            }
                        }, _growl_error);
                    };

                    $scope.update_auto_ssl_setting = function(user, new_value) {

                        if (user.auto_ssl_enabled === new_value) {
                            return;
                        }

                        if (new_value === "inherit") {
                            $scope.reset_auto_ssl([user]);
                        } else if (new_value === "enabled") {
                            $scope.enable_auto_ssl([user]);
                        } else if (new_value === "disabled") {
                            $scope.disable_auto_ssl([user]);
                        }

                    };

                    $scope.start_autossl_for_user = function(username) {
                        return $service.start_autossl_for_user(username).then(
                            function(result) {
                                growl.success(LOCALE.maketext("The system is checking the “[_1]” account’s domains (process [asis,ID] “[_2]”).", _.escape(username), result.data.pid));
                            },
                            _growl_error
                        );
                    };

                    $scope.select_all_items = function(items, force_on) {

                        if (force_on) {
                            $scope.all_rows_selected = true;
                        }

                        angular.forEach(items, function(item) {
                            item.rowSelected = $scope.all_rows_selected;
                        });

                        $scope.selected_items = $scope.get_selected_items();
                        $scope.fetch();
                        $scope.get_settings_for_current_users();
                    };

                    $scope.clear_all_selections = function() {
                        angular.forEach($scope.items, function(item) {
                            item.rowSelected = 0;
                        });
                        $scope.selected_items = $scope.get_selected_items();
                        $scope.fetch();
                        $scope.get_settings_for_current_users();
                    };

                    $scope.select_item = function() {
                        $scope.selected_items = $scope.get_selected_items();
                        $scope.fetch();
                        $scope.get_settings_for_current_users();
                    };

                    $scope.get_selected_items = function() {
                        return $filter("filter")($scope.items, function(item) {
                            if (item.rowSelected) {
                                return true;
                            }
                        });
                    };

                    $scope.auto_ssl_items = function(items) {
                        return $filter("filter")(items, function(item) {
                            return item.auto_ssl_enabled === "enabled";
                        });
                    };

                    $scope.get_reset_string = function(user) {
                        if (user.auto_ssl_settings.feature_list_setting) {
                            return LOCALE.maketext("Use setting established by the feature list “[_1]” which is currently set to “[_2]”.", user.feature_list, user.auto_ssl_settings.feature_list_setting === "1" ? LOCALE.maketext("enabled") : LOCALE.maketext("disabled"));
                        } else {
                            return "";
                        }
                    };

                    $scope.get_enable_button_label = function() {
                        return LOCALE.maketext("Enable [asis,AutoSSL] on selected [quant,_1,user,users]", $scope.selected_items.length);
                    };

                    $scope.get_disable_button_label = function() {
                        return LOCALE.maketext("Disable [asis,AutoSSL] on selected [quant,_1,user,users]", $scope.selected_items.length);
                    };

                    $scope.get_reset_button_label = function() {
                        return LOCALE.maketext("Reset [asis,AutoSSL] on selected [quant,_1,user,users]", $scope.selected_items.length);
                    };

                    $scope.fetch();
                    $scope.get_settings_for_current_users();

                }
            ]
        );

        return controller;
    }
);
