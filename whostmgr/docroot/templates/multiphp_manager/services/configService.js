/* global define: false */

define(
    [

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
