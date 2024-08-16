/*
# cpanel - whostmgr/docroot/templates/hulkd/services/HulkdDataSource.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-disable camelcase */

define(
    'app/services/HulkdDataSource',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/query",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it's ready
    ],
    function(angular, $, _, LOCALE, QUERY, PARSE, API, APIREQUEST, APIDRIVER) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var hulkDataSource = app.factory("HulkdDataSource", ["$q", "PAGE", "COUNTRY_CONSTANTS", function($q, PAGE, COUNTRY_CONSTANTS) {

            var hulkData = {};

            hulkData.whitelist = [];
            hulkData.blacklist = [];

            hulkData.whitelist_comments = {};
            hulkData.blacklist_comments = {};

            hulkData.whitelist_is_cached = false;
            hulkData.blacklist_is_cached = false;

            hulkData.config_settings = {};

            hulkData.enabled = PAGE.hulkd_status.is_enabled;

            hulkData.hulkd_status = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "cphulk_status");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        hulkData.enabled = PARSE.parsePerlBoolean(response.data.is_enabled);
                        deferred.resolve(hulkData.enabled);
                    });

                return deferred.promise;
            };

            hulkData.get_countries_with_known_ip_ranges = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_countries_with_known_ip_ranges");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.data);
                    });

                return deferred.promise;
            };

            hulkData.clear_caches = function() {
                hulkData.whitelist = [];
                hulkData.blacklist = [];

                hulkData.whitelist_comments = {};
                hulkData.blacklist_comments = {};

                hulkData.whitelist_is_cached = false;
                hulkData.blacklist_is_cached = false;
            };

            hulkData.enable_hulkd = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "enable_cphulk");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                            hulkData.enabled = true;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            hulkData.disable_hulkd = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "disable_cphulk");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.status);
                            hulkData.enabled = false;

                            // clear the caches to force a reload if
                            // hulkd is re-enabled later
                            hulkData.clear_caches();
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            hulkData.convert_config_settings = function(config) {
                var settings = {};

                settings.block_brute_force_with_firewall = PARSE.parsePerlBoolean(config.cphulk_config.block_brute_force_with_firewall);
                settings.block_excessive_brute_force_with_firewall = PARSE.parsePerlBoolean(config.cphulk_config.block_excessive_brute_force_with_firewall);
                settings.brute_force_period_mins = config.cphulk_config.brute_force_period_mins;
                settings.command_to_run_on_brute_force = config.cphulk_config.command_to_run_on_brute_force;
                settings.command_to_run_on_excessive_brute_force = config.cphulk_config.command_to_run_on_excessive_brute_force;
                settings.is_enabled = PARSE.parsePerlBoolean(config.cphulk_config.is_enabled);
                settings.ip_brute_force_period_mins = config.cphulk_config.ip_brute_force_period_mins;
                settings.lookback_period_min = config.cphulk_config.lookback_period_min;
                settings.max_failures = config.cphulk_config.max_failures;
                settings.max_failures_byip = config.cphulk_config.max_failures_byip;
                settings.mark_as_brute = config.cphulk_config.mark_as_brute;
                settings.notify_on_root_login = PARSE.parsePerlBoolean(config.cphulk_config.notify_on_root_login);
                settings.notify_on_root_login_for_known_netblock = PARSE.parsePerlBoolean(config.cphulk_config.notify_on_root_login_for_known_netblock);
                settings.notify_on_brute = PARSE.parsePerlBoolean(config.cphulk_config.notify_on_brute);
                settings.can_temp_ban_firewall = PARSE.parsePerlBoolean(config.cphulk_config.can_temp_ban_firewall);
                settings.iptable_error = config.cphulk_config.iptable_error;
                settings.username_based_protection = PARSE.parsePerlBoolean(config.cphulk_config.username_based_protection);
                settings.ip_based_protection = PARSE.parsePerlBoolean(config.cphulk_config.ip_based_protection);
                settings.username_based_protection_local_origin = PARSE.parsePerlBoolean(config.cphulk_config.username_based_protection_local_origin);
                settings.username_based_protection_for_root = PARSE.parsePerlBoolean(config.cphulk_config.username_based_protection_for_root);

                settings.country_whitelist = config.cphulk_config.country_whitelist ? config.cphulk_config.country_whitelist.split(",") : [];
                settings.country_blacklist = config.cphulk_config.country_blacklist ? config.cphulk_config.country_blacklist.split(",") : [];

                hulkData.config_settings = settings;

                return settings;
            };

            hulkData.save_config_settings = function(config) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "save_cphulk_config");

                for (var i = 0, keys = _.keys(config), len = keys.length; i < len; i++) {

                    // we do not want to send this option
                    if (keys[i] === "is_enabled") {
                        continue;
                    }

                    var value = config[keys[i]];
                    if (_.isArray(value)) {
                        value = value.join(",");
                    } else if (_.isBoolean(value)) {
                        if (value) {
                            value = 1;
                        } else {
                            value = 0;
                        }
                    }

                    apiCall.addArgument(keys[i], value);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {

                            // clean up the restart_ssh boolean
                            response.data.restart_ssh = PARSE.parsePerlBoolean(response.data.restart_ssh);
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };


            hulkData.load_config_settings = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "load_cphulk_config");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response.data,
                                settings = hulkData.convert_config_settings(results);
                            deferred.resolve(settings);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            hulkData.set_cphulk_config_keys = function(updatedKeys) {
                var batchCalls = [];

                angular.forEach(updatedKeys, function(value, key) {
                    batchCalls.push({
                        func: "set_cphulk_config_key",
                        data: {
                            key: key,
                            value: value,
                        },
                    });
                });

                return _batch_apiv1(batchCalls).then(function(results) {

                    // Use the last updated config, giving the most recent cphulk configuration
                    var response = results.pop();
                    response = response.parsedResponse;
                    var settings = hulkData.convert_config_settings(response.data);
                    return hulkData._parse_xlisted_countries(settings);
                });
            };

            function _batch_apiv1(calls_infos) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "batch");

                calls_infos.forEach(function(call, i) {
                    apiCall.addArgument(
                        ("command-" + i),
                        call.func + "?" + QUERY.make_query_string(call.data)
                    );
                });

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response.data;
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            }

            hulkData.load_xlisted_countries = function() {
                return hulkData.load_config_settings().then(function(settings) {
                    return hulkData._parse_xlisted_countries(settings);
                });
            };

            hulkData._parse_xlisted_countries = function(settings) {
                var countries = {};
                settings.country_blacklist.forEach(function(item) {
                    countries[item] = COUNTRY_CONSTANTS.BLACKLISTED;
                });
                settings.country_whitelist.forEach(function(item) {
                    countries[item] = COUNTRY_CONSTANTS.WHITELISTED;
                });
                return countries;
            };


            hulkData.add_to_list = function(list, records) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "batch_create_cphulk_records", null, null, { json: true });
                apiCall.addArgument("list_name", list);
                apiCall.addArgument("records", records);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {

                            // on API call success, add to list
                            var return_data = {
                                added: [],
                                rejected: response.data.ips_failed,
                                updated: [],
                            };

                            var original_ips_added = response.data.original_ips_added || [];
                            var ip_list = hulkData[ list + "list" ];
                            var comment_list = hulkData[ list + "list_comments"];

                            for (var i = 0, len = original_ips_added.length; i < len; i++) {

                                var ip = original_ips_added[i];
                                var ip_formatted = response.data.ips_added[i];

                                // Update the ip cache and parse the return data
                                var index = _.indexOf(hulkData.whitelist, ip_formatted);
                                if (index === -1) {
                                    ip_list.push(ip_formatted);
                                    return_data.added.push(ip_formatted);
                                } else {
                                    return_data.updated.push(ip_formatted);
                                }

                                // Update the comment cache.
                                var record = _.find(records, function(record) {
                                    return record.ip === ip;
                                });
                                if (record && record.comment) {
                                    comment_list[ip_formatted] = record.comment;
                                }

                                // Extra info for the whitelist return.
                                if (list === "white") {
                                    return_data.requester_ip = response.data.requester_ip;
                                    return_data.requester_ip_is_whitelisted = response.data.requester_ip_is_whitelisted;
                                }
                            }

                            deferred.resolve(return_data);

                        } else {

                            // pass the error along
                            var error_details = {
                                main_message: response.error,
                                secondary_messages: [],
                            };

                            // Build the reason individual ips were rejected.
                            Object.keys(response.data.ips_failed).forEach(function(ip) {
                                var rejectReason = response.data.ips_failed[ip];
                                error_details.secondary_messages.push(rejectReason);
                            });

                            deferred.reject(error_details);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;
            };

            hulkData.add_to_whitelist = function(records) {
                return hulkData.add_to_list("white", records);
            };

            hulkData.add_to_blacklist = function(records) {
                return hulkData.add_to_list("black", records);
            };

            hulkData.remove_from_list = function(ips_to_delete, list) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "delete_cphulk_record");
                apiCall.addArgument("list_name", list);
                for (var i = 0; i < ips_to_delete.length; i++) {
                    apiCall.addArgument("ip-" + i, ips_to_delete[i]);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            var i = 0;

                            if (list === "white") {

                                // remove the IPs
                                hulkData.whitelist = _.difference(hulkData.whitelist, response.data.ips_removed);

                                // remove the comment
                                for (i = 0; i < response.data.ips_removed.length; i++) {
                                    delete hulkData.whitelist_comments[response.data.ips_removed[i]];
                                }
                            } else {

                                // remove the IPs
                                hulkData.blacklist = _.difference(hulkData.blacklist, response.data.ips_removed);

                                // remove the comment
                                for (i = 0; i < response.data.ips_removed.length; i++) {
                                    delete hulkData.blacklist_comments[response.data.ips_removed[i]];
                                }
                            }

                            deferred.resolve({ removed: response.data.ips_removed, not_removed: response.data.ips_failed, requester_ip: response.data.requester_ip, requester_ip_is_whitelisted: response.data.requester_ip_is_whitelisted });
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;

            };

            hulkData.remove_from_whitelist = function(ips_to_delete) {
                return hulkData.remove_from_list(ips_to_delete, "white");
            };

            hulkData.remove_from_blacklist = function(ip_to_delete) {
                return hulkData.remove_from_list(ip_to_delete, "black");
            };

            hulkData.remove_all_from_whitelist = function() {
                return hulkData.remove_from_whitelist(hulkData.whitelist);
            };

            hulkData.remove_all_from_blacklist = function() {
                return hulkData.remove_from_blacklist(hulkData.blacklist);
            };

            hulkData.load_list = function(list) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "read_cphulk_records");
                apiCall.addArgument("list_name", list);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {

                            // on API call success, populate data structure

                            var return_data = {};

                            if (list === "white") {

                                // check to see if the ip address is not whitelisted
                                if (!response.data.requester_ip_is_whitelisted) {
                                    return_data.whitelist_warning = response.data.warning_ip;
                                }
                                if (response.data.restart_ssh) {
                                    return_data.restart_ssh = true;
                                }
                                if (response.data.warning_ssh) {
                                    return_data.warning_ssh = response.data.warning_ssh;
                                }

                                hulkData.whitelist = Object.keys(response.data.ips_in_list).slice();
                                for (var i = 0; i < hulkData.whitelist.length; i++) {
                                    if (response.data.ips_in_list[hulkData.whitelist[i]]) {
                                        hulkData.whitelist_comments[hulkData.whitelist[i]] = response.data.ips_in_list[hulkData.whitelist[i]];
                                    }
                                }
                                hulkData.whitelist_is_cached = true;
                                return_data.list = hulkData.whitelist;
                                return_data.comments = hulkData.whitelist_comments;
                                return_data.requester_ip = response.data.requester_ip;
                                return_data.requester_ip_is_whitelisted = response.data.requester_ip_is_whitelisted;
                                deferred.resolve(return_data);
                            } else if (list === "black") {
                                hulkData.blacklist = Object.keys(response.data.ips_in_list).slice();
                                for (var j = 0; j < hulkData.blacklist.length; j++) {
                                    if (response.data.ips_in_list[hulkData.blacklist[j]]) {
                                        hulkData.blacklist_comments[hulkData.blacklist[j]] = response.data.ips_in_list[hulkData.blacklist[j]];
                                    }
                                }
                                hulkData.blacklist_is_cached = true;
                                return_data.list = hulkData.blacklist;
                                return_data.comments = hulkData.blacklist_comments;
                                return_data.requester_ip = response.data.requester_ip;
                                deferred.resolve(return_data);
                            }
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;
            };

            function init() {

                // check for page data in the template if this is a first load
                if (app.firstLoad && app.firstLoad.configs && PAGE.config_values) {
                    app.firstLoad.configs = false;
                    hulkData.config_settings = hulkData.convert_config_settings(PAGE.config_values);
                }
            }

            init();

            return hulkData;
        }]);

        return hulkDataSource;
    }
);

/*
# templates/hulkd/directives/disableValidation.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
  * @summary Directive that disables any validation functions tied to an ngModel
  * based on a value (which must be evaluated) passed to the directive.
  *
  * This code is based on this plunkr: https://embed.plnkr.co/EM1tGb/
  *
  * @required ngModel This directive requires ngModel be set on the element.
  *
  * @example
  * <input type="text"
  *     id="theText"
  *     name="theText"
  *     ng-model="myvalue"
  *     required
  *     disable-validation="toggleValidation">
  */
define(
    'app/directives/disableValidation',[
        "angular"
    ],
    function(angular) {
        "use strict";

        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", []);
        }

        app.directive("disableValidation", function() {
            return {
                require: "ngModel",
                restrict: "A",
                link: function(scope, element, attrs, ngModelController) {
                    var originalValidators = angular.copy(ngModelController.$validators);
                    Object.keys(originalValidators).forEach(function(key) {
                        ngModelController.$validators[key] = function(v) {

                            // pass the view value twice because some validators take modelValue and viewValue (e.g. required)
                            return scope.$eval(attrs.disableValidation) || originalValidators[key](v, v);
                        };
                    });

                    scope.$watch(attrs.disableValidation, function() {

                        // trigger validation
                        var originalViewValue = ngModelController.$viewValue;
                        scope.$applyAsync(function() {
                            ngModelController.$setViewValue("");
                            ngModelController.$setViewValue(originalViewValue);
                        });
                    });

                }
            };
        });
    }
);

/*
# templates/hulkd/views/configController.js       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/views/configController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/validator/length-validators",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/decorators/growlDecorator",
        "app/services/HulkdDataSource",
        "app/directives/disableValidation"
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "configController",
            ["$scope", "HulkdDataSource", "growl", "PAGE",
                function($scope, HulkdDataSource, growl, PAGE) {

                    $scope.username_protection_level = "local";
                    $scope.username_protection_enabled = true;

                    function ignoreKeyDownForSpacebar(event) {

                        // prevent the spacebar from scrolling the window
                        if (event.keyCode === 32) {
                            event.preventDefault();
                        }
                    }

                    $scope.growlProtectionChangeRequiresSave = function() {
                        growl.warning(LOCALE.maketext("You changed the protection level of [asis,cPHulk]. Click Save to implement this change."));
                    };

                    $scope.$watch( function() {
                        return $scope.username_protection_enabled;
                    },
                    function(newValue, oldValue) {
                        if (newValue !== oldValue ) {
                            $scope.growlProtectionChangeRequiresSave();
                        }
                    }
                    );

                    $scope.$watch( function() {
                        return $scope.config_settings.ip_based_protection;
                    },
                    function(newValue, oldValue) {
                        if (newValue !== oldValue ) {
                            $scope.growlProtectionChangeRequiresSave();
                        }
                    }
                    );

                    $scope.align_username_protection_settings = function() {

                        // set up username protection to match the combined
                        // settings
                        if ($scope.config_settings.username_based_protection) {
                            $scope.username_protection_level = "both";
                            $scope.username_protection_enabled = true;
                        } else if ($scope.config_settings.username_based_protection_local_origin) {
                            $scope.username_protection_level = "local";
                            $scope.username_protection_enabled = true;
                        } else {
                            $scope.username_protection_enabled = false;
                        }
                    };

                    $scope.prepare_username_protection_settings_for_save = function() {
                        if (!$scope.username_protection_enabled) {
                            $scope.config_settings.username_based_protection_local_origin = false;
                            $scope.config_settings.username_based_protection = false;
                        } else if ($scope.username_protection_level === "local") {
                            $scope.config_settings.username_based_protection_local_origin = true;
                            $scope.config_settings.username_based_protection = false;
                        } else {
                            $scope.config_settings.username_based_protection = true;
                        }
                    };

                    $scope.handle_protection_keydown = function(event) {
                        ignoreKeyDownForSpacebar(event);
                    };

                    $scope.handle_protection_keyup = function(event, target) {

                    // bind to the spacebar and enter keys
                        if (event.keyCode === 32 || event.keyCode === 13) {
                            event.preventDefault();
                            if ($scope.config_settings[target] !== void 0) {
                                if (target === "username") {
                                    $scope.username_protection_enabled = !$scope.username_protection_enabled;
                                } else {
                                    $scope.config_settings[target] = !$scope.config_settings[target];
                                }
                            }
                        }
                    };

                    $scope.collapse_keydown = function(event) {
                        ignoreKeyDownForSpacebar(event);
                    };


                    $scope.collapse_keyup = function(event, target) {

                    // bind to the spacebar and enter keys
                        if (event.keyCode === 32 || event.keyCode === 13) {
                            event.preventDefault();
                            if ($scope[target] !== void 0) {
                                $scope[target] = !$scope[target];
                            }
                        }
                    };

                    $scope.disableSave = function(form) {
                        return form.$invalid || $scope.loadingPageData;
                    };

                    $scope.save = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        $scope.loadingPageData = true;

                        $scope.prepare_username_protection_settings_for_save();

                        return HulkdDataSource.save_config_settings($scope.config_settings)
                            .then(
                                function(data) {
                                    growl.success(LOCALE.maketext("The system successfully saved your [asis,cPHulk] configuration settings."));
                                    if (data.restart_ssh) {
                                        growl.warning(LOCALE.maketext("The system disabled the [asis,UseDNS] setting for [asis,SSHD] in order to add IP addresses to the whitelist. You must restart SSH through the [output,url,_1,Restart SSH Server,_2] page to implement the change.", PAGE.security_token + "/scripts/ressshd", { "target": "_blank" }));
                                    } else if (data.warning) {
                                        growl.warning(data.warning);
                                    }
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally(function() {
                                $scope.loadingPageData = false;
                            });
                    };

                    $scope.fetch = function() {
                        if (_.isEmpty(HulkdDataSource.config_settings)) {
                            $scope.loadingPageData = true;
                            HulkdDataSource.load_config_settings()
                                .then(
                                    function(data) {
                                        $scope.config_settings = data;
                                        $scope.align_username_protection_settings();
                                    }, function(error) {
                                        growl.error(error);
                                    }
                                )
                                .finally(function() {
                                    $scope.loadingPageData = false;
                                });
                        } else {
                            $scope.config_settings = HulkdDataSource.config_settings;
                            $scope.align_username_protection_settings();
                        }

                    };

                    $scope.bruteInfoCollapse = true;
                    $scope.excessiveBruteInfoCollapse = true;
                    $scope.loadingPageData = false;

                    $scope.fetch();
                }
            ]);

        return controller;
    }
);

/*
# templates/hulkd/directives/countryCodesTableDirective
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// Then load the application dependencies
define(
    'app/directives/countryCodesTableDirective',[
        "angular",
        "lodash",
        "cjt/core",
        "uiBootstrap",
        "cjt/modules",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/quickFiltersDirective",
    ], function(angular, _, CJT) {
        "use strict";

        var app = angular.module("App");

        app.directive("countryCodesTable", ["COUNTRY_CONSTANTS", "$timeout", function(COUNTRY_CONSTANTS, $timeout) {

            var TEMPLATE_PATH = "directives/countryCodesTable.ptt";
            var RELATIVE_PATH = "templates/hulkd/" + TEMPLATE_PATH;

            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                restrict: "EA",
                scope: {
                    "items": "=",
                    "onChange": "&onChange",
                },
                replace: true,
                controller: ["$scope", "$filter", "$uibModal", function($scope, $filter, $uibModal) {

                    // confirm blacklist modal
                    $scope.modal_instance = null;
                    $scope.country_blacklist_in_progress = false;

                    $scope.confirm_country_blacklisting = function() {
                        $scope.country_blacklist_in_progress = true;

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_country_blacklisting.html",
                            scope: $scope,
                        });
                        return true;
                    };

                    $scope.cancel_country_blacklisting = function() {
                        $scope.clear_modal_instance();
                        $scope.deselectAll();
                        $scope.country_blacklisting_in_progress = false;
                    };

                    $scope.continue_country_blacklisting = function(selectedItems) {
                        $scope.clear_modal_instance();
                        $scope.country_blacklist_in_progress = false;
                        $scope.blacklistCountries(selectedItems);
                    };

                    $scope.clear_modal_instance = function() {
                        if ($scope.modal_instance) {
                            $scope.modal_instance.close();
                            $scope.modal_instance = null;
                        }
                    };

                    // initialize filter list
                    var updateTimeout;
                    $scope.filteredList = $scope.items;
                    $scope.COUNTRY_CONSTANTS = COUNTRY_CONSTANTS;
                    var countriesMap = {};

                    $scope.items.forEach(function(item) {
                        countriesMap[item.code] = item;
                        item.searchableCode = "(" + item.code + ")";
                    });

                    $scope.loading = false;

                    $scope.meta = {
                        filterValue: "",
                        sortBy: "name",
                        quickFilterValue: "all",
                    };

                    /**
                 * Initialize the variables required for
                 * row selections in the table.
                */

                    // This updates the selected tracker in the 'Selected' Badge.
                    $scope.selectedItems = [];

                    $scope.toggleSelect = function(itemCode, list) {

                        var idx = list.indexOf(itemCode);
                        if (idx > -1) {
                            list.splice(idx, 1);
                        } else {
                            list.push(itemCode);
                        }
                    };

                    $scope.toggleSelectAll = function() {
                        if ($scope.allSelected()) {
                            $scope.deselectAll();
                        } else {
                            $scope.selectAll();
                        }
                    };

                    $scope.selectAll = function() {
                        $scope.selectedItems = $scope.filteredList.map(function(item) {
                            return item.code;
                        });
                    };

                    $scope.deselectAll = function() {
                        $scope.selectedItems = [];
                    };

                    $scope.allSelected = function() {
                        return $scope.selectedItems.length && $scope.selectedItems.length === $scope.filteredList.length;
                    };

                    $scope.exists = function(item, list) {
                        return list.indexOf(item) > -1;
                    };

                    // update the table on sort
                    $scope.sortList = function(meta) {
                        $scope.fetch();
                    };

                    // update table on search
                    $scope.searchList = function(searchString) {
                        $scope.fetch();
                    };

                    $scope.getCountriesFromCodes = function(countryCodes) {
                        return countryCodes.map(function(countryCode) {
                            return countriesMap[countryCode];
                        });
                    };

                    $scope.whitelistCountries = function(countries) {
                        $scope.getCountriesFromCodes(countries).forEach(function(country) {
                            country.status = COUNTRY_CONSTANTS.WHITELISTED;
                        });
                        $scope.countriesUpdated();
                    };

                    $scope.blacklistCountries = function(countries) {
                        $scope.getCountriesFromCodes(countries).forEach(function(country) {
                            country.status = COUNTRY_CONSTANTS.BLACKLISTED;
                        });
                        $scope.countriesUpdated();
                    };

                    $scope.unlistCountries = function(countries) {
                        $scope.getCountriesFromCodes(countries).forEach(function(country) {
                            country.status = COUNTRY_CONSTANTS.UNLISTED;
                        });
                        $scope.countriesUpdated();
                    };

                    $scope.countriesUpdated = function() {
                        if ($scope.onChange) {

                            if (updateTimeout) {
                                $timeout.cancel(updateTimeout);
                                updateTimeout = false;
                            }

                            updateTimeout = $timeout(function() {
                                $scope.countriesUpdating = true;
                                var whitelistedDomains = [];
                                var blacklistedDomains = [];
                                $scope.items.forEach(function(item) {
                                    if (item.status === COUNTRY_CONSTANTS.WHITELISTED) {
                                        whitelistedDomains.push(item.code);
                                    } else if (item.status === COUNTRY_CONSTANTS.BLACKLISTED) {
                                        blacklistedDomains.push(item.code);
                                    }
                                });
                                $scope.onChange({ whitelist: whitelistedDomains, blacklist: blacklistedDomains }).finally(function() {
                                    $scope.countriesUpdating = false;
                                });
                            }, 250);

                        }
                    };

                    // have your filters all in one place - easy to use
                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                    };

                    $scope.quickFilterUpdated = function() {
                        $scope.deselectAll();
                        $scope.fetch();
                    };

                    // update table
                    $scope.fetch = function() {
                        var filteredList = [];

                        // filter list based on search text
                        if ($scope.meta.filterValue !== "") {
                            filteredList = filters.filter($scope.items, $scope.meta.filterValue, false);
                        } else {
                            filteredList = $scope.items;
                        }

                        if ($scope.meta.quickFilterValue !== "all") {
                            filteredList = filters.filter(filteredList, { status: $scope.meta.quickFilterValue }, false);
                        }

                        // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }

                        // update the total items after search
                        $scope.meta.totalItems = filteredList.length;

                        $scope.filteredList = filteredList;

                        return filteredList;
                    };

                    // first page load
                    $scope.fetch();
                }],
            };
        }]);
    });

/*
# templates/hulkd/views/historyController.js      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/countriesController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/directives/countryCodesTableDirective",
        "cjt/decorators/growlDecorator",
        "app/services/HulkdDataSource"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "countriesController",
            ["$scope","growl","HulkdDataSource","COUNTRY_CONSTANTS","COUNTRY_CODES","XLISTED_COUNTRIES",
            function($scope, $growl, $service, COUNTRY_CONSTANTS, COUNTRY_CODES, XLISTED_COUNTRIES) {

                function _parseCountries(countryCodes, xlistedCountries){
                    return countryCodes.map(function(countryCode){
                        countryCode.status = xlistedCountries[countryCode.code] || COUNTRY_CONSTANTS.UNLISTED;
                        return countryCode;
                    });
                }

                $scope.countries = _parseCountries(COUNTRY_CODES, XLISTED_COUNTRIES);

                var startingGrowl, successGrowl;

                $scope.countriesUpdated = function(whitelist, blacklist){
                    // Using growl for consistency, but this will have to be refactored later
                    if(successGrowl){
                        successGrowl.destroy();
                    }
                    startingGrowl = $growl.info(LOCALE.maketext("Updating the country whitelist and blacklist …"));
                    return $service.set_cphulk_config_keys({
                        "country_whitelist":whitelist.sort().join(","),
                        "country_blacklist":blacklist.sort().join(",")
                    }).then(function(xlistedCountries){
                        XLISTED_COUNTRIES = xlistedCountries;
                        $scope.countries = _parseCountries(COUNTRY_CODES, xlistedCountries);
                        startingGrowl.destroy();
                        successGrowl = $growl.success(LOCALE.maketext("Country whitelist and blacklist updated."));
                    });
                };

            }
        ]);

        return controller;
    }
);



/*
# cpanel - whostmgr/docroot/templates/hulkd/utils/download.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
define(
    'app/utils/download',[],function() {

        "use strict";

        return {

            /**
             * Create a download name.
             *
             * @param {string} prefix
             * @returns {string}
             */
            getDownloadName: function(prefix) {
                return prefix + ".txt";
            },

            /**
             * Convert the raw data into a download url data blob.
             *
             * @param {string} data - the formatted download data.
             * @returns {string} - The data formatted for a download url.
             */
            getTextDownloadUrl: function(data) {
                var blob = new Blob([data], { type: "plain/text" });
                return window.URL.createObjectURL(blob);
            },

            /**
             * Clean up the allocated url.
             *
             * @param {string} url - the url previously created with createObjetURL.
             */
            cleanupDownloadUrl: function(url) {
                if (url) {
                    window.URL.revokeObjectURL(url);
                }
            },

            /**
             * @typedef IpRecord
             * @property {string} ip - ip address or range.
             * @property {string?} comment - comment associated with the ip or range.
             */

            /**
             * Convert the ip list into a serialized format.
             *
             * @param {IpRecord[]} list
             * @returns {string}
             */
            formatList: function(list) {
                if (list && list.length) {
                    return list.map(function(item) {
                        return item.ip + (item.comment ? " # " + item.comment : "");
                    }).join("\n") + "\n";
                }
                return "";
            },
        };

    }
);

/*
# cpanel - whostmgr/docroot/templates/hulkd/views/hulkdWhitelistController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint camelcase: 0, no-prototype-builtins: 0 */

define(
    'app/views/hulkdWhitelistController',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "app/utils/download",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/decorators/growlDecorator",
        "cjt/filters/startFromFilter",
        "app/services/HulkdDataSource",
    ],
    function(angular, $, _, LOCALE, Download) {

        "use strict";

        // Retrieve the current application
        var app = angular.module("App");
        app.config([ "$compileProvider",
            function($compileProvider) {
                $compileProvider.aHrefSanitizationWhitelist(/^blob:https:/);
            },
        ]);

        var controller = app.controller(
            "hulkdWhitelistController",
            ["$rootScope", "$scope", "$filter", "$routeParams", "$uibModal", "HulkdDataSource", "growl", "PAGE", "growlMessages", "$timeout",
                function($rootScope, $scope, $filter, $routeParams, $uibModal, HulkdDataSource, growl, PAGE, growlMessages, $timeout) {

                    $scope.whitelist_reverse = false;

                    $scope.whitelist = [];
                    $scope.whitelist_comments = {};

                    $scope.adding_batch_to_whitelist = false;

                    $scope.new_whitelist_records = "";

                    $scope.ip_being_edited = false;
                    $scope.current_ip = null;
                    $scope.current_comment = "";
                    $scope.updating_comment = false;

                    $scope.modal_instance = null;

                    $scope.loading = false;

                    $scope.downloadAllLink = "";
                    $scope.downloadSelectionLink = "";

                    $scope.meta = {
                        sortDirection: "asc",
                        sortBy: "white_ip",
                        sortType: "",
                        sortReverse: false,
                        filter: "",
                        maxPages: 0,
                        totalItems: $scope.whitelist.length || 0,
                        currentPage: 1,
                        pageNumberStart: 0,
                        pageNumberEnd: 0,
                        pageSize: 20,
                        pageSizes: [20, 50, 100],
                    };

                    $scope.LOCALE = LOCALE;

                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                        startFrom: $filter("startFrom"),
                        limitTo: $filter("limitTo"),
                    };

                    $scope.delete_in_progress = false;
                    $scope.ips_to_delete = [];

                    // Handle auto-adding an ip from a query param or POST
                    if (($routeParams["ip"] && $routeParams["ip"].length > 0) ||
                        PAGE.ipToAdd !== null) {
                        var ip;
                        var comment = "";

                        if ($routeParams["ip"] && $routeParams["ip"].length > 0) {

                            // added via a query param
                            ip = $routeParams["ip"];
                        } else if (PAGE.ipToAdd !== null) {

                            // added via a POST and stuffed into PAGE
                            ip = PAGE.ipToAdd;
                        }

                        // clear the ip so we don't add it again
                        PAGE.ipToAdd = null;

                        if (ip !== void 0) {
                            $scope._add_to_whitelist([ { ip: ip, comment: comment } ]);
                        }
                    }


                    $scope.growl_whitelist_warning = function(missing_ip) {

                        // create a new growl to be displayed.
                        var message_cache = LOCALE.maketext("Your current IP address “[_1]” is not on the whitelist.", _.escape(missing_ip));
                        $rootScope.whitelist_warning_message = growl.error(message_cache,
                            {
                                variables: {
                                    buttonLabel: LOCALE.maketext("Add to Whitelist"),
                                    showAction: true,
                                    action: function() {
                                        $rootScope.one_click_add_to_whitelist(missing_ip)
                                            .then(function() {
                                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                            });
                                    },
                                },
                                onclose: function() {
                                    $rootScope.whitelist_warning_message = null;
                                },
                            }
                        );
                    };

                    $scope.edit_whitelist_ip = function(whitelist_ip) {
                        $scope.current_ip = whitelist_ip;
                        $scope.current_comment = $scope.whitelist_comments.hasOwnProperty(whitelist_ip) ? $scope.whitelist_comments[whitelist_ip] : "";
                        $scope.ip_being_edited = true;
                        var whitelist_comment_field = $("#whitelist_current_comment");
                        var wait_id = setInterval( function() {
                            if (whitelist_comment_field.is(":visible")) {
                                whitelist_comment_field.focus();
                                whitelist_comment_field.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    $scope.cancel_whitelist_editing = function() {
                        $scope.current_ip = null;
                        $scope.current_comment = "";
                        $scope.ip_being_edited = false;
                        $scope.focus_on_whitelist();
                    };

                    $scope.delete_tooltip = function(ip_address) {
                        return LOCALE.maketext("Click to delete “[_1]” from the whitelist.", ip_address);
                    };

                    $scope.edit_tooltip = function(ip_address) {
                        return LOCALE.maketext("Click to edit the comment for “[_1]”.", ip_address);
                    };

                    $scope.update_whitelist_comment = function() {
                        if ($scope.updating_comment) {
                            return;
                        }

                        $scope.updating_comment = true;
                        HulkdDataSource.add_to_whitelist([ { ip: $scope.current_ip, comment: $scope.current_comment } ])
                            .then( function(results) {
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;

                                // Growl out each success from the batch.
                                results.updated.forEach(function(ip) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(ip)));
                                });

                                // Report the failures from the batch.
                                var rejectedMessages = [];
                                Object.keys(results.rejected).forEach(function(ip) {
                                    rejectedMessages.push(_.escape(ip) + ": " + _.escape(results.rejected[ip]));
                                });

                                if (rejectedMessages.length > 0) {
                                    var accumulatedMessages = LOCALE.maketext("Some records failed to update.") + "<br>";
                                    accumulatedMessages += rejectedMessages.join("<br>");
                                    growl.error(accumulatedMessages);
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updating_comment = false;
                                $scope.cancel_whitelist_editing();
                                $scope.focus_on_whitelist();
                            });
                    };

                    var ipV6 = /^(([\da-fA-F]{1,4}:){4})(([\da-fA-F]{1,4}:){3})([\da-fA-F]{1,4})$/;
                    var ipV4Range = /^((\d{1,3}.){3}\d{1,3})-((\d{1,3}.){3}\d{1,3})$/;
                    var ipRangeTest = /-/;
                    var ipV6Test = /:/;

                    /**
                     * Separates long ipv4 and ipv6 addresses with br tags.
                     * Also, supports separating ipv4 and ipv6 address ranges.
                     *
                     * @param {string} ip - an ip address
                     * @todo Implement this as an Angular Filter in a separate file
                     */
                    $scope.splitLongIp = function(ip) {

                        // ipv6?
                        if (ipV6Test.test(ip)) {

                            // is this a range?
                            if (ipRangeTest.test(ip)) {

                                // format the ipv6 addresses in range format
                                var ipv6Addresses = ip.split(ipRangeTest);
                                var ipv6AddressRange = "";

                                // get the first part of the range
                                var match = ipV6.exec(ipv6Addresses[0]);
                                if (match) {
                                    ipv6AddressRange += match[1] + "<br>" + match[3] + match[5];
                                }

                                // add the range separator
                                ipv6AddressRange += "-<br>";

                                // get the second part of the range
                                match = ipV6.exec(ipv6Addresses[1]);
                                if (match) {
                                    ipv6AddressRange += match[1] + "<br>" + match[3] + match[5];
                                }

                                // if all we have is -<br>, then forget it
                                if (ipv6AddressRange.length > 5) {
                                    return ipv6AddressRange;
                                }
                            } else {

                                // format the ipv6 address
                                var v6match = ipV6.exec(ip);
                                if (v6match) {
                                    return v6match[1] + "<br>" + v6match[3] + v6match[5];
                                }
                            }
                        } else {

                            // format the ipv4 range
                            var v4rangeMatch = ipV4Range.exec(ip);
                            if (v4rangeMatch) {
                                return v4rangeMatch[1] + "-<br>" + v4rangeMatch[3];
                            }
                        }

                        // could not format it, just return it
                        return ip;
                    };

                    $scope.$watch(function() {
                        return HulkdDataSource.enabled;
                    }, function() {
                        $scope.load_list();
                    });

                    $scope.$watch(function() {
                        return $rootScope.ip_added_with_one_click === true;
                    }, function() {
                        $scope.applyFilters();
                        $rootScope.ip_added_with_one_click = false;
                    });

                    $scope.$watchGroup([ "whitelist.length", "meta.filteredList.length" ], function() {
                        if ($scope.whitelist.length === 0 || $scope.meta.filteredList.length === 0) {
                            $("#whitelist_select_all_checkbox").prop("checked", false);
                        }
                    });

                    $scope.selectPage = function(page) {
                        $("#whitelist_select_all_checkbox").prop("checked", false);

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.currentPage = page;
                        }

                        $scope.load_list();
                    };

                    $scope.selectPageSize = function() {
                        return $scope.load_list({ reset_focus: false });
                    };

                    /**
                     * Filter the list by the `meta.filter`.
                     */
                    $scope.filterList = function() {
                        $scope.meta.currentPage = 1;
                        $scope.load_list({ reset_focus: false });
                    };

                    /**
                     * Clear the filter if it is set.
                     */
                    $scope.toggleFilter = function() {
                        $scope.meta.filter = "";
                        $scope.load_list({ reset_focus: false });
                    };

                    $scope.sortList = function(meta) {
                        $scope.meta.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        $scope.applyFilters();
                    };

                    $scope.orderByComments = function(comment_object, ip_list) {
                        var comments_as_pairs = _.toPairs(comment_object);
                        var ips_as_pairs = [];

                        // get the IPs that have no comments
                        for (var i = 0; i < ip_list.length; i++) {
                            if (!_.has(comment_object, ip_list[i] )) {
                                var one_entry = [ip_list[i], "" ];
                                ips_as_pairs.push(one_entry);
                            }
                        }

                        // sort the IPs that have no comments
                        var sorted_pairs = _.sortBy(ips_as_pairs, function(pair) {
                            return $scope.ip_padder(pair[0]);
                        });

                        // sort the comments first by comment, then by IP address
                        comments_as_pairs.sort(compareComments);

                        // create an array of the IPs from the sorted comments
                        var just_ips_comments = _.map(comments_as_pairs, function(pair) {
                            return pair[0];
                        });

                        // create an array of the sorted IPs with no comments
                        var just_ips = _.map(sorted_pairs, function(pair) {
                            return pair[0];
                        });

                        // put the IPs with comments and the IPs without comments together
                        var stuck_together = just_ips_comments.concat(just_ips);

                        if ($scope.meta.sortDirection === "desc") {
                            return stuck_together.reverse();
                        }

                        return stuck_together;
                    };

                    /**
                     * Apply the sort, filter and pagination to the whitelist data.
                     *
                     * @returns {string[]} List of ips that pass the filters.
                     */
                    $scope.applyFilters = function() {
                        var filteredList = [];
                        var start, limit;

                        filteredList = $scope.whitelist;

                        // Sort
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            if ($scope.meta.sortBy === "white_ip") {
                                filteredList = filters.orderBy(filteredList, $scope.ip_padder, $scope.meta.sortReverse);
                            } else {
                                filteredList = $scope.orderByComments($scope.whitelist_comments, $scope.whitelist);
                            }
                        }

                        // Totals
                        $scope.meta.totalItems = $scope.whitelist.length;

                        // Filter content
                        var expected = $scope.meta.filter.toLowerCase();
                        if (expected) {
                            filteredList = filters.filter(filteredList, function(actual) {
                                return actual.indexOf(expected) !== -1 ||
                                       ($scope.whitelist_comments[actual] && $scope.whitelist_comments[actual].toLowerCase().indexOf(expected) !== -1);
                            });
                        }

                        // Track the filtered size separatly
                        $scope.meta.filteredItems = filteredList.length;

                        // Pagination
                        start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                        limit = $scope.meta.pageSize;
                        filteredList = filters.limitTo(filters.startFrom(filteredList, start), limit);

                        $scope.meta.pageNumberStart = start + 1;
                        $scope.meta.pageNumberEnd = ($scope.meta.currentPage * $scope.meta.pageSize);

                        if ($scope.meta.totalItems === 0) {
                            $scope.meta.pageNumberStart = 0;
                        }

                        if ($scope.meta.pageNumberEnd > $scope.meta.totalItems) {
                            $scope.meta.pageNumberEnd = $scope.meta.totalItems;
                        }

                        $scope.meta.filteredList = filteredList;

                        return filteredList;
                    };

                    $scope.load_list = function(options) {
                        if (HulkdDataSource.enabled && !$scope.loading) {

                            $scope.loading = true;
                            var reset_focus = typeof options !== "undefined" && options.hasOwnProperty("reset_focus") ? options.reset_focus : true;

                            if (HulkdDataSource.whitelist_is_cached) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                $scope.applyFilters();
                                if (reset_focus) {
                                    $scope.focus_on_whitelist();
                                }
                                $scope.loading = false;
                            } else {
                                $scope.meta.filteredList = [];
                                return HulkdDataSource.load_list("white")
                                    .then(function(results) {
                                        $scope.whitelist = HulkdDataSource.whitelist;
                                        $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                        $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                        $scope.applyFilters();

                                        // if the requester ip is not whitelisted and the growl does not exist or is not displayed, then display it
                                        if (results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted <= 0) {
                                            if (results.hasOwnProperty("requester_ip") && $rootScope.whitelist_warning_message === null) {
                                                $scope.growl_whitelist_warning(results.requester_ip);
                                            }
                                        }

                                        if (results.restart_ssh) {
                                            growl.warning(LOCALE.maketext("The system disabled the [asis,UseDNS] setting for [asis,SSHD] in order to add IP addresses to the whitelist. You must restart SSH through the [output,url,_1,Restart SSH Server,_2] page to implement the change.", PAGE.security_token + "/scripts/ressshd", { "target": "_blank" }));
                                        } else if (results.warning_ssh) {
                                            growl.warning(results.warning_ssh);
                                        }
                                    }, function(error) {
                                        growl.error(error);
                                    })
                                    .finally(function() {
                                        if (reset_focus) {
                                            $scope.focus_on_whitelist();
                                        }
                                        $scope.loading = false;
                                    });
                            }
                        }
                        return null;
                    };

                    $scope.force_load_whitelist = function() {
                        HulkdDataSource.whitelist_is_cached = false;
                        $scope.whitelist = [];
                        $scope.whitelist_comments = {};
                        $scope.meta.filteredList = [];
                        return $scope.load_list();
                    };

                    $scope.delete_confirmation_message = function() {
                        if ($scope.ips_to_delete.length === 1) {
                            return LOCALE.maketext("Do you want to permanently delete “[_1]” from the whitelist?", $scope.ips_to_delete[0]);
                        } else {
                            return LOCALE.maketext("Do you want to permanently delete [quant,_1,record,records] from the whitelist?", $scope.ips_to_delete.length);
                        }
                    };

                    $scope.itemsAreChecked = function() {
                        return $(".whitelist_select_item").filter(":checked").length > 0;
                    };

                    $scope.check_whitelist_selection = function() {
                        if ($(".whitelist_select_item").filter(":not(:checked)").length === 0) {
                            $("#whitelist_select_all_checkbox").prop("checked", true);
                        } else {
                            $("#whitelist_select_all_checkbox").prop("checked", false);
                        }
                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                    };

                    /**
                     * Get the list of ips selected in the UI.
                     *
                     * @returns <string[]> List if ips selected.
                     */
                    $scope.getSelection = function()  {
                        var selected_items = [],
                            $selected_dom_nodes = $(".whitelist_select_item:checked");

                        if ($selected_dom_nodes.length === 0) {
                            return [];
                        }

                        $selected_dom_nodes.each( function() {
                            selected_items.push($(this).data("ip"));
                        });

                        return selected_items;
                    };

                    $scope.confirm_whitelist_deletion = function(ip_to_delete) {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $scope.delete_in_progress = true;
                        if (ip_to_delete !== undefined) {
                            $scope.ips_to_delete = [ip_to_delete];
                            $scope.is_single_deletion = true;
                        } else {
                            var selected_items = $scope.getSelection();
                            if (selected_items.length === 0) {
                                return false;
                            }
                            $scope.ips_to_delete = selected_items;
                            $scope.is_single_deletion = false;
                        }

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_whitelist_deletion.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.clear_modal_instance = function() {
                        if ($scope.modal_instance) {
                            $scope.modal_instance.close();
                            $scope.modal_instance = null;
                        }
                    };

                    $scope.cancel_deletion = function() {
                        $scope.delete_in_progress = false;
                        $scope.ips_to_delete = [];
                        $scope.clear_modal_instance();
                        $scope.focus_on_whitelist();
                    };

                    $scope.delete_whitelist_ips = function(is_single_deletion) {
                        $scope.clear_modal_instance();
                        HulkdDataSource.remove_from_whitelist($scope.ips_to_delete)
                            .then( function(results) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.applyFilters();
                                $scope.focus_on_whitelist();

                                if (results.removed.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully deleted “[_1]” from the whitelist.", _.escape(results.removed[0])));
                                } else {
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the whitelist.", results.removed.length));
                                }

                                if ( results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted <= 0 && results.hasOwnProperty("requester_ip") ) {
                                    $scope.growl_whitelist_warning(results.requester_ip);
                                }

                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the whitelist.", results.not_removed.keys.length));
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.delete_in_progress = false;
                                $scope.ips_to_delete = [];
                                if (!is_single_deletion) {
                                    $scope.deselect_all_whitelist();
                                }

                                // Since this is using JQuery/DOM, we have to wait another tick for the UI to update
                                // before we try to get the selection.
                                $timeout(function() {
                                    $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                    $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                                });
                            });
                    };

                    $scope.confirm_delete_all = function() {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $scope.delete_in_progress = true;

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_whitelist_delete_all.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.cancel_delete_all = function() {
                        $scope.delete_in_progress = false;
                        $scope.clear_modal_instance();
                        $scope.focus_on_whitelist();
                    };

                    $scope.delete_all = function() {
                        $scope.clear_modal_instance();
                        HulkdDataSource.remove_all_from_whitelist()
                            .then( function(results) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.applyFilters();
                                $scope.focus_on_whitelist();
                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the whitelist.", results.removed.keys.length));
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the whitelist.", results.not_removed.keys.length));
                                } else {
                                    growl.success(LOCALE.maketext("You have deleted all records from the whitelist."));
                                }

                                if ( results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted <= 0 && results.hasOwnProperty("requester_ip") ) {
                                    $scope.growl_whitelist_warning(results.requester_ip);
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.delete_in_progress = false;
                                $scope.deselect_all_whitelist();

                                // Since this is using JQuery/DOM, we have to wait another tick for the UI to update
                                // before we try to get the selection.
                                $timeout(function() {
                                    $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                    $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                                });
                            });
                    };

                    $scope.select_all_whitelist = function() {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $(".whitelist_select_item").prop("checked", true);
                        $("#whitelist_select_all_checkbox").prop("checked", true);

                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();

                        return true;
                    };

                    $scope.deselect_all_whitelist = function() {
                        if ($scope.whitelist.length === 0) {
                            return false;
                        }
                        $(".whitelist_select_item").prop("checked", false);
                        $("#whitelist_select_all_checkbox").prop("checked", false);

                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();

                        return true;
                    };

                    $scope.toggle_whitelist_selection = function() {
                        if ($("#whitelist_select_all_checkbox").prop("checked") === true) {
                            $scope.select_all_whitelist();
                        } else {
                            $scope.deselect_all_whitelist();
                        }
                    };

                    $scope.focus_on_whitelist = function() {
                        var whitelist_batch_field = $("#whitelist_batch_add");
                        var wait_id = setInterval( function() {
                            if (whitelist_batch_field.is(":visible")) {
                                whitelist_batch_field.focus();
                                whitelist_batch_field.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    /**
                     *
                     * @typedef Record
                     * @property {string} ip
                     * @property {string?} comment
                     */

                    /**
                     * Parse the batch of records.
                     *
                     * @param {string} text
                     * @returns {Record[]}
                     */
                    function parseBatch(text) {
                        var lines = text.split("\n");
                        var records = [];

                        for (var i = 0; i < lines.length; i++) {
                            var line = lines[i];
                            if (line && line.length > 0) {
                                var parts = line.split("#");
                                var ip = parts.shift().trim();
                                var comment = parts.join("#").trim();
                                records.push({
                                    ip: ip,
                                    comment: comment,
                                });
                            }
                        }
                        return records;
                    }

                    /**
                     * Add a batch of records to the whitelist.
                     *
                     * @async
                     * @returns
                     */
                    $scope.add_to_whitelist = function() {
                        if (!$scope.new_whitelist_records || $scope.adding_batch_to_whitelist) {
                            return;
                        }

                        var records = parseBatch($scope.new_whitelist_records);
                        return $scope._add_to_whitelist(records);
                    };

                    /**
                     * Add a batch of whitelist records.
                     *
                     * @private
                     * @param {Record[]} batch
                     * @returns
                     */
                    $scope._add_to_whitelist = function(batch) {
                        $scope.adding_batch_to_whitelist = true;
                        return HulkdDataSource.add_to_whitelist(batch)
                            .then( function(results) {
                                $scope.whitelist = HulkdDataSource.whitelist;
                                $scope.whitelist_comments = HulkdDataSource.whitelist_comments;
                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                $scope.applyFilters();

                                if (results.added.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully added “[_1]” to the whitelist.", _.escape(results.added[0])));
                                } else if (results.added.length > 1) {
                                    growl.success(LOCALE.maketext("You have successfully added [quant,_1,IP address,IP addresses] to the whitelist.", results.added.length));
                                }

                                if (results.updated.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(results.updated[0])));
                                } else if (results.updated.length > 1) {
                                    growl.success(LOCALE.maketext("You have successfully updated the [numerate,_1,comment,comments] for [quant,_1,IP address,IP addresses].", results.updated.length));
                                }

                                // if requester ip is marked as being whitelisted in the last call, but the growl warning
                                // is still displayed then hide the growl warning
                                if (results.hasOwnProperty("requester_ip_is_whitelisted") && results.requester_ip_is_whitelisted > 0 && $rootScope.whitelist_warning_message !== null) {
                                    $rootScope.whitelist_warning_message.ttl = 0;
                                    $rootScope.whitelist_warning_message.promises = [];
                                    $rootScope.whitelist_warning_message.promises.push($timeout(angular.bind(growlMessages, function() {
                                        growlMessages.deleteMessage($rootScope.whitelist_warning_message);
                                        $rootScope.whitelist_warning_message = null;
                                    }), 200));
                                }

                                var rejectedIps = Object.keys(results.rejected);
                                if (rejectedIps.length > 0) {
                                    var accumulatedMessages = LOCALE.maketext("Some IP addresses were not added to the whitelist.");
                                    accumulatedMessages += "<br>\n";

                                    // Put the rejected ips/comments back in the list.
                                    $scope.new_whitelist_records = rejectedIps.map(function(ip) {
                                        var record = batch.find(function(record) {
                                            return record.ip === ip;
                                        });
                                        if (record && record.comment) {
                                            return ip + " # " + record.comment + "\n";
                                        }
                                        return ip + "\n";
                                    }).join("");

                                    // Report the problems in the growl
                                    accumulatedMessages += "<ul>\n";
                                    rejectedIps.forEach(function(ip) {
                                        if (results.rejected[ip]) {
                                            accumulatedMessages += "<li>" + _.escape(results.rejected[ip]) + "</li>\n";
                                        }
                                    });
                                    accumulatedMessages += "</ul>\n";
                                    growl.error(accumulatedMessages);

                                } else {
                                    $scope.new_whitelist_records = "";
                                }
                            }, function(error_details) {
                                var error = error_details.main_message;

                                // Format the individual partial errors.
                                var secondary_count = error_details.secondary_messages.length;
                                if (secondary_count > 0) {
                                    error += "<ul>\n";
                                }

                                error_details.secondary_messages.forEach(function(message) {
                                    error += "<li>" + _.escape(message) + "</li>\n";
                                });

                                if (secondary_count > 0) {
                                    error += "</ul>\n";
                                }

                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.adding_batch_to_whitelist = false;
                                $scope.focus_on_whitelist();
                            });
                    };

                    // TODO: Make this a utility system: ip-comparison
                    $scope.ip_padder = function(unpadded) {
                        var padded_ip = "";
                        if (unpadded) {
                            var split_ip = unpadded.split(".");
                            for (var i = 0; i < split_ip.length; i++) {
                                var this_section = split_ip[i];
                                while ( this_section.length < 3) {
                                    this_section = "0" + this_section;
                                }
                                padded_ip += this_section;
                            }
                        }
                        return padded_ip;
                    };

                    function compareComments(a, b) {

                        // sort by comment
                        if (a[1].toLowerCase() < b[1].toLowerCase()) {
                            return -1;
                        }
                        if (a[1].toLowerCase() > b[1].toLowerCase()) {
                            return 1;
                        }

                        // we have a duplicate comment, so sort by IP address
                        if ($scope.ip_padder(a[0]) < $scope.ip_padder(b[0])) {
                            return -1;
                        }
                        if ($scope.ip_padder(a[0]) > $scope.ip_padder(b[0])) {
                            return 1;
                        }

                        // we have a duplicate comment and IP
                        return 0;
                    }

                    /**
                     * Generate the download name.
                     *
                     * @returns {string} - the name of the download.
                     */
                    $scope.downloadName = function() {
                        return Download.getDownloadName("whitelist");
                    };

                    /**
                     * @typedef IpRecord
                     * @property {string} ip - ip address or range.
                     * @property {string?} comment - comment associated with the ip or range.
                     */

                    /**
                     * Package the ips and comments into a records structure
                     *
                     * @param {string[]} ips
                     * @param {Dictionary<string,string>} comments
                     * @returns {IpRecord[]}
                     */
                    function getRecords(ips, comments) {
                        var list = [];
                        ips.forEach(function(ip) {
                            var comment = comments[ip];
                            list.push({ ip: ip, comment: comment });
                        });
                        return list;
                    }

                    /**
                     * Generate a data blob url that contains all the whitelist ips.
                     *
                     * @returns {string} - data url.
                     */
                    $scope.generateDownloadAllLink = function() {

                        if ($scope.downloadAllLink) {

                            // Clean up the previous url
                            Download.cleanupDownloadUrl($scope.downloadAllLink);
                            $scope.downloadAllLink = null;
                        }

                        var ips = $scope.whitelist;
                        if (!ips || ips.length === 0) {
                            return "";
                        }

                        var list = getRecords(ips, $scope.whitelist_comments);
                        return Download.getTextDownloadUrl(Download.formatList(list));
                    };

                    /**
                     * Generate a data blob url that contains the selected whitelist ips.
                     *
                     * @returns {string} - data url.
                     */
                    $scope.generateDownloadSelectionLink = function() {
                        if ($scope.downloadSelectionLink) {

                            // Clean up the previous url
                            Download.cleanupDownloadUrl($scope.downloadSelectionLink);
                            $scope.downloadSelectionLink = null;
                        }

                        if (!$scope.whitelist || $scope.whitelist.length === 0) {
                            return "";
                        }

                        var selection = $scope.getSelection();
                        if (!selection || selection.length === 0) {
                            return "";
                        }

                        var list = getRecords(selection, $scope.whitelist_comments);

                        return Download.getTextDownloadUrl(Download.formatList(list));
                    };

                    $scope.focus_on_whitelist();
                },
            ]);

        return controller;
    }
);

/*
# cpanel - whostmgr/docroot/templates/hulkd/views/hulkdBlacklistController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint camelcase: 0, no-prototype-builtins: 0 */

define(
    'app/views/hulkdBlacklistController',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "app/utils/download",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/decorators/growlDecorator",
        "cjt/filters/startFromFilter",
        "app/services/HulkdDataSource",
    ],
    function(angular, $, _, LOCALE, Download) {

        "use strict";

        // Retrieve the current application
        var app = angular.module("App");
        app.config([ "$compileProvider",
            function($compileProvider) {
                $compileProvider.aHrefSanitizationWhitelist(/^blob:https:/);
            },
        ]);

        var controller = app.controller(
            "hulkdBlacklistController",
            ["$scope", "$filter", "$routeParams", "$uibModal", "HulkdDataSource", "growl", "PAGE", "$timeout",
                function($scope, $filter, $routeParams, $uibModal, HulkdDataSource, growl, PAGE, $timeout) {

                    $scope.blacklist_reverse = false;

                    $scope.blacklist = [];
                    $scope.blacklist_comments = {};

                    $scope.adding_batch_to_blacklist = false;

                    $scope.new_blacklist_records = "";

                    $scope.ip_being_edited = false;
                    $scope.current_ip = null;
                    $scope.current_comment = "";
                    $scope.updating_comment = false;

                    $scope.modal_instance = null;

                    $scope.loading = false;

                    $scope.downloadAllLink = "";
                    $scope.downloadSelectionLink = "";

                    $scope.meta = {
                        sortDirection: "asc",
                        sortBy: "black_ip",
                        sortType: "",
                        sortReverse: false,
                        filter: "",
                        maxPages: 0,
                        totalItems: $scope.blacklist.length || 0,
                        currentPage: 1,
                        pageNumberStart: 0,
                        pageNumberEnd: 0,
                        pageSize: 20,
                        pageSizes: [20, 50, 100],
                    };

                    $scope.LOCALE = LOCALE;

                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                        startFrom: $filter("startFrom"),
                        limitTo: $filter("limitTo"),
                    };

                    $scope.delete_in_progress = false;
                    $scope.ips_to_delete = [];

                    $scope.selecting_page_size = false;

                    $scope.edit_blacklist_ip = function(blacklist_ip) {
                        $scope.current_ip = blacklist_ip;
                        $scope.current_comment = $scope.blacklist_comments.hasOwnProperty(blacklist_ip) ? $scope.blacklist_comments[blacklist_ip] : "";
                        $scope.ip_being_edited = true;
                        var blacklist_comment_field = $("#blacklist_current_comment");
                        var wait_id = setInterval( function() {
                            if (blacklist_comment_field.is(":visible")) {
                                blacklist_comment_field.focus();
                                blacklist_comment_field.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    $scope.cancel_blacklist_editing = function() {
                        $scope.current_ip = null;
                        $scope.current_comment = "";
                        $scope.ip_being_edited = false;
                        $scope.focus_on_blacklist();
                    };

                    $scope.delete_tooltip = function(ip_address) {
                        return LOCALE.maketext("Click to delete “[_1]” from the blacklist.", ip_address);
                    };

                    $scope.edit_tooltip = function(ip_address) {
                        return LOCALE.maketext("Click to edit the comment for “[_1]”.", ip_address);
                    };

                    $scope.update_blacklist_comment = function() {
                        if ($scope.updating_comment) {
                            return;
                        }

                        $scope.updating_comment = true;
                        HulkdDataSource.add_to_blacklist([ { ip: $scope.current_ip, comment: $scope.current_comment } ])
                            .then( function(results) {
                                $scope.blacklist_comments = HulkdDataSource.blacklist_comments;

                                // Growl out each success from the batch.
                                results.updated.forEach(function(ip) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(ip)));
                                });

                                // Report the failures from the batch.
                                var rejectedMessages = [];
                                Object.keys(results.rejected).forEach(function(ip) {
                                    rejectedMessages.push(_.escape(ip) + ": " + _.escape(results.rejected[ip]));
                                });

                                if (rejectedMessages.length > 0) {
                                    var accumulatedMessages = LOCALE.maketext("Some records failed to update.") + "<br>";
                                    accumulatedMessages += rejectedMessages.join("<br>");
                                    growl.error(accumulatedMessages);
                                }

                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.updating_comment = false;
                                $scope.cancel_blacklist_editing();
                                $scope.focus_on_blacklist();
                            });
                    };

                    var ipV6 = /^(([\da-fA-F]{1,4}:){4})(([\da-fA-F]{1,4}:){3})([\da-fA-F]{1,4})$/;
                    var ipV4Range = /^((\d{1,3}.){3}\d{1,3})-((\d{1,3}.){3}\d{1,3})$/;
                    var ipRangeTest = /-/;
                    var ipV6Test = /:/;

                    /**
                     * Separates long ipv4 and ipv6 addresses with br tags.
                     * Also, supports separating ipv4 and ipv6 address ranges.
                     *
                     * @param {string} ip - an ip address
                     * @todo Implement this as an Angular Filter in a separate file
                     */
                    $scope.splitLongIp = function(ip) {

                        // ipv6?
                        if (ipV6Test.test(ip)) {

                            // is this a range?
                            if (ipRangeTest.test(ip)) {

                                // format the ipv6 addresses in range format
                                var ipv6Addresses = ip.split(ipRangeTest);
                                var ipv6AddressRange = "";

                                // get the first part of the range
                                var match = ipV6.exec(ipv6Addresses[0]);
                                if (match) {
                                    ipv6AddressRange += match[1] + "<br>" + match[3] + match[5];
                                }

                                // add the range separator
                                ipv6AddressRange += "-<br>";

                                // get the second part of the range
                                match = ipV6.exec(ipv6Addresses[1]);
                                if (match) {
                                    ipv6AddressRange += match[1] + "<br>" + match[3] + match[5];
                                }

                                // if all we have is -<br>, then forget it
                                if (ipv6AddressRange.length > 5) {
                                    return ipv6AddressRange;
                                }
                            } else {

                                // format the ipv6 address
                                var v6match = ipV6.exec(ip);
                                if (v6match) {
                                    return v6match[1] + "<br>" + v6match[3] + v6match[5];
                                }
                            }
                        } else {

                            // format the ipv4 range
                            var v4rangeMatch = ipV4Range.exec(ip);
                            if (v4rangeMatch) {
                                return v4rangeMatch[1] + "-<br>" + v4rangeMatch[3];
                            }
                        }

                        // could not format it, just return it
                        return ip;
                    };

                    $scope.$watch(function() {
                        return HulkdDataSource.enabled;
                    }, function() {
                        $scope.load_list();
                    });

                    $scope.$watchGroup([ "blacklist.length", "meta.filteredList.length" ], function() {
                        if ($scope.blacklist.length === 0 || $scope.meta.filteredList.length === 0) {
                            $("#blacklist_select_all_checkbox").prop("checked", false);
                        }
                    });

                    $scope.selectPage = function(page) {
                        $("#blacklist_select_all_checkbox").prop("checked", false);

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.currentPage = page;
                        }

                        $scope.load_list();
                    };

                    $scope.selectPageSize = function() {
                        return $scope.load_list({ reset_focus: false });
                    };

                    /**
                     * Filter the list by the `meta.filter`.
                     */
                    $scope.filterList = function() {
                        $scope.meta.currentPage = 1;
                        $scope.load_list({ reset_focus: false });
                    };

                    /**
                     * Clear the filter if it is set.
                     */
                    $scope.toggleFilter = function() {
                        $scope.meta.filter = "";
                        $scope.load_list({ reset_focus: false });
                    };

                    $scope.sortList = function(meta) {
                        $scope.meta.sortReverse = (meta.sortDirection === "asc") ? false : true;
                        $scope.applyFilters();
                    };

                    $scope.orderByComments = function(comment_object, ip_list) {
                        var comments_as_pairs = _.toPairs(comment_object);
                        var ips_as_pairs = [];

                        // get the IPs that have no comments
                        for (var i = 0; i < ip_list.length; i++) {
                            if (!_.has(comment_object, ip_list[i] )) {
                                var one_entry = [ip_list[i], "" ];
                                ips_as_pairs.push(one_entry);
                            }
                        }

                        // sort the IPs that have no comments
                        var sorted_pairs = _.sortBy(ips_as_pairs, function(pair) {
                            return $scope.ip_padder(pair[0]);
                        });

                        // sort the comments first by comment, then by IP address
                        comments_as_pairs.sort(compareComments);

                        // create an array of the IPs from the sorted comments
                        var just_ips_comments = _.map(comments_as_pairs, function(pair) {
                            return pair[0];
                        });

                        // create an array of the sorted IPs with no comments
                        var just_ips = _.map(sorted_pairs, function(pair) {
                            return pair[0];
                        });

                        // put the IPs with comments and the IPs without comments together
                        var stuck_together = just_ips_comments.concat(just_ips);

                        if ($scope.meta.sortDirection === "desc") {
                            return stuck_together.reverse();
                        }

                        return stuck_together;
                    };

                    /**
                     * Apply the sort, filter and pagination to the blacklist data.
                     *
                     * @returns {string[]} List of ips that pass the filters.
                     */
                    $scope.applyFilters = function() {
                        var filteredList = [];
                        var start, limit;

                        filteredList = $scope.blacklist;

                        // Sort
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            if ($scope.meta.sortBy === "black_ip") {
                                filteredList = filters.orderBy(filteredList, $scope.ip_padder, $scope.meta.sortReverse);
                            } else {
                                filteredList = $scope.orderByComments($scope.blacklist_comments, $scope.blacklist);
                            }
                        }

                        // Totals
                        $scope.meta.totalItems = $scope.blacklist.length;

                        // Filter content
                        var expected = $scope.meta.filter.toLowerCase();
                        if (expected) {
                            filteredList = filters.filter(filteredList, function(actual) {
                                return actual.indexOf(expected) !== -1 ||
                                       ($scope.blacklist_comments[actual] && $scope.blacklist_comments[actual].toLowerCase().indexOf(expected) !== -1);
                            });
                        }

                        // Track the filtered size separatly
                        $scope.meta.filteredItems = filteredList.length;

                        // Pagination
                        start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                        limit = $scope.meta.pageSize;
                        filteredList = filters.limitTo(filters.startFrom(filteredList, start), limit);

                        $scope.meta.pageNumberStart = start + 1;
                        $scope.meta.pageNumberEnd = ($scope.meta.currentPage * $scope.meta.pageSize);


                        if ($scope.meta.totalItems === 0) {
                            $scope.meta.pageNumberStart = 0;
                        }

                        if ($scope.meta.pageNumberEnd > $scope.meta.totalItems) {
                            $scope.meta.pageNumberEnd = $scope.meta.totalItems;
                        }

                        $scope.meta.filteredList = filteredList;

                        return filteredList;
                    };

                    $scope.load_list = function(options) {
                        if (HulkdDataSource.enabled && !$scope.loading) {

                            $scope.loading = true;
                            var reset_focus = typeof options !== "undefined" && options.hasOwnProperty("reset_focus") ? options.reset_focus : true;

                            if (HulkdDataSource.blacklist_is_cached) {
                                $scope.blacklist = HulkdDataSource.blacklist;
                                $scope.blacklist_comments = HulkdDataSource.blacklist_comments;
                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                $scope.applyFilters();
                                if (reset_focus) {
                                    $scope.focus_on_blacklist();
                                }
                                $scope.loading = false;
                            } else {
                                $scope.meta.filteredList = [];
                                return HulkdDataSource.load_list("black")
                                    .then(function() {
                                        $scope.blacklist = HulkdDataSource.blacklist;
                                        $scope.blacklist_comments = HulkdDataSource.blacklist_comments;
                                        $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                        $scope.applyFilters();
                                    }, function(error) {
                                        growl.error(error);
                                    })
                                    .finally(function() {
                                        if (reset_focus) {
                                            $scope.focus_on_blacklist();
                                        }
                                        $scope.selecting_page_size = false;
                                        $scope.loading = false;
                                    });
                            }
                        }
                        return null;
                    };

                    $scope.force_load_blacklist = function() {
                        HulkdDataSource.blacklist_is_cached = false;
                        $scope.blacklist = [];
                        $scope.blacklist_comments = {};
                        $scope.meta.filteredList = [];
                        return $scope.load_list();
                    };

                    $scope.delete_confirmation_message = function() {
                        if ($scope.ips_to_delete.length === 1) {
                            return LOCALE.maketext("Do you want to permanently delete “[_1]” from the blacklist?", $scope.ips_to_delete[0]);
                        } else {
                            return LOCALE.maketext("Do you want to permanently delete [quant,_1,record,records] from the backlist?", $scope.ips_to_delete.length);
                        }
                    };

                    $scope.itemsAreChecked = function() {
                        return $(".blacklist_select_item").filter(":checked").length > 0;
                    };

                    $scope.check_blacklist_selection = function() {
                        if ($(".blacklist_select_item").filter(":not(:checked)").length === 0) {
                            $("#blacklist_select_all_checkbox").prop("checked", true);
                        } else {
                            $("#blacklist_select_all_checkbox").prop("checked", false);
                        }
                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                    };

                    /**
                     * Get the list of ips selected in the UI.
                     *
                     * @returns <string[]> List if ips selected.
                     */
                    $scope.getSelection = function()  {
                        var selected_items = [],
                            $selected_dom_nodes = $(".blacklist_select_item:checked");

                        if ($selected_dom_nodes.length === 0) {
                            return [];
                        }

                        $selected_dom_nodes.each( function() {
                            selected_items.push($(this).data("ip"));
                        });

                        return selected_items;
                    };

                    $scope.confirm_blacklist_deletion = function(ip_to_delete) {
                        if ($scope.blacklist.length === 0) {
                            return false;
                        }

                        $scope.delete_in_progress = true;
                        if (ip_to_delete !== undefined) {
                            $scope.ips_to_delete = [ip_to_delete];
                            $scope.is_single_deletion = true;
                        } else {
                            var selected_items = $scope.getSelection();
                            if (selected_items.length === 0) {
                                return false;
                            }
                            $scope.ips_to_delete = selected_items;
                            $scope.is_single_deletion = false;
                        }

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_blacklist_deletion.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.clear_modal_instance = function() {
                        if ($scope.modal_instance) {
                            $scope.modal_instance.close();
                            $scope.modal_instance = null;
                        }
                    };

                    $scope.cancel_deletion = function() {
                        $scope.delete_in_progress = false;
                        $scope.ips_to_delete = [];
                        $scope.clear_modal_instance();
                        $scope.focus_on_blacklist();
                    };

                    $scope.delete_blacklist_ips = function(is_single_deletion) {
                        $scope.clear_modal_instance();
                        HulkdDataSource.remove_from_blacklist($scope.ips_to_delete)
                            .then( function(results) {
                                $scope.blacklist = HulkdDataSource.blacklist;
                                $scope.blacklist_comments = HulkdDataSource.blacklist_comments;
                                $scope.applyFilters();
                                $scope.focus_on_blacklist();

                                if (results.removed.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully deleted “[_1]” from the blacklist.", _.escape(results.removed[0])));
                                } else {
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the blacklist.", results.removed.length));
                                }

                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the blacklist.", results.not_removed.keys.length));
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.delete_in_progress = false;
                                $scope.ips_to_delete = [];
                                if (!is_single_deletion) {
                                    $scope.deselect_all_blacklist();
                                }

                                // Since this is using JQuery/DOM, we have to wait another tick for the UI to update
                                // before we try to get the selection.
                                $timeout(function() {
                                    $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                    $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                                });
                            });
                    };

                    $scope.confirm_delete_all = function() {
                        if ($scope.blacklist.length === 0) {
                            return false;
                        }
                        $scope.delete_in_progress = true;

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_blacklist_delete_all.html",
                            scope: $scope,
                        });

                        return true;
                    };

                    $scope.cancel_delete_all = function() {
                        $scope.delete_in_progress = false;
                        $scope.clear_modal_instance();
                        $scope.focus_on_blacklist();
                    };

                    $scope.delete_all = function() {
                        $scope.clear_modal_instance();
                        HulkdDataSource.remove_all_from_blacklist()
                            .then( function(results) {
                                $scope.blacklist = HulkdDataSource.blacklist;
                                $scope.blacklist_comments = HulkdDataSource.blacklist_comments;
                                $scope.applyFilters();
                                $scope.focus_on_blacklist();
                                if (results.not_removed.keys && results.not_removed.keys.length > 0) {
                                    growl.success(LOCALE.maketext("You have successfully deleted [quant,_1,record,records] from the blacklist.", results.removed.keys.length));
                                    growl.warning(LOCALE.maketext("The system was unable to delete [quant,_1,record,records] from the blacklist.", results.not_removed.keys.length));
                                } else {
                                    growl.success(LOCALE.maketext("You have deleted all records from the blacklist."));
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally( function() {
                                $scope.delete_in_progress = false;
                                $scope.deselect_all_blacklist();

                                // Since this is using JQuery/DOM, we have to wait another tick for the UI to update
                                // before we try to get the selection.
                                $timeout(function() {
                                    $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                    $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();
                                });
                            });
                    };

                    $scope.select_all_blacklist = function() {
                        if ($scope.blacklist.length === 0) {
                            return false;
                        }
                        $(".blacklist_select_item").prop("checked", true);
                        $("#blacklist_select_all_checkbox").prop("checked", true);

                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();

                        return true;
                    };

                    $scope.deselect_all_blacklist = function() {
                        if ($scope.blacklist.length === 0) {
                            return false;
                        }
                        $(".blacklist_select_item").prop("checked", false);
                        $("#blacklist_select_all_checkbox").prop("checked", false);

                        $scope.downloadSelectionLink = $scope.generateDownloadSelectionLink();

                        return true;
                    };

                    $scope.toggle_blacklist_selection = function() {
                        if ($("#blacklist_select_all_checkbox").prop("checked") === true) {
                            $scope.select_all_blacklist();
                        } else {
                            $scope.deselect_all_blacklist();
                        }
                    };

                    $scope.focus_on_blacklist = function() {
                        var blacklist_batch_field = $("#blacklist_batch_add");
                        var wait_id = setInterval( function() {
                            if (blacklist_batch_field.is(":visible")) {
                                blacklist_batch_field.focus();
                                blacklist_batch_field.select();
                                clearInterval(wait_id);
                            }
                        }, 250);
                    };

                    /**
                     *
                     * @typedef Record
                     * @property {string} ip
                     * @property {string?} comment
                     */

                    /**
                     * Parse the batch of records.
                     *
                     * @param {string} text
                     * @returns {Record[]}
                     */
                    function parseBatch(text) {
                        var lines = text.split("\n");
                        var records = [];

                        for (var i = 0; i < lines.length; i++) {
                            var line = lines[i];
                            if (line && line.length > 0) {
                                var parts = line.split("#");
                                var ip = parts.shift().trim();
                                var comment = parts.join("#").trim();
                                records.push({
                                    ip: ip,
                                    comment: comment,
                                });
                            }
                        }
                        return records;
                    }

                    /**
                     * Add a batch of records to the blacklist.
                     *
                     * @async
                     * @returns
                     */
                    $scope.add_to_blacklist = function() {
                        if (!$scope.new_blacklist_records || $scope.adding_batch_to_blacklist) {
                            return;
                        }

                        var records = parseBatch($scope.new_blacklist_records);
                        return $scope._add_to_blacklist(records);
                    };

                    /**
                     * Add a batch of blacklist records.
                     *
                     * @private
                     * @param {Record[]} batch
                     * @returns
                     */
                    $scope._add_to_blacklist = function(batch) {
                        $scope.adding_batch_to_blacklist = true;
                        HulkdDataSource.add_to_blacklist(batch)
                            .then( function(results) {
                                $scope.blacklist = HulkdDataSource.blacklist;
                                $scope.blacklist_comments = HulkdDataSource.blacklist_comments;
                                $scope.downloadAllLink = $scope.generateDownloadAllLink();
                                $scope.applyFilters();

                                if (results.added.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully added “[_1]” to the blacklist.", _.escape(results.added[0])));
                                } else if (results.added.length > 1) {
                                    growl.success(LOCALE.maketext("You have successfully added [quant,_1,IP address,IP addresses] to the blacklist.", results.added.length));
                                }

                                if (results.updated.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(results.updated[0])));
                                } else if (results.updated.length > 1) {
                                    growl.success(LOCALE.maketext("You have successfully updated the [numerate,_1,comment,comments] for [quant,_1,IP address,IP addresses].", results.updated.length));
                                }

                                var rejectedIps = Object.keys(results.rejected);
                                if (rejectedIps.length > 0) {
                                    var accumulatedMessages = LOCALE.maketext("Some IP addresses were not added to the blacklist.");
                                    accumulatedMessages += "<br>\n";

                                    // Put the rejected ips/comments back in the list.
                                    $scope.new_blacklist_records = rejectedIps.map(function(ip) {
                                        var record = batch.find(function(record) {
                                            return record.ip === ip;
                                        });
                                        if (record && record.comment) {
                                            return ip + " # " + record.comment + "\n";
                                        }
                                        return ip + "\n";
                                    }).join("");

                                    // Report the problems in the growl
                                    accumulatedMessages += "<ul>\n";
                                    rejectedIps.forEach(function(ip) {
                                        if (results.rejected[ip]) {
                                            accumulatedMessages += "<li>" + _.escape(results.rejected[ip]) + "</li>\n";
                                        }
                                    });
                                    accumulatedMessages += "</ul>\n";
                                    growl.error(accumulatedMessages);
                                } else {
                                    $scope.new_blacklist_records = "";
                                }
                            }, function(error_details) {
                                var error = error_details.main_message;

                                // Format the individual partial errors.
                                var secondary_count = error_details.secondary_messages.length;
                                if (secondary_count > 0) {
                                    error += "<ul>\n";
                                }

                                error_details.secondary_messages.forEach(function(message) {
                                    error += "<li>" + _.escape(message) + "</li>\n";
                                });

                                if (secondary_count > 0) {
                                    error += "</ul>\n";
                                }

                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.adding_batch_to_blacklist = false;
                                $scope.focus_on_blacklist();
                            });
                    };

                    // Handle auto-adding an ip from a query param or POST
                    if (($routeParams["ip"] && $routeParams["ip"].length > 0) ||
                        PAGE.ipToAdd !== null) {
                        var ip;
                        var comment = "";

                        if ($routeParams["ip"] && $routeParams["ip"].length > 0) {

                            // added via a query param
                            ip = $routeParams["ip"];
                        } else if (PAGE.ipToAdd !== null) {

                            // added via a POST and stuffed into PAGE
                            ip = PAGE.ipToAdd;
                        }

                        // clear the ip so we don't add it again
                        PAGE.ipToAdd = null;

                        if (ip !== void 0) {
                            $scope._add_to_blacklist([ { ip: ip, comment: comment } ]);
                        }
                    }

                    // TODO: Make this a utility system: ip-comparison
                    $scope.ip_padder = function(unpadded) {
                        var padded_ip = "";
                        if (unpadded) {
                            var split_ip = unpadded.split(".");
                            for (var i = 0; i < split_ip.length; i++) {
                                var this_section = split_ip[i];
                                while ( this_section.length < 3) {
                                    this_section = "0" + this_section;
                                }
                                padded_ip += this_section;
                            }
                        }
                        return padded_ip;
                    };

                    function compareComments(a, b) {

                        // sort by comment
                        if (a[1].toLowerCase() < b[1].toLowerCase()) {
                            return -1;
                        }
                        if (a[1].toLowerCase() > b[1].toLowerCase()) {
                            return 1;
                        }

                        // we have a duplicate comment, so sort by IP address
                        if ($scope.ip_padder(a[0]) < $scope.ip_padder(b[0])) {
                            return -1;
                        }
                        if ($scope.ip_padder(a[0]) > $scope.ip_padder(b[0])) {
                            return 1;
                        }

                        // we have a duplicate comment and IP
                        return 0;
                    }

                    /**
                     * Generate the download name.
                     *
                     * @returns {string} - the name of the download.
                     */
                    $scope.downloadName = function() {
                        return Download.getDownloadName("blacklist");
                    };

                    /**
                     * @typedef IpRecord
                     * @property {string} ip - ip address or range.
                     * @property {string?} comment - comment associated with the ip or range.
                     */

                    /**
                     * Package the ips and comments into a records structure
                     *
                     * @param {string[]} ips
                     * @param {Dictionary<string,string>} comments
                     * @returns {IpRecord[]}
                     */
                    function getRecords(ips, comments) {
                        var list = [];
                        ips.forEach(function(ip) {
                            var comment = comments[ip];
                            list.push({ ip: ip, comment: comment });
                        });
                        return list;
                    }

                    /**
                     * Generate a data blob url that contains all the blacklist ips.
                     *
                     * @returns {string} - data url.
                     */
                    $scope.generateDownloadAllLink = function() {
                        if ($scope.downloadAllLink) {

                            // Clean up the previous url
                            Download.cleanupDownloadUrl($scope.downloadAllLink);
                            $scope.downloadAllLink = null;
                        }

                        var ips = $scope.blacklist;
                        if (!ips || ips.length === 0) {
                            return "";
                        }

                        var list = getRecords(ips, $scope.blacklist_comments);
                        return Download.getTextDownloadUrl(Download.formatList(list));
                    };

                    /**
                     * Generate a data blob url that contains the selected blacklist ips.
                     *
                     * @returns {string} - data url.
                     */
                    $scope.generateDownloadSelectionLink = function() {
                        if ($scope.downloadSelectionLink) {

                            // Clean up the previous url
                            Download.cleanupDownloadUrl($scope.downloadSelectionLink);
                            $scope.downloadSelectionLink = null;
                        }

                        if (!$scope.blacklist || $scope.blacklist.length === 0) {
                            return "";
                        }

                        var selection = $scope.getSelection();
                        if (!selection || selection.length === 0) {
                            return "";
                        }

                        var list = getRecords(selection, $scope.blacklist_comments);

                        return Download.getTextDownloadUrl(Download.formatList(list));
                    };


                    $scope.focus_on_blacklist();
                },
            ]);

        return controller;
    }
);

/* global define: false */

define(
    'app/services/FailedLoginService',[

        // Libraries
        "angular",

        // Application

        // CJT
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1" // IMPORTANT: Load the driver so its ready
    ],
    function(angular, LOCALE, API, APIREQUEST, APIDRIVER) {

        var app = angular.module("App");

        app.factory("FailedLoginService", ["$q", function($q) {

            var exports = {};

            function normalizeData(data) {

                // make the timeleft field an actual integer for sorting
                if (angular.isDefined(data.timeleft)) {
                    data.timeleft = parseInt(data.timeleft, 10);
                }

                // make the authservice the same as the service if there is no authservice specified
                if (angular.isDefined(data.service) && angular.isDefined(data.authservice)) {
                    if (data.authservice === "") {
                        data.authservice = data.service;
                    }
                }

                return data;
            }


            function convertResponseData(responseData) {
                var items = [];

                for (var i = 0, len = responseData.length; i < len; i++) {
                    items.push(normalizeData(responseData[i]));
                }

                return items;
            }

            exports.getBrutes = function(meta) {
                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_brutes");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.getExcessiveBrutes = function(meta) {

                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_excessive_brutes");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.getFailedLogins = function(meta) {
                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_failed_logins");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.getBlockedUsers = function(meta) {
                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_cphulk_user_brutes");
                if (meta) {
                    if (meta.filterBy && meta.filterValue !== null && meta.filterValue !== void 0) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber !== null && meta.pageNumber !== void 0) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };


            exports.clearHistory = function() {

                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "flush_cphulk_login_history");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            results.data = convertResponseData(results.data);
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            exports.unBlockAddress = function(address) {

                var deferred = $q.defer(),
                    apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "flush_cphulk_login_history_for_ips");
                apiCall.addArgument("ip", address);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response;
                            deferred.resolve(results.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };


            return exports;
        }]);
    }
);

/*
# templates/hulkd/views/historyController.js      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/historyController',[
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

/*
# templates/hulkd/views/hulkdEnableController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                      http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/views/hulkdEnableController',[
        "angular",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/growlDecorator",
        "app/services/HulkdDataSource"
    ],
    function(angular, $, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "hulkdEnableController",
            ["$scope", "HulkdDataSource", "growl", "growlMessages", "PAGE",
                function($scope, HulkdDataSource, growl, growlMessages, PAGE) {
                    $scope.hulkdEnabled = PARSE.parsePerlBoolean(PAGE.hulkd_status.is_enabled);

                    $scope.knobLabel = "\u00a0";

                    $scope.changing_status = false;
                    $scope.status_check_in_progress = false;

                    $scope.handle_keydown = function(event) {

                    // prevent the spacebar from scrolling the window
                        if (event.keyCode === 32) {
                            event.preventDefault();
                        }
                    };

                    $scope.handle_keyup = function(event) {

                    // bind to the spacebar and enter keys
                        if (event.keyCode === 32 || event.keyCode === 13) {
                            event.preventDefault();
                            $scope.toggle_status();
                        }
                    };

                    $scope.toggle_status = function() {
                        if ($scope.changing_status) {
                            return;
                        }

                        $scope.changing_status = true;

                        if ($scope.hulkdEnabled) {
                            growlMessages.destroyAllMessages();
                            HulkdDataSource.disable_hulkd()
                                .then( function() {
                                    $scope.hulkdEnabled = false;
                                    growl.success(LOCALE.maketext("[asis,cPHulk] is now disabled."));
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    $scope.changing_status = false;
                                });
                        } else {
                            HulkdDataSource.enable_hulkd()
                                .then( function(response) {
                                    $scope.hulkdEnabled = true;
                                    growl.success(LOCALE.maketext("[asis,cPHulk] is now enabled."));
                                    if (response.data && response.data.restart_ssh) {
                                        growl.warning(LOCALE.maketext("The system disabled the [asis,UseDNS] setting for [asis,SSHD] in order to add IP addresses to the whitelist. You must restart SSH through the [output,url,_1,Restart SSH Server,_2] page to implement the change.", PAGE.security_token + "/scripts/ressshd", { "target": "_blank" }));
                                    } else if (response.data && response.data.warning) {
                                        growl.warning(response.data.warning);
                                    }
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    $scope.changing_status = false;
                                });
                        }

                    };

                    $scope.get_status = function() {
                        if ($scope.status_check_in_progress) {
                            return;
                        }
                        $scope.status_check_in_progress = true;
                        return HulkdDataSource.hulkd_status()
                            .then( function(results) {
                                if (results !== $scope.hulkdEnabled) {

                                // this test needs to run only if status has changed
                                    if (results === false) {
                                        growlMessages.destroyAllMessages();
                                    }
                                    growl.warning(LOCALE.maketext("The status for [asis,cPHulk] has changed, possibly in another browser session."));
                                }
                                $scope.hulkdEnabled = results;
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.status_check_in_progress = false;
                            });
                    };

                    $scope.init = function() {
                        $(document).ready(function() {

                        // for window and tab changes
                            $(window).on("focus", function() {
                                $scope.get_status();
                            });
                        });
                    };

                    $scope.init();
                }
            ]);

        return controller;
    }
);

/*
# cpanel - whostmgr/docroot/templates/hulkd/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* eslint-disable camelcase */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",
        "ngAnimate",
    ],
    function(angular, $, _, LOCALE, CJT) {
        "use strict";
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "ngSanitize",
                "ngAnimate",
                "angular-growl",
                "cjt2.whm",
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/configController",
                    "app/views/countriesController",
                    "app/views/hulkdWhitelistController",
                    "app/views/hulkdBlacklistController",
                    "app/views/historyController",
                    "app/views/hulkdEnableController",
                    "app/services/HulkdDataSource",
                    "angular-growl",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);
                    app.value("COUNTRY_CONSTANTS", {
                        WHITELISTED: "whitelisted",
                        BLACKLISTED: "blacklisted",
                        UNLISTED: "unlisted",
                    });

                    // used to indicate that we are prefetching the following items
                    app.firstLoad = {
                        configs: true,
                    };

                    app.controller("BaseController", ["$rootScope", "$scope",
                        function($rootScope, $scope) {

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
                        },
                    ]);

                    app.config(["$routeProvider", "$animateProvider",
                        function($routeProvider, $animateProvider) {

                            $animateProvider.classNameFilter(/^((?!no-animate).)*$/);

                            // Setup the routes
                            $routeProvider.when("/config", {
                                controller: "configController",
                                templateUrl: CJT.buildFullPath("hulkd/views/configView.ptt"),
                            });

                            $routeProvider.when("/whitelist", {
                                controller: "hulkdWhitelistController",
                                templateUrl: CJT.buildFullPath("hulkd/views/hulkdWhitelistView.ptt"),
                            });

                            $routeProvider.when("/blacklist", {
                                controller: "hulkdBlacklistController",
                                templateUrl: CJT.buildFullPath("hulkd/views/hulkdBlacklistView.ptt"),
                            });

                            $routeProvider.when("/history", {
                                controller: "historyController",
                                templateUrl: CJT.buildFullPath("hulkd/views/historyView.ptt"),
                            });

                            $routeProvider.when("/countries", {
                                controller: "countriesController",
                                templateUrl: CJT.buildFullPath("hulkd/views/countriesView.ptt"),
                                resolve: {
                                    "COUNTRY_CODES": ["HulkdDataSource", function($service) {
                                        return $service.get_countries_with_known_ip_ranges();
                                    }],
                                    "XLISTED_COUNTRIES": ["HulkdDataSource", function($service) {
                                        return $service.load_xlisted_countries();
                                    }],
                                },
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/config",
                            });
                        },
                    ]);

                    app.run(["$rootScope", "$timeout", "$location", "HulkdDataSource", "growl", "growlMessages", function($rootScope, $timeout, $location, HulkdDataSource, growl, growlMessages) {

                        // register listener to watch route changes
                        $rootScope.$on( "$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                        });

                        $rootScope.whitelist_warning_message = null;
                        $rootScope.ip_added_with_one_click = false;

                        $rootScope.one_click_add_to_whitelist = function(missing_ip) {
                            return HulkdDataSource.add_to_whitelist([{ ip: missing_ip } ])
                                .then(function(results) {
                                    growl.success(LOCALE.maketext("You have successfully added “[_1]” to the whitelist.", results.added[0]));

                                    // check if the client ip is in the whitelist and if our growl is still shown, remove it
                                    if ((Object.prototype.hasOwnProperty.call(results, "requester_ip") &&
                                         results.added.indexOf(results.requester_ip) > -1) &&
                                         ($rootScope.whitelist_warning_message !== null)) {

                                        // remove is handled in this manner because it was not removing the growl in the right sequence
                                        // when shown with other growls
                                        $rootScope.whitelist_warning_message.ttl = 0;
                                        $rootScope.whitelist_warning_message.promises = [];
                                        $rootScope.whitelist_warning_message.promises.push($timeout(angular.bind(growlMessages, function() {
                                            growlMessages.deleteMessage($rootScope.whitelist_warning_message);
                                            $rootScope.whitelist_warning_message = null;
                                        }), 200));
                                        $rootScope.ip_added_with_one_click = true;
                                    }
                                }, function(error_details) {
                                    var combined_message = error_details.main_message;
                                    var secondary_count = error_details.secondary_messages.length;
                                    for (var z = 0; z < secondary_count; z++) {
                                        if (z === 0) {
                                            combined_message += "<br>";
                                        }
                                        combined_message += "<br>";
                                        combined_message += error_details.secondary_messages[z];
                                    }
                                    growl.error(combined_message);
                                });
                        };
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

