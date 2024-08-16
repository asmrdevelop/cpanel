/* global define: false */

define(
    'app/services/configService',[

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/util/parse",
        "cjt/util/locale",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
        "cjt/services/APIService"
    ],
    function(angular, API, PARSE, LOCALE, APIREQUEST, APIDRIVER) {

        "use strict";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        /**
         * Set up the account list model's API service.
         */
        app.factory("configService", ["$q", "APIService", function($q, APIService) {


            /**
             * @typedef PoolOption
             * @property {Number}          trinary_admin_value 0 = admin option does not exist for pool value, 1 = this is php_admin_value, 2 = php_value
             * @property {String}          base_flag_name      name of option being set
             * @property {String | Number} value               value of option being set
             */

            var MultiPHPConfigService = function() {};
            MultiPHPConfigService.prototype = new APIService();

            /**
             * Parse raw data into format usuable to front end
             * @method parsePHPFPMData
             * @param  {Array<PoolOption>}     data       raw data from backend
             * @return {Array<PoolOption>}     parsedData parsed data for use by front end
             */
            function parsePHPFPMData(data, domain) {
                var parsedData = {};

                function parseValue(option) {
                    if (option.value === "on") {
                        return true;
                    }

                    if (option.value === "off") {
                        return false;
                    }

                    if (option.base_flag_name === "pm_max_children" ||
                        option.base_flag_name === "pm_process_idle_timeout" ||
                        option.base_flag_name === "pm_max_requests") {

                        if (!isNaN(parseInt(option.value, 10))) {
                            return parseInt(option.value, 10);
                        }
                    }

                    if (option.base_flag_name === "error_reporting" || option.base_flag_name === "disable_functions") {
                        if (typeof option.value !== "string" || option.value.length === 0) {
                            option.value = [];
                        } else {
                            option.value = option.value.split(",");
                        }

                        return option.value;
                    }

                    if (option.base_flag_name === "doc_root") {
                        if (typeof option.value !== "string" || !domain) {
                            option.value = "";
                        } else {
                            option.value = option.value.split("[% documentroot %]")[1];
                            if (option.value.indexOf("/") === 0) {
                                option.value = option.value.slice(1, option.value.length);
                            }
                        }
                        return option.value;
                    }

                    if (option.base_flag_name === "error_log") {
                        if (typeof option.value !== "string" || !domain) {
                            option.value = "";
                        } else {
                            option.value = option.value.split("/logs/")[1];
                        }
                        return option.value;
                    }
                }

                data.forEach(function(option) {
                    parsedData[option.base_flag_name] = {
                        value: parseValue(option),
                        admin: option.trinary_admin_value === 1 ? true : option.trinary_admin_value === 2 ? false : 0
                    };
                });
                return parsedData;
            }

            /**
             * Encode options for API call
             * @method encodePoolOptions
             * @param  {Array<PoolOption>}   poolOptions        data in format for front end
             * @return {Array<PoolOption>}   encodedPoolOptions data encoded for use by API
             */
            function encodePoolOptions(poolOptions) {
                var encodedPoolOptions = [];
                var encodedOption = {};

                function encodeValue(option, val) {
                    if (option === "allow_url_fopen" || option === "log_errors" || option === "short_open_tag") {
                        if (val) {
                            val = "on";
                        } else {
                            val = "off";
                        }
                        return val;
                    }

                    if (option === "disable_functions" || option === "error_reporting") {
                        if (val.length === 0) {

                            // API only accepts empty string for no funs or errs
                            val = "";
                        } else {
                            val = val.join(",");
                        }
                        return val;
                    }

                    if (option === "pm_max_children" ||
                        option === "pm_max_requests" ||
                        option === "pm_process_idle_timeout") {
                        return val;
                    }

                    if (option === "error_log") {
                        if (val === "") {
                            val = "[% homedir %]/logs/[% scrubbed_domain %].php.error.log";
                        } else {
                            val = "[% homedir %]/logs/" + val;
                        }
                        return val;
                    }

                    if (option === "doc_root") {
                        if (val.indexOf("/") !== 0) {
                            val = "[% documentroot %]/" + val;
                        } else {
                            val = "[% documentroot %]"  + val;
                        }
                        return val;
                    }
                }

                for (var option in poolOptions) {
                    if (option) {
                        encodedOption["trinary_admin_value"] = poolOptions[option].admin ? 1 : poolOptions[option].admin === 0 ? poolOptions[option].admin : 2;
                        encodedOption["base_flag_name"] = option;
                        encodedOption["value"] = encodeValue(option, poolOptions[option].value);
                    }

                    encodedPoolOptions.push(encodedOption);
                    encodedOption = {};
                }
                return encodedPoolOptions;
            }

            angular.extend(MultiPHPConfigService.prototype, {

                /**
                 * Converts the response to our application data structure
                 * @param   {Object} response - Response from API call.
                 * @returns {Object} Sanitized data structure.
                 */
                convertResponseToList: function(response) {
                    var items = [];
                    if (response.status) {
                        var data = response.data;
                        for (var i = 0, length = data.length; i < length; i++) {
                            var list = data[i];
                            if (list.hasOwnProperty("php_fpm")) {
                                list.php_fpm = PARSE.parsePerlBoolean(list.php_fpm);
                            }
                            if (list.hasOwnProperty("is_suspended")) {
                                list.is_suspended = PARSE.parsePerlBoolean(list.is_suspended);
                            }
                            if (list.hasOwnProperty("main_domain")) {
                                list.main_domain = PARSE.parsePerlBoolean(list.main_domain);
                            }
                            if (list.hasOwnProperty("version")) {
                                list.display_php_version = this.transformPhpFormat(list.version);
                            }

                            items.push(
                                list
                            );
                        }

                        var meta = response.meta;

                        var totalItems = meta.paginate.total_records || data.length;
                        var totalPages = meta.paginate.total_pages || 1;

                        return {
                            items: items,
                            totalItems: totalItems,
                            totalPages: totalPages
                        };
                    } else {
                        return {
                            items: [],
                            totalItems: 0,
                            totalPages: 0
                        };
                    }
                },

                /**
                 * Retrieves a list of installed FPM packages.
                 * @returns {Promise} - Promise encapsulating the package list.
                 */
                checkFPMPackages: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "package_manager_list_packages");
                    apiCall.addArgument("state", "installed");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response.data;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Set a given PHP version at the system level.
                 * @param {string} setData - PHP version to set.
                 * @returns {Promise} - Promise that will fulfill the request.
                 */
                applySystemSetting: function(setData) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_set_system_default_version");
                    apiCall.addArgument("version", setData);
                    var that = this;
                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return that.convertResponseToList(response);
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Gets the current system-level PHP version.
                 * @returns {Promise} - Promise that will fulfill the request.
                 */
                fetchSystemPhp: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_get_system_default_version");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response.data;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Set a given PHP version to the given list of vhosts.
                 * @param {string} version - PHP version to apply to the provided vhost list.
                 * @param {Object[]} vhostList - List of vhosts to which the new PHP needs to be applied.
                 * @returns {Promise} - Promise that will fulfill the request.
                 */
                applyDomainSetting: function(version, vhostList) {
                    var apiCall = new APIREQUEST.Class();
                    var that = this;
                    apiCall.initialize("", "php_set_vhost_versions");
                    apiCall.addArgument("version", version);

                    if (typeof (vhostList) !== "undefined" && vhostList.length > 0) {
                        vhostList.forEach(function(vhost, index) {
                            apiCall.addArgument("vhost-" + index, vhost);
                        });
                    }

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            var results = that.convertResponseToList(response);
                            return results;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Set PHP FPM to the given list of vhosts.
                 * @param {number} fpm - PHP FPM, either On(1) or Off(0).
                 * @param {Object[]} vhostList - List of vhosts.
                 * @returns {Promise} - Promise that will fulfill the request.
                 */
                applyDomainFpm: function(fpm, vhostList) {
                    var apiCall = new APIREQUEST.Class();
                    var that = this;
                    apiCall.initialize("", "php_set_vhost_versions");
                    apiCall.addArgument("php_fpm", fpm);

                    if (typeof (vhostList) !== "undefined" && vhostList.length > 0) {
                        vhostList.forEach(function(vhost, index) {
                            apiCall.addArgument("vhost-" + index, vhost);
                        });
                    }

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            var results = that.convertResponseToList(response);
                            return results;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Set Pool Options for the given vhost
                 * @param {Object} account - The account whose options need to be saved.
                 * @returns {Promise} - Promise that will fulfill the request.
                 */
                savePoolOption: function(account) {
                    var apiCall = new APIREQUEST.Class();
                    var that = this;
                    apiCall.initialize("", "php_set_vhost_versions");
                    apiCall.addArgument("php_fpm", 1);
                    apiCall.addArgument("vhost-0", account.vhost);
                    apiCall.addArgument("php_fpm_pool_parms", JSON.stringify(account.php_fpm_pool_parms));

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            var results = that.convertResponseToList(response);
                            return results;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Get a list of accounts along with their default PHP versions for the given search/filter/page criteria.
                 * @param {object} meta - Optional meta data to control sorting, filtering and paging
                 *   @param {string} meta.sortBy - Name of the field to sort by
                 *   @param {string} meta.sortDirection - asc or desc
                 *   @param {string} meta.sortType - Optional name of the sort rule to apply to the sorting
                 *   @param {string} meta.filterBy - Name of the field to filter by
                 *   @param {string} meta.filterValue - Expression/argument to pass to the compare method.
                 *   @param {string} meta.pageNumber - Page number to fetch.
                 *   @param {string} meta.pageSize - Size of a page, will default to 10 if not provided.
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                fetchList: function(meta) {
                    var apiCall = new APIREQUEST.Class();
                    var that = this;
                    apiCall.initialize("", "php_get_vhost_versions");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            var results = that.convertResponseToList(response);
                            return results;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Get a list of PHP versions and their associated PHP handlers.
                 * @returns {Promise} - Promise that will fulfill the request.
                 */
                fetchVersionHandlerList: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_get_handlers");
                    var that = this;

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return that.convertResponseToList(response);
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Get a list of PHP versions.
                 * @returns {Promise} - Promise that will fulfill the request.
                 */
                fetchPHPVersions: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_get_installed_versions");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response.data;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Get the domains that are impacted by the given domain's
                 * PHP settings and/or the system’s default PHP setting
                 * @param {string} type - "domain" or "system_default"
                 * @param {string|number} value - The domain name or 1 for system default.
                 * @returns {Promise} - Promise encapsulating a list of domains.
                 */
                fetchImpactedDomains: function(type, value) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_get_impacted_domains");
                    apiCall.addArgument(type, value);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Applies the provided handler to the provided version
                 * @param  {string} version
                 * @param  {string} handler
                 * @returns {Promise} - Promise encapsulating a list of domains.
                 */
                applyVersionHandler: function(version, handler) {
                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_set_handler");
                    apiCall.addArgument("version", version);
                    apiCall.addArgument("handler", handler);

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response.status;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                * Checks to see if a FPM conversion job is currently running
                * @returns {Promise} Result of API call.
                */
                conversionInProgress: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "is_conversion_in_progress");

                    return this.deferred(apiCall).promise
                        .then(function(result) {
                            return PARSE.parsePerlBoolean(result.data.inProgress);
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Convert all accounts to use PHP-FPM.
                 * @returns {Promise} Result of API call. Indicates whether
                 * the batch process has started.
                 */
                convertAllAccountsToFPM: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "convert_all_domains_to_fpm");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response.data;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Get the current status of PHP-FPM on the system.
                 * @return {Promise} Result of API call.
                 */
                fetchFPMStatus: function() {
                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_get_default_accounts_to_fpm");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response.data;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Get the server PHP FPM environment information.
                 * @param  {string} version
                 * @param  {string} handler
                 * @returns {Promise} Result of API call.
                 */
                checkFPMEnvironment: function(version, handler) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "get_fpm_count_and_utilization");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response.data;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Get all PHP FPM information at once.
                 * @param  {string} version
                 * @param  {string} handler
                 * @returns {Promise} Promise encapsulating object with all results
                 */

                getPHPFPMInfo: function(version, handler) {
                    var promises = {
                        environment: this.checkFPMEnvironment(version, handler),
                        status: this.fetchFPMStatus(),
                        packages: this.checkFPMPackages()
                    };

                    return $q.all(promises);
                },

                /**
                 * Switch the current status of PHP-FPM on the system.
                 * @param {number} newStatus - 0 (off) or 1 (on).
                 * @returns {Promise} Promise encapsulating object with all results
                 */
                switchSystemFPM: function(newStatus) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_set_default_accounts_to_fpm");
                    apiCall.addArgument("default_accounts_to_fpm", newStatus);

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return true;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Convert the rpm format of PHP version (eg: ea-php56)
                 * to a user friendly notation (eg: PHP 5.6)
                 * @param  {String}
                 * @return {String}
                 */
                friendlyPhpFormat: function(str) {
                    var newStr = str || "";
                    var phpVersionRegex = /^\D+-(php)(\d{2,3})$/i;
                    if (phpVersionRegex.test(str)) {
                        var stringArr = str.match(phpVersionRegex);

                        // adds a period before the last digit
                        var formattedNumber = stringArr[2].replace(/(\d)$/, ".$1");

                        newStr = "PHP " + formattedNumber;
                    }
                    return newStr;
                },


                /**
                 * Friendly PHP format with the rpm package
                 * name included.
                 * Example: PHP 5.6 (ea-php56)
                 * @param  {String}
                 * @return {String}
                 */
                transformPhpFormat: function(str) {
                    var newStr = str || "";
                    var phpVersionRegex = /^\D+-(php)(\d{2,3})$/i;
                    if (phpVersionRegex.test(str)) {
                        newStr = this.friendlyPhpFormat(str);
                        newStr = newStr + " (" + str + ")";
                    }
                    return newStr;
                },

                /**
                 * Parse the values coming back from API.
                 * @param {Object} clData - The CloudLinux purchase data needed to build the banner.
                 * @returns {Object} - Return parsed data.
                 */
                parseCloudLinuxData: function(data) {
                    data.cl_is_installed = PARSE.parsePerlBoolean(data.cl_is_installed);
                    data.cl_is_supported = PARSE.parsePerlBoolean(data.cl_is_supported);

                    data.purchase_cl_data.disable_upgrade = PARSE.parsePerlBoolean(data.purchase_cl_data.disable_upgrade);
                    data.purchase_cl_data.is_url = PARSE.parsePerlBoolean(data.purchase_cl_data.is_url);
                    data.purchase_cl_data.server_timeout = PARSE.parsePerlBoolean(data.purchase_cl_data.server_timeout);
                    return data;
                },

                /**
                 * Set CloudLinux information that is needed for a banner.
                 * @param {Object} clData - The CloudLinux purchase data needed to build the banner.
                 * @returns {Object} - data needed by the banner.
                 */
                setCloudLinuxInfo: function(clData) {
                    var returnData = {};
                    if (clData) {
                        var cloudLinuxData = this.parseCloudLinuxData(clData);
                        var purchaseData = cloudLinuxData.purchase_cl_data;

                        if (cloudLinuxData.cl_is_supported && !cloudLinuxData.cl_is_installed && !purchaseData.disable_upgrade) {
                            returnData.showBanner = true;

                            if (!purchaseData.server_timeout) {

                                if (purchaseData.is_url) {
                                    returnData.purchaseLink = purchaseData.url;
                                    returnData.actionText = LOCALE.maketext("Upgrade to [asis,CloudLinux]");
                                    returnData.linkTarget = purchaseData.target || "_blank";
                                } else {

                                    // Create an email link to send to user
                                    var mailSubject = "Upgrade to Cloud Linux"; // Do not localize the stuff that will get emailed to the CL folks
                                    var mailBody = "I am interested in more information on how I can benefit from CloudLinux on my cPanel server."; // Do not localize the stuff that will get emailed to the CL folks
                                    var mailtoText = "mailto:" + encodeURIComponent(purchaseData.email || "") + "?subject=" + encodeURIComponent(mailSubject) + "&body=" + encodeURIComponent(mailBody);
                                    returnData.purchaseLink = mailtoText;
                                    returnData.linkTarget = "_top";
                                    returnData.actionText = LOCALE.maketext("Email Provider");
                                }
                            }
                        }
                        returnData.data = cloudLinuxData;
                    }
                    return returnData;
                },

                /**
                 * Fetch system default or domain specific php-fpm settings
                 * @method getPHPFPMSettings
                 * @param  {String}          [domain] Empty parameter for system settings, domain string if domain specific settings
                 * @return {Promise<Object>}          Object of php-fpm keys with their respective values
                 * @throws {Promise<String>}          Error message on failure
                 */
                getPHPFPMSettings: function(domain) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_fpm_config_get");
                    apiCall.json = true;
                    apiCall.addArgument("domain", domain ? domain : "");

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return parsePHPFPMData(response.data.config, domain);
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * Submit config pool options for validation or saving
                 * @method submitPoolOptions
                 * @param  {Object}   poolOptions Aray of object describing each pool option and its value
                 * @param  {Boolean}             validate    A boolean, if true will validate options, if false will save options
                 * @param  {String}              [domain]    If given the options are saved or validated for given domain, if left empty values are saved/validated as system defaults
                 * @return {Promise<Boolean>}                If true, values saved or validated successfully
                 * @throws {Promise<String>}                 Error message on failue
                 */
                submitPoolOptions: function(poolOptions, validate, domain) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "php_fpm_config_set");
                    apiCall.json = true;
                    apiCall.addArgument("validate_only", validate);
                    apiCall.addArgument("domain", domain ? domain : "");
                    apiCall.addArgument("config", encodePoolOptions(poolOptions));

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return true;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                },

                /**
                 * @method getEA4Recommendations
                 * @return {Promise}
                 */
                getEA4Recommendations: function() {
                    var apiCall = new APIREQUEST.Class();
                    var apiService = new APIService();
                    apiCall.initialize("", "ea4_recommendations");

                    var deferred = apiService.deferred(apiCall);
                    return deferred.promise;
                }
            });

            return new MultiPHPConfigService();
        }
        ]);
    });

/*
 * templates/multiphp_manager/views/impactedDomainsPopup.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/views/impactedDomainsPopup',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "impactedDomainsPopup",
            ["$scope", "$uibModalInstance", "data",
                function($scope, $uibModalInstance, data) {
                    $scope.modalData = {};
                    var vhostInfo = data;
                    $scope.modalData = vhostInfo;

                    $scope.closeModal = function() {
                        $uibModalInstance.close();
                    };
                }
            ]);
        return controller;
    }
);

/*
 * templates/multiphp_manager/views/poolOptions.js
 *                                                 Copyright 2022 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
/* eslint no-use-before-define: 0*/

define(
    'app/views/poolOptions',[
        "angular",
        "lodash",
        "cjt/util/parse",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/configService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/toggleLabelInfoDirective",
        "cjt/directives/loadingPanel",
        "cjt/directives/actionButtonDirective",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/validator/path-validators",
    ],
    function(angular, _, PARSE, LOCALE) {
        "use strict";

        var app = angular.module("App");

        var controller = app.controller(
            "poolOptionsController",
            ["$q", "$scope", "$anchorScroll", "$rootScope", "alertService", "configService",
                function($q, $scope, $anchorScroll, $rootScope, alertService, configService) {

                    $scope.displayValue = {
                        selectedDomain: "",
                        docRootDisplayValue: "",
                        logDirDisplayValue: "",
                        reportedErrs: "",
                        disabledFuncs: "",
                        displayMode: null,
                        disabledFuncsPanelOpen: false,
                        errsReportedPanelOpen: false,
                        saveReminderDisplayed: false,
                        saveReminderMessage: LOCALE.maketext("Click [output,em,Save Configuration] to save your changes."),
                    };

                    $scope.poolOptions = {};
                    $scope.poolOptionsCache = {};

                    $scope.additionalResources = [
                        {
                            text: "cPanel Documentation",
                            link: "https://docs.cpanel.net/",
                        },
                        {
                            text: LOCALE.maketext("Official [asis,PHP] Configuration Documentation"),
                            link: "https://secure.php.net/manual/en/install.fpm.configuration.php",
                        },
                        {
                            text: "Bottleneck with Child Processes",
                            link: "https://go.cpanel.net/ApachevsPHP-FPMBottleneckwithChildProcesses",
                        },
                    ];

                    /**
                 * Return default button classes to work with cp-action directive
                 *
                 * @scope
                 * @method getDefaultButtonClasses
                 */
                    $scope.getDefaultButtonClasses = function() {
                        return "btn btn-default";
                    };

                    /**
                 * Return small default button classes to work with cp-action directive
                 * @method getSmallDefaultButtonClasses
                 */
                    $scope.getSmallDefaultButtonClasses = function() {
                        return "btn btn-sm btn-default";
                    };

                    /**
                 * Return default button classes to work with cp-action directive
                 *
                 * @scope
                 * @method getButtonClasses
                 * @return {String}         Default button classes
                 */
                    $scope.getButtonClasses = function() {
                        return "btn btn-default";
                    };

                    /**
                 * Return primary button classes to work with cp-action directive
                 *
                 * @scope
                 * @method getPrimaryButtonsClasses
                 * @return {String}           Promary button classes
                 */
                    $scope.getPrimaryButtonsClasses = function() {
                        return "btn btn-sm btn-primary";
                    };

                    /**
                 * Add functions to the disable_functions value list
                 *
                 * @scope
                 * @method addFunctionsToDisable
                 * @param  {Array.<String>}      funcs   array of functions to validate for disabling
                 * @param  {Object}              formVal object representing php-fpm form
                 * @return {Promise.<Array.<String>> | } if the promise exists it returns an array of strings of validated funcs, if the promise does not exist, the function returns nothing
                 */
                    $scope.addFunctionsToDisable = function(funcs, formVal) {
                        var funcsPromises = formatAndValidateFunctions(funcs, formVal);
                        if (!funcsPromises) {
                            return;
                        }
                        $scope.actions.validatingFuncs = true;
                        return funcsPromises.then(function(validatedFuncs) {
                            alertService.add({
                                type: "success",
                                autoClose: 5000,
                                message: LOCALE.maketext("You successfully added the “[_1]” function to the list. Click [output,em,Save Configuration] to save your changes.", _.escape(validatedFuncs)),
                            });
                            $scope.actions.validatingFuncs = false;
                        });
                    };

                    /**
                 * Remove functions from disable_functions value list
                 *
                 * @scope
                 * @method removeDisabledFunction
                 * @param  {String}               func    function to remove from disable_functions value list
                 * @param  {Object}               formVal object representing php-fpm form
                 */
                    $scope.removeDisabledFunction = function(func, formVal) {
                        var commands = $scope.poolOptions.disable_functions.value;
                        for (var i = 0, len = $scope.poolOptions.disable_functions.value.length; i < len; i++) {
                            if (func === commands[i]) {
                                $scope.poolOptions.disable_functions.value.splice(i, 1);
                                formVal.$setDirty();
                                return;
                            }
                        }
                    };

                    /**
                 * Add errors to error_reporting value list
                 *
                 * @scope
                 * @method addErrsToReport
                 * @param  {Array.<String>}           errs    array of errors to validate before adding to error_reporting value list
                 * @param  {Object}                   formVal object representing php-fpm form
                 * @return {Promise.<Array.<String>>}         if the promise exists it returns and array of strings of validated errors, if it does not exist the function return nothing
                 */
                    $scope.addErrsToReport = function(errs, formVal) {
                        var errsPromises = formatAndValidateErrs(errs, formVal);
                        if (!errsPromises) {
                            return;
                        }
                        $scope.actions.validatingErrs = true;
                        return errsPromises.then(function(validatedErrs) {
                            alertService.add({
                                type: "success",
                                autoClose: 5000,
                                message: LOCALE.maketext("You successfully added the “[_1]” error to the list. Click [output,em,Save Configuration] to save your changes.", _.escape(validatedErrs)),
                            });
                            $scope.actions.validatingErrs = false;
                        });
                    };

                    /**
                 * Remove errors from error_reporting value list
                 *
                 * @scope
                 * @method removeReportedErrs
                 * @param  {String}           err     error to remove from error_reporting value list
                 * @param  {Object}           formVal object representing php-fpm form
                 */
                    $scope.removeReportedErrs = function(err, formVal) {
                        var errs = $scope.poolOptions.error_reporting.value;
                        for (var i = 0, len = $scope.poolOptions.error_reporting.value.length; i < len; i++) {
                            if (err === errs[i]) {
                                $scope.poolOptions.error_reporting.value.splice(i, 1);
                                formVal.$setDirty();
                                return;
                            }
                        }
                    };

                    /**
                 * Emit event to return to PHP Version domain list view
                 *
                 * @scope
                 * @method returnToDomainsList
                 */
                    $scope.returnToDomainsList = function() {
                        $rootScope.$emit("returnToDomainList");
                    };

                    /**
                 * Toggle betwee php_value and php_admin_value for given options
                 *
                 * @scope
                 * @method toggleOverrideVal
                 * @param  {String}          overrideVal which pool option is being toggled
                 * @param  {Object}          formVal     object representing php-fpm form
                 * @throws {String}                      error informing developer of invalid value
                 */
                    $scope.toggleOverrideVal = function(overrideVal, formVal) {
                        formVal.$setDirty();

                        if (!$scope.displayValue.saveReminderDisplayed) {
                            alertService.add({
                                type: "info",
                                closeable: true,
                                autoClose: 5000,
                                message: $scope.displayValue.saveReminderMessage,
                            });
                            $scope.displayValue.saveReminderDisplayed = true;
                        }

                        switch (overrideVal) {
                            case "allow_url_fopen":
                                $scope.poolOptions.allow_url_fopen.admin = !$scope.poolOptions.allow_url_fopen.admin;
                                break;
                            case "log_errors":
                                $scope.poolOptions.log_errors.admin = !$scope.poolOptions.log_errors.admin;
                                break;
                            case "short_open_tag":
                                $scope.poolOptions.short_open_tag.admin = !$scope.poolOptions.short_open_tag.admin;
                                break;
                            case "doc_root":
                                $scope.poolOptions.doc_root.admin = !$scope.poolOptions.doc_root.admin;
                                break;
                            case "error_log":
                                $scope.poolOptions.error_log.admin = !$scope.poolOptions.error_log.admin;
                                break;
                            case "disable_functions":
                                $scope.poolOptions.disable_functions.admin = !$scope.poolOptions.disable_functions.admin;
                                break;
                            case "error_reporting":
                                $scope.poolOptions.error_reporting.admin = !$scope.poolOptions.error_reporting.admin;
                                break;
                            default:
                                throw new Error("DEVELOPER ERROR: invalid override value given");
                        }
                    };

                    /**
                 * Save new pool options
                 *
                 * @scope
                 * @method savePoolOptions
                 * @param  {Object}        formVal object representing php-fpm form
                 */
                    $scope.savePoolOptions = function(formVal) {
                        return submitPoolOptions($scope.poolOptions, false, $scope.displayValue.selectedDomain, formVal);
                    };

                    /**
                 * Validate new pool options
                 *
                 * @scope
                 * @method validatePoolOptions
                 */
                    $scope.validatePoolOptions = function() {
                        return submitPoolOptions($scope.poolOptions, true, $scope.displayValue.selectedDomain);
                    };

                    /**
                 * Set the form to pristine
                 *
                 * @scope
                 * @method deactivateSaveActions
                 * @param  {Object}              formVal object representing php-fpm form
                 */
                    $scope.deactivateSaveActions = function(formVal) {
                        formVal.$setPristine();
                    };

                    /**
                 * Reset form to initial state
                 *
                 * @scope
                 * @method resetPoolOptionsForm
                 * @param  {Object}             formVal object representing php-fpm form
                 */
                    $scope.resetPoolOptionsForm = function(formVal) {
                        $scope.poolOptions = $scope.poolOptionsCache;
                        $scope.poolOptionsCache = angular.copy($scope.poolOptions);
                        formVal.$setPristine();
                    };

                    /**
                 * Check for duplicate entries in entered list, and existing list. Format each function for validation submission
                 *
                 * @method formatAndValidateFunctions
                 * @param  {Array.<String>}           funcs   functions to format and validate
                 * @param  {Object}                   formVal object representing php-fpm form
                 * @return {Array.<Promise>}                  if functions is a duplicate, return nothing, if it isn't return array of promises from validated functions
                 */
                    function formatAndValidateFunctions(funcs, formVal) {
                        funcs = funcs.split(",");
                        funcs = formatListVals(funcs);
                        var optionForValidation;
                        var validationPromises = [];
                        var validationPromise;

                        for (var i = 0, len = funcs.length; i < len; i++) {

                            // checks for duplicates within the array entered and returns out of if()
                            // unless it is the last index of that function
                            if (funcs.indexOf(funcs[i]) !== -1 && funcs.indexOf(funcs[i], i + 1) !== -1) {
                                return;
                            }

                            // checks for duplicates in already existing function list
                            if ($scope.poolOptions.disable_functions.value.indexOf(funcs[i]) !== -1) {
                                var duplicateMessage = LOCALE.maketext("The “[_1]” function already appears on the disabled functions list.", _.escape(funcs[i]));
                                alertService.add({
                                    type: "warning",
                                    autoClose: 5000,
                                    closeable: true,
                                    message: duplicateMessage,
                                });
                                if (len === 1) {
                                    return;
                                } else {
                                    continue;
                                }
                            }

                            optionForValidation = {
                                disable_functions: {
                                    value: [],
                                    admin: $scope.poolOptions.disable_functions.admin,
                                },
                            };
                            optionForValidation.disable_functions.value.push(funcs[i]);
                            validationPromise = validateInlineOption(optionForValidation, true, $scope.displayValue.selectedDomain, formVal);
                            validationPromises.push(validationPromise);
                        }
                        return $q.all(validationPromises);
                    }

                    /**
                 * Check for duplicate entries in entered error list, and existing error list. Format each error for validation submission
                 *
                 * @method formatAndValidateErrs
                 * @param  {Array.<String>}        errs    errors to format and validate
                 * @param  {Object}                formVal object representing php-fpm form
                 * @return {Array.<Promise>}                      if error is a duplicate, return nothing, if it isn't return array of promises from validated errors
                 */
                    function formatAndValidateErrs(errs, formVal) {
                        errs = errs.split(",");
                        errs = formatListVals(errs);
                        var optionForValidation;
                        var validationPromises = [];
                        var validationPromise;

                        for (var i = 0, len = errs.length; i < len; i++) {

                            // checks for duplicates within the array entered and returns out of if()
                            // unless it is the last index of that function
                            if (errs.indexOf(errs[i]) !== -1 && errs.indexOf(errs[i], i + 1) !== -1) {
                                return;
                            }

                            // checks for duplicates in already existing function list
                            if ($scope.poolOptions.error_reporting.value.indexOf(errs[i]) !== -1) {
                                var duplicateMessage = LOCALE.maketext("The “[_1]” error already appears on the errors list.", _.escape(errs[i]));
                                alertService.add({
                                    type: "warning",
                                    autoClose: 5000,
                                    closeable: true,
                                    message: duplicateMessage,
                                });
                                if (len === 1) {
                                    return;
                                } else {
                                    continue;
                                }
                            }

                            optionForValidation = {
                                error_reporting: {
                                    value: [],
                                    admin: $scope.poolOptions.error_reporting.admin,
                                },
                            };
                            optionForValidation.error_reporting.value.push(errs[i]);
                            validationPromise = validateInlineOption(optionForValidation, true, $scope.displayValue.selectedDomain, formVal);
                            validationPromises.push(validationPromise);
                        }
                        return $q.all(validationPromises);
                    }

                    /**
                 * Remove leading and trailing spaces from each value
                 *
                 * @method formatListVals
                 * @param  {Array.<String>}       vals array of function or error values to format
                 * @return {Array.<String>}            array of parsed error or function values
                 */
                    function formatListVals(vals) {
                        var parsedVals = [];

                        function removeSpaceChars(val) {
                            var endIndex = val.length - 1;
                            if (val.indexOf(" ") !== 0 && val.indexOf(" ") !== endIndex) {
                                return val;

                            }
                            if (val.indexOf(" ") === 0) {
                                val = val.slice(1);
                            }
                            if (val.indexOf(" ") === endIndex) {
                                val = val.slice(0, endIndex);
                            }

                            return removeSpaceChars(val);
                        }

                        vals.forEach(function(val) {
                            val = removeSpaceChars(val);
                            parsedVals.push(val);
                        });
                        return parsedVals;
                    }

                    /**
                 * Validate options entered into disable_functions or error_reporting
                 *
                 * @method validateInlineOption
                 * @param  {Object}             poolOption name and value of option to validate
                 * @param  {Boolean}            validate   boolean always set to true so that option is validated, not saved
                 * @param  {String}             [domain]   if it exists then it is validating options for that domain, if it does not the options are validated for system config
                 * @param  {[type]}             formVal    object representing php-fpm form
                 * @return {String | Promise}              on success return value of option validated, on failure return error
                 */
                    function validateInlineOption(poolOption, validate, domain, formVal) {
                        return configService.submitPoolOptions(poolOption, validate, domain)
                            .then(function(data) {

                                if (poolOption.disable_functions) {
                                    $scope.poolOptions.disable_functions.value.push(poolOption.disable_functions.value[0]);
                                    $scope.displayValue.disabledFuncsPanelOpen = true;
                                    $scope.displayValue.disabledFuncs = "";
                                    formVal.$setDirty();
                                    return poolOption.disable_functions.value[0];
                                } else if (poolOption.error_reporting) {
                                    $scope.displayValue.reportedErrs = "";
                                    $scope.poolOptions.error_reporting.value.push(poolOption.error_reporting.value[0]);
                                    $scope.displayValue.errsReportedPanelOpen = true;
                                    formVal.$setDirty();
                                    return poolOption.error_reporting.value[0];
                                }
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                });
                            });
                    }

                    /**
                 * Save or validate PHP-FPM form
                 *
                 * @method submitPoolOptions
                 * @param  {Object}          poolOptions names and value of pool options to submit
                 * @param  {Boolean}         validate    if true options are validated, if false options are saved
                 * @param  {String}          [domain]    if it exists options are saved/validated for individual domain, if it does not options are saved/validated for the system config
                 * @param  {Object}          formVal     object representing php-fpm form
                 * @return {Promise}
                 */
                    function submitPoolOptions(poolOptions, validate, domain, formVal) {
                        return configService.submitPoolOptions(poolOptions, validate, domain)
                            .then(function(data) {
                                var successMessage;
                                if (validate) {
                                    successMessage = LOCALE.maketext("The system successfully validated the [asis,PHP-FPM] configuration.");
                                } else {
                                    formVal.$setPristine();
                                    $scope.poolOptionsCache = angular.copy(poolOptions);
                                    successMessage = LOCALE.maketext("The system successfully saved the [asis,PHP-FPM] configuration.");
                                }
                                alertService.add({
                                    type: "success",
                                    message: successMessage,
                                    autoClose: 5000,
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                });
                            });
                    }

                    /**
                 * Get document root from global value
                 *
                 * @method getDocRootValue
                 * @return {String}        document root
                 */
                    function getDocRootValue() {
                        return PAGE.selectedDomainDocRoot;
                    }

                    /**
                 * Get domain home directory from global value
                 *
                 * @method getHomeDirectory
                 * @return {String}         domain home directory
                 */
                    function getHomeDirectory() {
                        return PAGE.selectedDomainHomeDir;
                    }

                    /**
                 * Get selected domain name from global values
                 *
                 * @method getSelectedDomainName
                 * @return {String}              selected domain value
                 */
                    function getSelectedDomainName() {
                        return PAGE.selectedDomainName;
                    }

                    /**
                 * Get display mode from global values
                 *
                 * @method getDisplayMode
                 * @return {String}       display mode
                 */
                    function getDisplayMode() {
                        return PAGE.poolOptionsDisplayMode;
                    }

                    /**
                 * Parse location of error log for use by front end
                 *
                 * @method parseErrorLog
                 * @param  {String}      data raw error log location
                 * @return {String}           parsed error log location
                 */
                    function parseErrorLog(data) {

                        function replacer() {
                            return "_";
                        }

                        function removeLeadingChars(log) {
                            if (log.indexOf(".") === 0) {
                                return log;

                            }
                            log = log.slice(1);
                            return removeLeadingChars(log);
                        }

                        var scrubbedDomainSplitter = "[% scrubbed_domain %]";
                        var scrubbedDomain = $scope.displayValue.selectedDomain.replace(/\./, replacer);
                        var parsedErrorLog;
                        if (data.error_log.value.indexOf(scrubbedDomainSplitter) !== -1) {
                            parsedErrorLog = removeLeadingChars(data.error_log.value.split("scrubbed_domain")[1]);
                            parsedErrorLog = scrubbedDomain + parsedErrorLog;
                            data.error_log.value = parsedErrorLog;
                        }
                        return data;
                    }

                    /**
                 * Get existing pool options
                 *
                 * @method getPoolOptions
                 * @param  {String}       [domain] if it exists fetch pool options for individual domain, if it doesn't fetch system pool options
                 */
                    function getPoolOptions(domain) {
                        return configService.getPHPFPMSettings(domain)
                            .then(function(data) {
                                if (domain) {
                                    data = parseErrorLog(data);
                                }
                                $scope.poolOptions = data;
                                $scope.poolOptionsCache = angular.copy($scope.poolOptions);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                });
                            })
                            .finally(function() {
                                scrollToFormTop();
                                $scope.actions.initialLoading = false;
                            });

                    }

                    /**
                 * Scroll to top of form
                 *
                 * @method scrollToFormTop
                 */
                    function scrollToFormTop() {
                        $anchorScroll.yOffset = -100;
                        $anchorScroll("content");
                    }

                    /**
                 * Initialize app
                 *
                 * @method init
                 */
                    function init() {

                        $scope.actions = {
                            initialLoading: true,
                            validatingFuncs: false,
                            validatingErrs: false,
                        };

                        $scope.displayValue.displayMode = getDisplayMode() || "default";
                        if ($scope.displayValue.displayMode === "domain") {
                            $scope.displayValue.docRootDisplayValue = getDocRootValue() + "/";
                            $scope.displayValue.logDirDisplayValue = getHomeDirectory() + "/logs/";
                            $scope.displayValue.selectedDomain = getSelectedDomainName();
                            getPoolOptions($scope.displayValue.selectedDomain);
                        } else {
                            getPoolOptions();
                        }

                    }
                    init();
                }]
        );
        return controller;
    }
);

/*
 * templates/multiphp_manager/views/phpManagerConfig.js
 *                                                 Copyright 2022 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
/* eslint no-use-before-define: 0*/

define(
    'app/views/phpManagerConfig',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/util/table",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "app/services/configService",
        "app/views/impactedDomainsPopup",
        "app/views/poolOptions"
    ],
    function(angular, _, LOCALE, PARSE, Table) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "phpManagerController",
            ["$scope", "$rootScope", "$q", "configService", "$timeout", "$uibModal", "alertService", "PAGE", "$interval",
                function($scope, $rootScope, $q, configService, $timeout, $uibModal, alertService, PAGE, $interval) {

                    $rootScope.$on("returnToDomainList", function() {
                        $rootScope.editPoolOptionsMode = false;

                        if (PAGE.poolOptionsDisplayMode) {
                            delete PAGE.poolOptionsDisplayMode;
                        }
                    });
                    $rootScope.litespeedRunning = PARSE.parsePerlBoolean(PAGE.litespeed_running);

                    var altRegex = /^alt/;
                    var eolWarningMsgLastPart = LOCALE.maketext("We recommend that you update to a supported version of [asis,PHP]. [output,url,_1,Learn more about supported versions,target,_2].", "http://php.net/supported-versions.php", "_blank");

                    $scope.actions = {
                        initialDataLoading: true,
                        loadingFPMInfo: false,
                        fetchingImpactedDomains: false,
                        settingSystemPHP: false,
                        fpmConversionRunning: false,
                        fpmConversionRunningOnLoad: false,
                        loadingAccountList: false
                    };

                    $scope.php = {
                        versions: [],
                        versionsInherit: [],
                        systemDefault: {
                            version: "",
                            displayVersion: "",
                            hasFPMInstalled: false,
                            showEolMsg: false,
                            eolWarningMsg: LOCALE.maketext("[output,strong,Warning]: Your system’s [asis,PHP] version has reached [output,acronym,EOL,End Of Life].") + " " + eolWarningMsgLastPart
                        },
                        showEolMsg: false,
                        eolWarningMsg: "",
                        perDomain: {
                            selected: ""
                        },
                        accountList: [],
                        compatibleVersions: [],
                        installedVersion: [],
                        systemEditView: false,
                        totalSelectedDomains: 0,
                        paginationMessage: "",
                        inheritWarning: LOCALE.maketext("[asis,PHP-FPM] option is disabled when one or more selections contain PHP version of [output,em,inherit]."),
                        incompatibleWarning: LOCALE.maketext("[asis,PHP-FPM] option is disabled when one or more selections contain PHP version that doesn’t have corresponding [asis,PHP-FPM] package installed."),
                        noVersions: false,
                    };

                    $scope.fpm = {
                        completePackageData: [],
                        checkingFPMPackage: false,
                        fpmPackageNeeded: false,
                        flag: false,
                        showMemoryWarning: false,
                        systemStatus: false,
                        requiredMemoryAmount: 0,
                        ea4ReviewLink: "",
                        fcgiMissing: false,
                        ea4Went: false,
                        conversionTimer: null,
                        conversionTimerInterval: 3000,
                        convertBuildId: null,
                        fpmConversionStarted: false,
                        domainSelection: 0,
                        missingPackages: [],
                        fpmWarning: LOCALE.maketext("The [output,em,inherit] option of [asis,PHP] Version is disabled when one or more selections have [asis,PHP-FPM] on.")
                    };

                    $scope.applyingPHPVersionTo = [];

                    var domainTable = new Table();

                    // Add more pageSizes.
                    domainTable.meta.pageSizes = _.concat(domainTable.meta.pageSizes, [500, 1000]);

                    var searchByDomainOrAccount = function(account, searchExpression) {
                        searchExpression = searchExpression.toLowerCase();

                        return account.account.toLowerCase().indexOf(searchExpression) !== -1 ||
                        account.vhost.toLowerCase().indexOf(searchExpression) !== -1 || account.account_owner.toLowerCase().indexOf(searchExpression) !== -1;
                    };

                    domainTable.setSearchFunction(searchByDomainOrAccount);
                    domainTable.setSort("vhost,account,account_owner,version,php_fpm", "asc");

                    $scope.meta = domainTable.getMetadata();

                    $scope.getFPMInfo = function() {
                        return getFPMInfo();
                    };

                    $scope.setFPMFlag = function() {
                        $scope.fpm.flag = false;
                        return configService.setFPMFlag();
                    };

                    $scope.editSystemPHP = function(toEditMode) {
                        if (toEditMode) {
                            $scope.php.systemEditView = true;
                            $scope.impactedDomains = {};
                            preSelectSystemValue();
                            processImpactedDomains("system_default", true, $scope.impactedDomains, true);
                        } else {
                            $scope.php.systemEditView = false;
                        }
                    };

                    $scope.applySystemPHP = function() {
                        return setSystemPHPVersion($scope.php.systemDefault.selected);
                    };

                    $scope.requiredMemory = function() {
                        return LOCALE.maketext("Your system requires [format_bytes,_1] of memory to convert the remaining domains to [asis,PHP-FPM].", $scope.fpm.requiredMemoryAmount);
                    };

                    $scope.switchSystemFPM = function() {
                        $scope.fpm.systemStatus = !$scope.fpm.systemStatus;
                        var status = $scope.fpm.systemStatus ? 1 : 0;
                        switchSystemFPM(status);
                    };

                    $scope.convertAllAccountsToFPM = function() {
                        return convertAllAccountsToFPM();
                    };

                    var addImpactedDomainsTo = function(vhost) {
                        if (typeof vhost.impactedDomains === "undefined") {
                            vhost.impactedDomains = {};
                        }

                        processImpactedDomains("domain", vhost.vhost, vhost.impactedDomains, vhost.selected);
                    };

                    $scope.handleEntireListSelection = function() {
                        var areAllSelected = domainTable.areAllDisplayedRowsSelected();
                        if (areAllSelected) {
                            domainTable.unselectAllDisplayed();
                        } else {
                            domainTable.selectAllDisplayed();
                        }
                        $scope.php.totalSelectedDomains = domainTable.getTotalRowsSelected();
                        $scope.php.accountList = domainTable.getList();
                    };

                    $scope.handleSingleListSelection = function(vhost) {
                        addImpactedDomainsTo(vhost);
                        if (vhost.selected) {
                            domainTable.selectItem(vhost);
                        } else {
                            domainTable.unselectItem(vhost);
                        }
                        $scope.php.allRowsSelected = domainTable.areAllDisplayedRowsSelected();
                        $scope.php.totalSelectedDomains = domainTable.getTotalRowsSelected();
                        $scope.php.accountList = domainTable.getList();
                    };

                    $scope.searchByDomainOrAccount = function() {
                        domainTable.update();

                        $scope.php.accountList = domainTable.getList();
                        $scope.meta = domainTable.getMetadata();
                        $scope.php.paginationMessage = domainTable.paginationMessage();
                    };

                    $scope.areRowsSelected = function() {
                        var rowsSelected = domainTable.getTotalRowsSelected();

                        if (rowsSelected === 0) {
                            return true;
                        } else {
                            return false;
                        }
                    };

                    $scope.applyPHPToMultipleAccounts = function() {
                        var version = $scope.php.perDomain.selected.version;
                        var vhostList = [];

                        var domains = domainTable.getSelectedList();
                        domains.forEach(function(domain) {
                            vhostList.push(domain.vhost);
                        });

                        $scope.php.accountList = domainTable.getList();

                        return applyPHPVersionToAccounts(version, vhostList);
                    };

                    $scope.applyPHPToSingleAccount = function(account) {
                        if (account.version === "inherit" && account.php_fpm) {
                            var version = account.display_php_version.split(" ")[2];
                            var endPoint = version.length - 2;
                            account.version = version.substr(1, endPoint);
                            return;
                        }
                        var vhostList = [];
                        vhostList.push(account.vhost);
                        applyPHPVersionToAccounts(account.version, vhostList);
                    };

                    $scope.isAnyDomainInherited = function() {
                        var accounts = domainTable.getSelectedList();
                        for (var i = 0, len = accounts.length; i < len; i++) {
                            if (accounts[i].inherited) {
                                return true;
                            }
                        }
                        return false;
                    };

                    $scope.isAnyDomainFPM = function() {
                        var accounts = domainTable.getSelectedList();
                        for (var i = 0, len = accounts.length; i < len; i++) {
                            if (accounts[i].php_fpm) {
                                return true;
                            }
                        }
                        return false;

                    };

                    $scope.updateTable = function() {
                        domainTable.update();
                        $scope.php.accountList = domainTable.getList();
                        $scope.meta = domainTable.getMetadata();
                        $scope.php.paginationMessage = domainTable.paginationMessage();
                    };

                    $scope.isAnyDomainIncompatible = function() {
                        var accounts = domainTable.getSelectedList();
                        var compatibleVersions = [];
                        $scope.php.compatibleVersions.forEach(function(version) {
                            version = version.split("-php-fpm")[0];
                            compatibleVersions.push(version);
                        });
                        for (var i = 0, len = accounts.length; i < len; i++) {
                            if (compatibleVersions.indexOf(accounts[i].version) === -1) {
                                return true;
                            }
                        }
                        return false;
                    };

                    $scope.isDomainVersionIncompatible = function(domainVersion) {

                        // always return false if domainVersion is "inherit"
                        if (domainVersion === "inherit") {
                            return false;
                        }

                        var compatibleVersions = [];
                        $scope.php.compatibleVersions.forEach(function(version) {
                            version = version.split("-php-fpm")[0];
                            compatibleVersions.push(version);
                        });

                        for (var i = 0, len = compatibleVersions.length; i < len; i++) {
                            if (domainVersion === compatibleVersions[i]) {
                                return false;
                            }
                        }
                        return true;
                    };

                    $scope.setMultipleDomainFPM = function() {
                        $scope.actions.applyingFPM = true;
                        var vhostList = [];
                        var selectedAccounts = domainTable.getSelectedList();

                        selectedAccounts.forEach(function(account) {
                            vhostList.push(account.vhost);
                        });
                        return applyDomainFPM($scope.fpm.domainSelection, vhostList);
                    };

                    $scope.setSingleDomainFPM = function(domain) {
                        var domainValue = domain.php_fpm ? 0 : 1;
                        var vhostList = [];
                        vhostList.push(domain.vhost);
                        return applyDomainFPM(domainValue, vhostList);
                    };

                    $scope.showAllImpactedDomains = function() {
                        var modalData = $scope.impactedDomains;
                        $uibModal.open({
                            templateUrl: "impactedDomainsPopup.ptt",
                            controller: "impactedDomainsPopup",
                            resolve: {
                                data: function() {
                                    return modalData;
                                }
                            }
                        });
                    };

                    $scope.setPoolOptionsDisplayValues = function(vhost) {
                        PAGE.poolOptionsDisplayMode = "domain";
                        PAGE.selectedDomainHomeDir = vhost.homedir;
                        PAGE.selectedDomainDocRoot = vhost.documentroot;
                        PAGE.selectedDomainName = vhost.vhost;
                        $rootScope.editPoolOptionsMode = true;
                    };

                    var getPHPVersions = function() {
                        return configService
                            .fetchPHPVersions()
                            .then(function(results) {
                                $scope.php.versions = createPHPDisplayVersions(results);
                                $scope.php.versionsInherit = createPHPVersionListInherit($scope.php.versions);
                            })
                            .catch(function(error) {

                                // No PHP version error is displayed as callout, so it does not also need to be an alert
                                if (error.indexOf("“PHP” is not installed on the system") === -1) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "getPHPVersionsError"
                                    });
                                }
                            });
                    };

                    var getSystemPHP = function() {
                        return configService.fetchSystemPhp()
                            .then(function(results) {
                                $scope.php.systemDefault.version = results.version;
                                $scope.php.systemDefault.displayVersion = configService.transformPhpFormat(results.version);
                            })
                            .catch(function(error) {

                                // No PHP version error is displayed as callout, so it does not also need to be an alert
                                if (error.indexOf("“PHP” is not installed on the system") === -1) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "getSystemPHPError"
                                    });
                                }
                            });
                    };


                    var validatePoolOption = function(input, max) {
                        var value = parseInt(input, 10);
                        if (isNaN(value)) {
                            return false;
                        } else if (value <= 0) {
                            return false;
                        } else if (value > max) {
                            return false;
                        }
                        return true;
                    };

                    var savePoolOptions = function(vhost) {
                        return configService.savePoolOption(vhost)
                            .then(function(data) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully updated the pool options for the domain “[_1]”.", vhost.vhost),
                                    autoClose: 5000,
                                    id: "poolOptionsSuccessMessage-" + vhost.vhost
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("Failed to apply [asis,PHP-FPM] Pool options to the selected domain."),
                                    closeable: true,
                                    id: "poolOptionsError"
                                });
                            })
                            .finally(function() {
                                getAccountList();
                            });
                    };

                    var applyDomainFPM = function(domainValue, selectedVhostList) {
                        $scope.actions.applyingFPM = true;
                        return configService.applyDomainFpm(domainValue, selectedVhostList)
                            .then(function(data) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully updated the [asis,PHP-FPM] setting."),
                                    autoClose: 5000,
                                    id: "phpFPMSuccessMessage"
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    id: "domainFPMError"
                                });
                            })
                            .finally(function() {
                                $scope.actions.applyingFPM = false;
                                getAccountList();
                            });
                    };

                    var applyPHPVersionToAccounts = function(version, vhostList) {
                        $scope.actions.applyingPHPVersion = true;
                        $scope.applyingPHPVersionTo = vhostList.slice();
                        return configService.applyDomainSetting(version, vhostList)
                            .then(function(data) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system successfully updated the [asis,PHP] version to “[_1]”.", version),
                                    autoClose: 5000,
                                    id: "phpDomainSuccessMessage"
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    id: "domainVersionError"
                                });
                            })
                            .finally(function() {

                                // add a little delay so updating message is easier to read
                                $timeout(function() {
                                    $scope.actions.applyingPHPVersion = false;
                                    $scope.applyingPHPVersionTo = [];
                                }, 500);
                                getAccountList();
                            });
                    };

                    $scope.phpConversionInProgressFor = function(acct) {
                        return $scope.applyingPHPVersionTo.indexOf(acct) !== -1;
                    };

                    $scope.processInProgress = function() {
                        return $scope.actions.loadingAccountList ||  $scope.actions.applyingPHPVersion ||  $scope.actions.applyingFPM ||  $scope.fpm.fpmConversionStarted;
                    };

                    var convertAllAccountsToFPM = function() {
                        $scope.fpm.fpmConversionStarted = true;
                        return configService.convertAllAccountsToFPM()
                            .then(function(data) {
                                $scope.fpm.convertBuildId = data.build;
                                return monitorConversionStatus();
                            })
                            .catch(function(error) {
                                if (error === "canceled") {
                                    $scope.fpm.conversionTimer = null;
                                } else {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "convertAllAccountsError"
                                    });
                                }
                            })
                            .finally(function() {
                                $scope.fpm.fpmConversionStarted = false;
                                getAccountList();
                            });
                    };

                    var switchSystemFPM = function(newStatus) {
                        return configService.switchSystemFPM(newStatus)
                            .then(function(data) {
                                fetchFPMSystemStatus();
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "fpmSystemSwitchError"
                                });
                            });
                    };

                    var fetchFPMSystemStatus = function() {
                        return configService.fetchFPMStatus()
                            .then(function(data) {
                                $scope.fpm.systemStatus = PARSE.parsePerlBoolean(data.default_accounts_to_fpm);
                            });
                    };

                    var monitorConversionStatus = function() {
                        $scope.fpm.conversionTimer = $interval(function() {
                            configService.conversionInProgress()
                                .then(function(inProgress) {
                                    $scope.actions.fpmConversionRunning = inProgress;
                                    if (!inProgress) {
                                        $scope.actions.fpmConversionRunning = false;
                                        $scope.actions.fpmConversionRunningOnLoad = false;
                                        $interval.cancel($scope.fpm.conversionTimer);
                                    }
                                });
                        }, $scope.fpm.conversionTimerInterval);
                        return $scope.fpm.conversionTimer;
                    };

                    var setSystemPHPVersion = function(phpVersion) {
                        $scope.actions.settingSystemPHP = true;
                        alertService.clear();
                        return configService.applySystemSetting(phpVersion.version)
                            .then(function(data) {
                                if (data !== undefined) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("The system default [asis,PHP] version has been set to “[_1]”.", phpVersion.displayVersion),
                                        autoClose: 10000,
                                        id: "phpSystemSuccess"
                                    });
                                    $scope.php.systemDefault.version = phpVersion.version;
                                    $scope.php.systemDefault.displayVersion = configService.transformPhpFormat(phpVersion.version);
                                    $scope.php.toggleEolWarning("systemDefault", isPhpEol($scope.php.systemDefault.version));
                                }

                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "phpSystemError"
                                });
                            })
                            .finally(function() {
                                runFPMPackageCheck($scope.fpm.completePackageData);
                                $scope.php.systemEditView = false;
                                $scope.actions.settingSystemPHP = false;
                                getAccountList();
                            });
                    };

                    var preSelectSystemValue = function() {
                        for (var i = 0, len = $scope.php.versions.length; i < len; i++) {
                            if ($scope.php.versions[i].version === $scope.php.systemDefault.version) {
                                $scope.php.systemDefault.selected = $scope.php.versions[i];
                                return;
                            }
                        }
                    };

                    var processImpactedDomains = function(type, value, impactedDomains, selected) {
                        if (selected) {

                            // Currently there are only two types: domain (string value), system_default (bool value).
                            $scope.actions.fetchingImpactedDomains = true;
                            configService.fetchImpactedDomains(type, value)
                                .then(function(result) {
                                    var domains = result.data;
                                    if (result.status && domains.length > 0) {
                                        impactedDomains.show = impactedDomains.warn = true;
                                        impactedDomains.showMore = domains.length > 10;
                                        var displayText = ( type === "domain" ) ?
                                            LOCALE.maketext("A change to the “[output,strong,_1]” domain‘s PHP version affects the following domains:", value)
                                            :
                                            LOCALE.maketext("A change to the system default PHP version affects the following domains:");
                                        impactedDomains.text = displayText;
                                        impactedDomains.domains = _.sortBy(domains);
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "fetchImpactedDomainsError"
                                    });
                                    impactedDomains.show = impactedDomains.warn = false;
                                })
                                .finally(function() {
                                    $scope.actions.fetchingImpactedDomains = false;
                                    $scope.impactedDomains = impactedDomains;
                                });
                        } else {
                            impactedDomains.show = impactedDomains.warn = false;
                            $scope.impactedDomains = impactedDomains;
                        }
                    };

                    var formatFPMMemoryNeeded = function(fpmData) {
                        var memoryRequired = fpmData.environment.memory_needed * 1024;
                        return memoryRequired;
                    };

                    var checkFPMSystemStatus = function(fpmData) {
                        var systemStatus = PARSE.parsePerlBoolean(fpmData.status.default_accounts_to_fpm);
                        return systemStatus;
                    };

                    var checkFPMMemoryWarning = function(fpmData) {
                        var showMemoryWarning = PARSE.parsePerlBoolean(fpmData.environment.show_warning);

                        if (showMemoryWarning) {
                            $scope.fpm.requiredMemoryAmount = formatFPMMemoryNeeded(fpmData);
                        }

                        return showMemoryWarning;
                    };

                    var createFPMPackageCheckList = function(phpVersions) {
                        var fpmPackageChecklist = [];
                        phpVersions.forEach(function(version) {
                            if (version.version !== "inherit" && !altRegex.test(version.version)) {
                                fpmPackageChecklist.push(version.version);
                            }
                        });

                        // Add ea-apache24-mod_proxy_fcgi in addition to php versions
                        fpmPackageChecklist.push("ea-apache24-mod_proxy_fcgi");
                        return fpmPackageChecklist;
                    };

                    var isSystemPHPFPMInstalled = function(fpmPackages, phpSystemDefault) {
                        phpSystemDefault = phpSystemDefault + "-php-fpm";
                        for (var i = 0, len = fpmPackages.length; i < len; i++) {
                            if (phpSystemDefault === fpmPackages[i].package) {
                                return true;
                            }
                        }
                        return false;
                    };

                    var createMissingPackageDisplayVersions = function(fpmPackageChecklist) {
                        var displayVersions = "";

                        if (fpmPackageChecklist[0] === "ea-apache24-mod_proxy_fcgi") {
                            fpmPackageChecklist.shift();
                        }

                        fpmPackageChecklist.forEach(function(fpmPackage) {
                            if (fpmPackage !== "ea-apache24-mod_proxy_fcgi") {
                                fpmPackage = fpmPackage.split("ea-php");
                                fpmPackage = fpmPackage[1].split("-php-fpm");
                                fpmPackage = fpmPackage[0].split("").join(".");
                            }
                            displayVersions = displayVersions + fpmPackage + ", ";
                        });

                        return displayVersions;
                    };

                    var checkCompatibleVersions = function(fpmPackages, fpmPackageChecklist) {
                        var compatibleVersions = [];
                        var installedVersions = [];
                        var extendedPackageChecklist = [];
                        fpmPackageChecklist.forEach(function(fpmPackage) {
                            if (fpmPackage !== "ea-apache24-mod_proxy_fcgi") {
                                fpmPackage = fpmPackage + "-php-fpm";
                            }
                            extendedPackageChecklist.push(fpmPackage);
                        });
                        for (var i = 0, len = fpmPackages.length; i < len; i++) {
                            for (var j = 0, length = extendedPackageChecklist.length; j < length; j++) {
                                if (fpmPackages[i].package === extendedPackageChecklist[j]) {
                                    installedVersions.push(fpmPackages[i].package);

                                    if (fpmPackages[i].package !== "ea-apache24-mod_proxy_fcgi") {
                                        compatibleVersions.push(fpmPackages[i].package);
                                    }
                                    extendedPackageChecklist.splice(extendedPackageChecklist.indexOf(fpmPackages[i].package), 1);
                                }
                            }
                        }
                        $scope.fpm.missingPackagesDisplay = createMissingPackageDisplayVersions(extendedPackageChecklist);
                        $scope.php.installedVersion = createMissingPackageDisplayVersions(installedVersions).slice(0, $scope.php.installedVersion.length - 2);
                        $scope.php.compatibleVersions = compatibleVersions;
                        $scope.fpm.missingPackages = extendedPackageChecklist;
                    };

                    var createQueryLink = function(fpmPackageChecklist) {
                        var queryString =
                        _.join(
                            _.map(fpmPackageChecklist,
                                function(fpmPkg) {
                                    return "install=" + fpmPkg;
                                }
                            ), "&"
                        );
                        return PAGE.cp_security_token + "/scripts7/EasyApache4/review?" + queryString;
                    };

                    var isFcgiMissing = function(fpmMissingPackages) {
                        if ($scope.fpm.missingPackages.indexOf("ea-apache24-mod_proxy_fcgi") !== -1) {
                            return true;
                        } else {
                            return false;
                        }
                    };

                    var runFPMPackageCheck = function(fpmPackageData) {
                        $scope.fpm.packageChecklist = createFPMPackageCheckList($scope.php.versions);
                        $scope.php.systemDefault.hasFPMInstalled = isSystemPHPFPMInstalled(fpmPackageData, $scope.php.systemDefault.version);

                        // fpm.packageChecklist turns into fpm.missingPackages here
                        checkCompatibleVersions(fpmPackageData, $scope.fpm.packageChecklist);

                        if ($scope.fpm.missingPackages.length) {
                            $scope.fpm.ea4ReviewLink = createQueryLink($scope.fpm.missingPackages);
                        }
                        $scope.fpm.fcgiMissing = isFcgiMissing($scope.fpm.missingPackages);
                    };

                    var getFPMInfo = function() {
                        $scope.actions.loadingFPMInfo = true;
                        return configService.getPHPFPMInfo()
                            .then(function(data) {
                                $scope.fpm.completePackageData = data.packages;
                                $scope.fpm.systemStatus = checkFPMSystemStatus(data);
                                $scope.fpm.showMemoryWarning = checkFPMMemoryWarning(data);
                                runFPMPackageCheck(data.packages);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "fetchFPMInfoError"
                                });
                            })
                            .finally(function() {
                                $scope.actions.loadingFPMInfo = false;
                            });
                    };

                    var createPHPDisplayVersions = function(phpVersions) {
                        var versionObj;
                        var versions = [];
                        phpVersions.forEach(function(version) {
                            versionObj = {};
                            versionObj["version"] = version;
                            versionObj["displayVersion"] = configService.transformPhpFormat(version);
                            versions.push(versionObj);
                        });
                        return versions;
                    };

                    var labelInheritedAccounts = function(phpAccountList) {
                        phpAccountList.forEach(function(account) {
                            if ( typeof account.phpversion_source !== "undefined" ) {
                                var type = "", value = "";
                                if ( typeof account.phpversion_source.domain !== "undefined" ) {
                                    type = "domain";
                                    value = account.phpversion_source.domain;
                                } else if (typeof account.phpversion_source.system_default !== "undefined") {
                                    type = "system_default";
                                    value = LOCALE.maketext("System Default");
                                }

                                if ((type === "domain" && value !== account.vhost) ||
                            type === "system_default") {
                                    account.version = "inherit";
                                    account.displayVersion = "inherit (" + $scope.php.systemDefault.version + ")";
                                    account.inherited = true;
                                    account.inheritedInfo = LOCALE.maketext("This domain inherits its [asis,PHP] version “[output,em,_1]” from: [output,strong,_2]", account.display_php_version, value);
                                }
                            }
                        });
                        return phpAccountList;
                    };

                    var labelUnavailableAccounts = function(phpAccountList) {
                        var phpVersions = [];
                        $scope.php.versions.forEach(function(version) {
                            phpVersions.push(version.version);
                        });
                        phpAccountList.forEach(function(account) {
                            if (account.version === "inherit") {
                                account.isUnavailableVersion = false;
                            } else if (phpVersions.indexOf(account.version) === -1) {
                                account.isUnavailableVersion = true;
                                account.isUnavailableVersionMessage = LOCALE.maketext("The domain ‘[_1]’ uses a PHP version, ‘[_2]’, that no longer exists in the system. You must select a new PHP version for this domain.", account.vhost, account.version);
                            } else {
                                account.isUnavailableVersion = false;
                            }
                        });
                        return phpAccountList;
                    };

                    var createAccountTable = function(phpAccountList) {
                        phpAccountList = labelInheritedAccounts(phpAccountList);
                        phpAccountList = labelUnavailableAccounts(phpAccountList);
                        domainTable.load(phpAccountList);
                        domainTable.update();
                        $scope.meta = domainTable.getMetadata();
                        $scope.php.accountList = domainTable.getList();
                        $scope.php.paginationMessage = domainTable.paginationMessage();
                    };

                    var createPHPVersionListInherit = function(phpVersionList) {
                        var clonedList = phpVersionList.slice();
                        clonedList.push({
                            version: "inherit",
                            displayVersion: "inherit"
                        });
                        return clonedList;
                    };

                    var preSelectPerDomainValue = function() {
                        for (var i = 0, len = $scope.php.versionsInherit.length; i < len; i++) {
                            if ($scope.php.versionsInherit[i].version === $scope.php.systemDefault.version) {
                                $scope.php.perDomain.selected = $scope.php.versionsInherit[i];
                                return;
                            }
                        }
                    };

                    var setInitialPHPFPMData = function() {
                        if (PAGE.php_versions.data) {
                            $scope.actions.fpmConversionRunning = $scope.actions.fpmConversionRunningOnLoad = PARSE.parsePerlBoolean(PAGE.fpm_conversion_in_progress);
                            $scope.php.noVersions = false;
                        } else {
                            $scope.php.noPHPVersionsError = PAGE.php_versions.metadata.reason;
                            $scope.php.noVersions = true;
                        }
                        if ($scope.actions.fpmConversionRunning) {
                            monitorConversionStatus();
                        }
                    };

                    var getAccountList = function() {
                        $scope.actions.loadingAccountList = true;
                        clearTable();
                        return configService.fetchList()
                            .then(function(data) {
                                createAccountTable(data.items);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "fetchTableListError"
                                });
                            })
                            .finally(function() {
                                $scope.php.allRowsSelected = false;
                                $scope.actions.loadingAccountList = false;
                            });
                    };

                    var clearTable = function() {
                        domainTable.clear();
                        $scope.php.totalSelectedDomains = 0;
                    };

                    var clearPoolOptionsDisplaySettings = function() {
                        $rootScope.editPoolOptionsMode = false;
                        if (PAGE.poolOptionsDisplayMode) {
                            delete PAGE.poolOptionsDisplayMode;
                        }
                    };

                    var isPhpEol = function(phpVer) {
                        return _.includes($scope.php.eolPhps, phpVer);
                    };

                    $scope.php.eolWarningClass = function(type) {
                        var cssClass = "";
                        switch (type) {
                            case "systemDefault":
                                if ($scope.php.systemDefault.showEolMsg) {
                                    cssClass = "system eol-warning";
                                }
                                break;
                            default:
                                cssClass = "";
                        }
                        return cssClass;
                    };

                    $scope.php.toggleEolWarning = function(type, show) {
                        switch (type) {
                            case "systemDefault":
                                $scope.php.systemDefault.showEolMsg = show;
                                break;
                        }
                        if (show) {
                            $scope.php.eolWarningClass(type);
                        } else {
                            $scope.php.eolWarningClass();
                        }
                    };

                    var setPhpEolData = function() {
                        var eolPhps = [];
                        if ($scope.php.versions.length > 0) {
                            return configService.getEA4Recommendations()
                                .then(function(result) {
                                    if (result && typeof result.data !== "undefined") {
                                        var keys = _.filter(_.keys(result.data), function(key) {
                                            return (/^ea-php\d{2}$/.test(key));
                                        });

                                        // Extract only the keys for the installed PHPs.
                                        keys = _.sortBy(_.intersection(keys, _.map($scope.php.versions, "version")));
                                        _.each(keys, function(key) {
                                            _.each(result.data[key], function(reco) {
                                                if (_.includes(reco.filter, "eol")) {
                                                    eolPhps.push(key);
                                                }
                                            });
                                        });
                                        if (eolPhps.length > 0) {
                                            $scope.php.eolPhps = eolPhps;
                                            var displayEolPhps = _.map(eolPhps, function(php) {
                                                return configService.friendlyPhpFormat(php);
                                            });
                                            var eolWarningMsg = LOCALE.maketext("[output,strong,Warning]: The [asis,PHP] [numerate,_2,version,versions] [list_and,_1] [numerate,_2,has,have] reached [output,acronym,EOL,End Of Life].", displayEolPhps, eolPhps.length) + " " + eolWarningMsgLastPart;
                                            $scope.php.showEolMsg = true;
                                            $scope.php.eolWarningMsg = eolWarningMsg;
                                        }
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        closeable: true,
                                        id: "recommendationsError"
                                    });
                                });
                        }
                    };

                    var init = function() {

                        // ===No API calls===
                        clearPoolOptionsDisplaySettings();
                        $scope.clData = PAGE.cl_data;
                        $scope.clBannerText = LOCALE.maketext("[output,strong,cPanel] provides the most recent stable versions of PHP. If you require legacy versions of PHP, such as PHP [list_and,_3], [asis,CloudLinux] provides hardened and secured [asis,PHP] versions that are patched against all known vulnerabilities. To learn more about [asis,CloudLinux] Advanced PHP Features, please read [output,url,_1,Hardened PHP versions on CloudLinux,target,_2].", "https://go.cpanel.net/cloudlinuxhardenedphp", "_blank", [4.4, 5.1, 5.2, 5.3]);
                        setInitialPHPFPMData();

                        // ===API calls===

                        var promises = {
                            info: getFPMInfo(),
                            versions: getPHPVersions(),
                            system: getSystemPHP()
                        };

                        $q.all(promises)
                            .then(function(data) {
                                setPhpEolData();
                                preSelectPerDomainValue();
                                return getAccountList();
                            })
                            .finally(function(data) {
                                $timeout(function() {

                                    // $scope.php.systemDefault.eolWarningMsg = systemEolWarningMsg;
                                    $scope.php.toggleEolWarning("systemDefault", isPhpEol($scope.php.systemDefault.version));
                                }, 0);
                                $scope.actions.initialDataLoading = false;
                            });
                    };
                    init();
                }
            ]);
        return controller;
    }
);

/*
 * templates/multiphp_manager/views/phpHandlers.js       Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/views/phpHandlers',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/configService"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "phpHandlers",
            ["$scope", "$location", "$routeParams", "$timeout", "$filter", "configService", "spinnerAPI", "alertService", "growl", "growlMessages", "$anchorScroll", "PAGE",
                function($scope, $location, $routeParams, $timeout, $filter, configService, spinnerAPI, alertService, growl, growlMessages, $anchorScroll, PAGE) {

                // Setup data structures for the view
                    $scope.loadingVersionsList = false;
                    $scope.phpVersionsEmpty = true;
                    $scope.meta = {

                    // Sort settings
                        sortReverse: false,
                        sortBy: "version",
                        sortDirection: "asc"
                    };

                    var orderBy = $filter("orderBy");

                    $scope.sortList = function() {

                    // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            $scope.phpVersionHandlerList = orderBy($scope.phpVersionHandlerList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }
                    };

                    $scope.editPhpHandler = function(itemToEdit) {

                    // set that record's editView = true;
                        itemToEdit.editView = true;

                    };

                    var clearConflictView = function(item) {
                        item.conflicts = [];
                        item.showAlert = false;
                    };

                    var applyListToTable = function(resultList) {
                        var versionList = resultList.items;

                        $scope.phpVersionHandlerList = versionList.map(function(item) {
                            item.editView = false;
                            item.conflicts = [];    // Records all the conflicts that happen when a handler is changed.
                            item.showAlert = false; // Used when conflicts/warnings need to be shown
                            item.originalHandler = item.current_handler;  // Used to decide when to show/hide warning.
                            return item;
                        });
                    };

                    $scope.cancelHandlerEdit = function(item) {
                        item.editView = false;
                        item.current_handler = item.originalHandler;
                        clearConflictView(item);
                    };

                    /**
                 * Fetch the list of PHP versions with their associated handlers.
                 * @return {Promise} Promise that will result in the list being loaded with the PHP versions with handlers.
                 */
                    $scope.fetchVersionHandlerList = function() {
                        $scope.loadingVersionsList = true;
                        return configService
                            .fetchVersionHandlerList()
                            .then(function(results) {
                                applyListToTable(results);
                                $scope.lsApiInstalled = _.includes(_.uniq(
                                    _.flatten(
                                        _.map($scope.phpVersionHandlerList, "available_handlers")
                                    )
                                ), "lsapi");
                            }, function(error) {

                            // failure
                                growl.error(error);
                            })
                            .then(function() {
                                $scope.loadingVersionsList = false;
                            });
                    };

                    // Apply the new PHP version setting of a selected user
                    $scope.applyVersionHandler = function(item) {
                        growlMessages.destroyAllMessages();
                        clearConflictView(item);
                        return configService.applyVersionHandler(item.version, item.current_handler)
                            .then(
                                function(success) {
                                    if (success) {
                                        growl.success(LOCALE.maketext("Successfully applied the “[_1]” [asis,PHP] handler to the “[_2]” package.", item.current_handler, item.version));
                                        item.originalHandler = item.current_handler;
                                        item.editView = false;
                                    }
                                })
                            .catch(function(error) {
                                growl.error(_.escape(error));
                            });
                    };

                    $scope.warnUser = function(versionHandler, originalHandler) {
                        if ( versionHandler.current_handler !== originalHandler ) {
                            versionHandler.showAlert = true;
                        } else {
                            versionHandler.showAlert = false;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        growlMessages.destroyAllMessages();
                        $scope.fetchVersionHandlerList();
                        $scope.clData = PAGE.cl_data;
                        $scope.clBannerText = LOCALE.maketext("To utilize the [asis,LSAPI] handler’s full functionality and performance benefits, upgrade your system to [asis,CloudLinux]. To learn more about this feature, please read [output,url,_1,CloudLinux - Mod_lsapi Feature,target,_2].", "https://go.cpanel.net/CL-lsapi", "blank");
                    });
                }
            ]);

        return controller;
    }
);

/*
 * templates/multiphp_manager/views/conversion.js        Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/views/conversion',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "conversion",
            ["$scope", "$sce", "$routeParams",
                function($scope, $sce, $routeParams) {
                    $scope.buildId = $routeParams.buildId;

                    // Create iframe to load the tailing cgi script
                    $scope.tailingUrl = CPANEL.security_token + "/cgi/process_tail.cgi?process=ConvertToFPM&build_id=" + $scope.buildId;
                    $scope.tailingUrl = $sce.trustAsResourceUrl($scope.tailingUrl);
                }
            ]);
        return controller;
    }
);

/*
# templates/multiphp_manager/directives/cloudLinuxBanner.js            Copyright 2022 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/cloudLinuxBanner',[
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/parse",
        "app/services/configService"
    ],
    function(angular, CJT, LOCALE, PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("whm.multiphpManager.cloudLinuxBanner", []);

        /**
         * This is a directive that renders CloudLinux banner where it is needed.
         *
         * Basic usage in a template:
         * <cloud-linux-banner id-prefix="someIdPrefix"
                cl-data = clDataObjectFromApi
                banner-text="clBannerTextFromView">
         * </cloud-linux-banner>
         */
        app.directive("cloudLinuxBanner",
            ["configService",
                function(configService) {
                    var TEMPLATE_PATH = "directives/cloudLinuxBanner.ptt";
                    var RELATIVE_PATH = "templates/multiphp_manager/" + TEMPLATE_PATH;
                    var checkToHideUpgradeOption = function(data) {
                        var purchaseData = data.purchase_cl_data;
                        return (purchaseData.server_timeout ||
                            (purchaseData.error_msg && purchaseData.error_msg !== ""));
                    };

                    var ddo = {
                        replace: true,
                        restrict: "E",
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        scope: {
                            idPrefix: "@",
                            clData: "=",
                            bannerText: "="
                        },
                        link: function postLink(scope, element, attrs) {
                            var scopeData = configService.setCloudLinuxInfo(scope.clData);
                            scope.data = scopeData.data;
                            scope.linkTarget = scopeData.linkTarget;
                            scope.purchaseLink = scopeData.purchaseLink;
                            scope.showBanner = scopeData.showBanner;
                            scope.actionText = scopeData.actionText;

                            scope.hideUpgradeOption = checkToHideUpgradeOption(scope.data);
                        }

                    };
                    return ddo;
                }
            ]
        );
    }
);

/*
 * templates/multiphp_manager/directives/nonStringSelect.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                    All rights reserved.
 * copyright@cpanel.net                                                  http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/directives/nonStringSelect',[
        "angular",
    ],
    function(angular) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.directive("convertToNumber", function() {
            return {
                require: "ngModel",
                link: function(scope, element, attrs, ngModel) {
                    ngModel.$parsers.push(function(val) {
                        return parseInt(val, 10);
                    });
                    ngModel.$formatters.push(function(val) {
                        return "" + val;
                    });
                }
            };
        });

        return controller;
    }
);

/*
* templates/multiphp_manager/index.js            Copyright(c) 2020 cPanel, L.L.C.
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
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "whm.multiphpManager.cloudLinuxBanner"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/phpManagerConfig",
                    "app/views/phpHandlers",
                    "app/views/conversion",
                    "app/directives/cloudLinuxBanner",
                    "app/views/poolOptions",
                    "app/directives/nonStringSelect",
                    "cjt/directives/actionButtonDirective",
                    "cjt/directives/pageSizeDirective",
                    "cjt/decorators/paginationDecorator",
                    "cjt/directives/searchDirective",
                    "cjt/directives/toggleSortDirective"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        phpAccountList: true
                    };

                    // Setup Routing
                    app.config(["$routeProvider", "growlProvider", "$animateProvider",
                        function($routeProvider, growlProvider, $animateProvider) {

                            // This prevents performance issues
                            // when the queue gets large.
                            // cf. https://docs.angularjs.org/guide/animations#which-directives-support-animations-
                            $animateProvider.classNameFilter(/INeverWantThisToAnimate/);

                            // Setup the routes
                            $routeProvider.when("/config", {
                                controller: "phpManagerController",
                                templateUrl: CJT.buildFullPath("multiphp_manager/views/phpManagerConfig.ptt"),
                                reloadOnSearch: false
                            })
                                .when("/handlers", {
                                    controller: "phpHandlers",
                                    templateUrl: CJT.buildFullPath("multiphp_manager/views/phpHandlers.ptt"),
                                    reloadOnSearch: false
                                })
                                .when("/conversion", {
                                    controller: "conversion",
                                    templateUrl: CJT.buildFullPath("multiphp_manager/views/conversion.ptt"),
                                    reloadOnSearch: false
                                })
                                .when("/poolOptions", {
                                    controller: "poolOptionsController",
                                    templateUrl: CJT.buildFullPath("multiphp_manager/views/poolOptions.ptt"),
                                    reloadOnSearch: false
                                })
                                .otherwise({
                                    "redirectTo": "/config"
                                });

                        }
                    ]);

                    app.run(["$rootScope", "$location", function($rootScope, $location) {
                        $("#content").show();

                        // register listener to watch route changes
                        $rootScope.$on("$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                        });
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

