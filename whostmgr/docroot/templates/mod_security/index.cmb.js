/*
# templates/mod_security/views/commonController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/* ------------------------------------------------------------------------------
* DEVELOPER NOTES:
*  1) Put all common application functionality here, maybe
*-----------------------------------------------------------------------------*/

define(
    'app/views/commonController',[
        "angular",
        "cjt/filters/wrapFilter",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "uiBootstrap"
    ],
    function(angular) {

        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", ["ui.bootstrap", "ngSanitize"]);
        }

        var controller = app.controller(
            "commonController",
            ["$scope", "$location", "$rootScope", "alertService", "PAGE",
                function($scope, $location, $rootScope, alertService, PAGE) {

                // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    // Bind the alerts service to the local scope
                    $scope.alerts = alertService.getAlerts();

                    $scope.route = null;

                    /**
                 * Closes an alert and removes it from the alerts service
                 *
                 * @method closeAlert
                 * @param {String} index The array index of the alert to remove
                 */
                    $scope.closeAlert = function(id) {
                        alertService.remove(id);
                    };

                    /**
                 * Determines if the current view matches the supplied pattern
                 *
                 * @method isCurrentView
                 * @param {String} view The path to the view to match
                 */
                    $scope.isCurrentView = function(view) {
                        if ( $scope.route && $scope.route.$$route ) {
                            return $scope.route.$$route.originalPath === view;
                        }
                        return false;
                    };

                    // register listener to watch route changes
                    $rootScope.$on( "$routeChangeStart", function(event, next, current) {
                        $scope.route = next;
                    });
                }
            ]);


        return controller;
    }
);

/* global define: false */

define(
    'app/services/hitlistService',[

        // Libraries
        "angular",

        // Application

        // CJT
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        // Angular components
        "cjt/services/APIService"

    ],
    function(angular, LOCALE, API, APIREQUEST, APIDRIVER) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        /**
         * Converts the response to our application data structure
         * @private
         * @param  {Object} response
         * @return {Object} Sanitized data structure.
         */
        function _convertResponseToList(response) {
            var items = [];
            if (response.status) {
                var data = response.data;
                for (var i = 0, length = data.length; i < length; i++) {
                    var hitList = data[i];
                    items.push(
                        hitList
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
        }

        /**
         * Setup the hitlist models API service
         */
        app.factory("hitListService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var HitListService = function() {};
            HitListService.prototype = new APIService({
                transformAPISuccess: _convertResponseToList
            });

            // Extend the prototype with any class-specific functionality
            angular.extend(HitListService.prototype, {

                /**
                 * Get a list of mod_security rule hits that match the selection criteria passed in meta parameter
                 * @param {object} meta Optional meta data to control sorting, filtering and paging
                 *   @param {string} meta.sortBy Name of the field to sort by
                 *   @param {string} meta.sordDirection asc or desc
                 *   @param {string} meta.sortType Optional name of the sort rule to apply to the sorting
                 *   @param {string} meta.filterBy Name of the filed to filter by
                 *   @param {string} meta.filterCompare Optional comparator to use when comparing for filter.
                 *   If not provided, will default to ???.
                 *   May be one of:
                 *       TODO: Need a list of valid filter types.
                 *   @param {string} meta.filterValue  Expression/argument to pass to the compare method.
                 *   @param {string} meta.pageNumber Page number to fetch.
                 *   @param {string} meta.pageSize Size of a page, will default to 10 if not provided.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchList: function fetchList(meta) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_log");
                    if (meta) {
                        if (meta.sortBy && meta.sortDirection) {
                            apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                        }
                        if (meta.pageNumber) {
                            apiCall.addPaging(meta.pageNumber, meta.pageSize || 10);
                        }
                        if (meta.filterBy && meta.filterValue) {
                            apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                        }
                    }

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Retrieve an individual hit from the unique hit ID, which is the primary key in the modsec.hits table.
                 *
                 * @method fetchById
                 * @param  {[type]} hitId [description]
                 * @return {[type]}       [description]
                 */
                fetchById: function fetchById(hitId) {
                    var promise = this.fetchList({
                        filterBy: "id",
                        filterValue: hitId,
                        filterCompare: "eq"
                    }).then(function(response) {

                        // Check the length of the results to make sure we only have one hit
                        var length = response.items.length;

                        if (length === 1) {
                            return response;
                        } else if (length > 1) {
                            return $q.reject({
                                message: LOCALE.maketext("More than one hit matched hit ID “[_1]”.", hitId),
                                count: length
                            });
                        } else {
                            return $q.reject({
                                message: LOCALE.maketext("No hits matched ID “[_1]”.", hitId),
                                count: length
                            });
                        }
                    });

                    return promise;
                },

                /**
                *  Helper method that calls convertResponseToList to prepare the data structure
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function prepareList(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return _convertResponseToList(response);
                }

            });

            return new HitListService();

        }]);
    }
);

/*
# mod_security/services/ruleService.js            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/ruleService',[

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/util/locale",
        "cjt/util/parse",

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST, APIDRIVER, LOCALE, PARSE) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        // CONSTANTS

        // Directive chunks. - The API returns complete directive chunks, so page by chunks.  This was
        //    selected arbitrary. Revise if we seem to be making too many requests.
        var NUMBER_OF_DIRECTIVES_PER_BATCH = 500;

        // Lines - To limit the need for a smart record parser, the UI just breaks up the batch by lines for saving.
        //    Since chunks are often made up of 2 to 3 lines, to make the load and save fairly balanced, batch by
        //    3 x the number of directives. Not guaranteed to match, but on average not a bad guess.
        var NUMBER_OF_LINES_PER_BATCH = 3 * NUMBER_OF_DIRECTIVES_PER_BATCH;

        var LINE_REGEX = /\n/g; // Match expression used to break up the text into line buffers.

        /**
         * Setup the rule models API service
         */
        app.factory("ruleService", ["$q", "APIService", function($q, APIService) {

            /**
             * Normalize the rule to account for any missing data, etc.
             *
             * @method normalizeRule
             * @private
             * @param  {Object} rule Rule returned from the server.
             * @return {Object}      Rule with all the fields normalized and patched.
             */
            function normalizeRule(rule) {
                rule.config_active = PARSE.parsePerlBoolean(rule.config_active);
                rule.disabled      = PARSE.parsePerlBoolean(rule.disabled);
                rule.staged        = PARSE.parsePerlBoolean(rule.staged);
                rule.vendor_active = PARSE.parsePerlBoolean(rule.vendor_active);
                return rule;
            }

            /**
             * Converts the response to our application data structure
             *
             * @method convertResponseToList
             * @private
             * @param  {Object} response
             * @return {Object} Sanitized data structure.
             */
            function convertResponseToList(response) {
                var items = [];
                if (response.status) {
                    var data = response.data.chunks;
                    for (var i = 0, length = data.length; i < length; i++) {
                        items.push(normalizeRule(data[i]));
                    }

                    var meta = response.meta;

                    var totalItems = meta.paginate.total_records || data.length;
                    var totalPages = meta.paginate.total_pages || 1;

                    return {
                        items: items,
                        stagedChanges: PARSE.parsePerlBoolean(response.data.staged_changes),
                        totalItems: totalItems,
                        totalPages: totalPages,
                        status: response.status
                    };
                } else {
                    return {
                        items: [],
                        stagedChanges: false,
                        totalItems: 0,
                        totalPages: 0,
                        status: response.status
                    };
                }
            }

            /**
             * Disable a rule.
             *
             * @method _disableRule
             * @private
             * @param  {Deferred} deferred
             * @param  {String}   config    Config file for rule
             * @param  {Number}   id        Rule id.
             * @param  {Boolean}  deploy    if true, will deploy the change, if false will only stage the change.
             * @param  {Object}   payload   optional payload to pass to resolve.
             * @return {Promise}
             */
            var _disableRule = function(deferred, config, id, deploy, payload) {

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "modsec_disable_rule");
                apiCall.addArgument("config", config);
                apiCall.addArgument("id", id);

                this.deferred(apiCall, {
                    context: this,
                    done: function(response) {

                        deferred.notify(LOCALE.maketext("You have successfully disabled the rule."));

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {

                            // Update the payload if exists
                            if (payload) {
                                payload.disabled = true;
                            }

                            // Move to the next step.
                            if (deploy) {
                                _deployRules.call(this, deferred, payload);
                            } else {

                                // keep the promise
                                deferred.resolve(payload);
                            }
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    }
                },
                deferred);

                // pass the promise back to the controller
                return deferred.promise;
            };

            /**
             * Enable a rule.
             *
             * @method _enabledRule
             * @private
             * @param  {Deferred} deferred
             * @param  {String} config     Config file for rule
             * @param  {Number} id         Rule id
             * @param  {Boolean} deploy    if true, will deploy the change, if false will only stage the change.
             * @param  {Object}   payload    optional payload to pass to resolve.
             * @return {Promise}
             */
            var _enableRule = function(deferred, config, id, deploy, payload) {

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "modsec_undisable_rule");
                apiCall.addArgument("config", config);
                apiCall.addArgument("id", id);

                this.deferred(apiCall, {
                    context: this,
                    done: function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.notify(LOCALE.maketext("You have successfully enabled the rule."));

                            // Update the payload if it exists
                            if (payload) {
                                payload.disabled = false;
                            }

                            // Move on to the next step.
                            if (deploy) {
                                _deployRules.call(this, deferred, payload);
                            } else {

                                // keep the promise
                                deferred.resolve(payload);
                            }
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    }
                },
                deferred);

                // pass the promise back to the controller
                return deferred.promise;
            };

            /**
             * Deploy staged rules.
             *
             * @method _deployRule
             * @private
             * @param  {Deferred} deferred
             * @param  {Object}   payload    optional payload to pass to resolve.
             * @return {Promise}
             */
            var _deployRules = function(deferred, payload) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "modsec_deploy_all_rule_changes");

                this.deferred(apiCall, {
                    apiSuccess: function(response) {
                        deferred.notify(LOCALE.maketext("You have successfully deployed the staged rules to your custom [asis,ModSecurity™] configuration."));
                        deferred.resolve(payload);
                    }
                }, deferred);

                // pass the promise back to the controller
                return deferred.promise;
            };

            // Set up the service's constructor and parent
            var RulesService = function() {};
            RulesService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(RulesService.prototype, {

                /**
                 * Get a list of custom mod_security rules that match the selection criteria passed in the meta parameter.
                 * At least one of the optional parameters must be provided as an argument.
                 *
                 * @method fetchRulesList
                 * @param {string} [vendorList] Optional array of one or more vendor ID strings.
                 * @param {object} [meta] Optional meta data to control sorting, filtering and paging
                 *   @param {string} meta.sortBy Name of the field to sort by
                 *   @param {string} meta.sordDirection asc or desc
                 *   @param {string} meta.sortType Optional name of the sort rule to apply to the sorting
                 *   @param {string} meta.filterBy Name of the filed to filter by
                 *   @param {string} meta.filterCompare Optional comparator to use when comparing for filter.
                 *   @param {string} meta.filterValue  Expression/argument to pass to the compare method.
                 *   @param {string} meta.pageNumber Page number to fetch.
                 *   @param {string} meta.pageSize Size of a page, will default to 10 if not provided.
                 *   @param {boolean} meta.advanced.showStagedDeployed
                 *   @param {boolean} meta.advanced.showEnabledDisabled
                 *   @param {boolean} meta.advanced.includeUserRules
                 * @return {Promise} Promise that will fulfill the request.
                 * @throws Error
                 */
                fetchRulesList: function(vendorList, meta) {
                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize(NO_MODULE, "modsec_get_rules");
                    if (vendorList && vendorList.length) {

                        // Make the vendorList comma delimmited for the back-end
                        apiCall.addArgument("vendor_id", vendorList.join(","));
                    }

                    // Make sure we have something to do before going further
                    if ((!vendorList || !vendorList.length) && meta && meta.advanced && !angular.isDefined(meta.advanced.includeUserRules)) {
                        throw new Error("No vendor selected and user-defined rules were not requested. There is nothing to fetch.");
                    }

                    apiCall.addArgument("exclude_other_directives", 1);
                    apiCall.addArgument("exclude_bare_comments", 1);

                    if ( !angular.isDefined(meta.advanced.includeUserRules) ) {
                        apiCall.addFilter("vendor_active", "eq", 1); // modsec2.user.conf will have these fields forced to true
                        apiCall.addFilter("config_active", "eq", 1);
                    }

                    if (meta && meta.advanced) {
                        if (meta.advanced.showStagedDeployed === "staged") {
                            apiCall.addFilter("staged", "eq", 1);
                        }

                        if (meta.advanced.showStagedDeployed === "deployed") {
                            apiCall.addFilter("staged", "eq", 0);
                        }

                        if (meta.advanced.showEnabledDisabled === "enabled") {
                            apiCall.addFilter("disabled", "eq", 0);
                        }

                        if (meta.advanced.showEnabledDisabled === "disabled") {
                            apiCall.addFilter("disabled", "eq", 1);
                        }

                        if (meta.advanced.includeUserRules) {

                            // Fetch the rules from the user's custom config as well
                            apiCall.addArgument("config", "modsec2.user.conf"); /* TODO: EA-4700 */
                        }
                    }

                    if (meta) {
                        if (meta.sortBy && meta.sortDirection) {
                            apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                        }
                        if (meta.pageNumber) {
                            apiCall.addPaging(meta.pageNumber, meta.pageSize || 10);
                        }
                        if (meta.filterBy && meta.filterCompare && meta.filterValue) {
                            apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                        }
                    }

                    var deferred = this.deferred(apiCall, {
                        transformAPISuccess: convertResponseToList
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Get a single rule by its id from the backend.
                 *
                 * @method fetchRulesById
                 * @param {Number} ruleId       Id of the rule to fetch.
                 * @param {String} [vendorId]   The unique vendor ID for the containing rule set.
                 *                              If this is not included, the user-defined rule set will be searched.
                 * @return {Promise}            Promise that will fulfill the request.
                 */
                fetchRulesById: function(ruleId, vendorId) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_rules");
                    apiCall.addArgument("exclude_other_directives", 1);
                    apiCall.addArgument("exclude_bare_comments", 1);
                    apiCall.addFilter("id", "==", ruleId);

                    // If a vendor string was passed, use that as the vendor ID.
                    // Otherwise, use the user-defined config.
                    if (typeof vendorId === "string") {
                        apiCall.addArgument("vendor_id", vendorId);
                    } else {
                        apiCall.addArgument("config", "modsec2.user.conf"); /* TODO: EA-4700 */
                    }

                    // Don't add the filtering here that requires the vendor and config to be active
                    // because if someone is specifically picking a rule out by id, they probably want
                    // it regardless of those other conditions.

                    var deferred = this.deferred(apiCall, {
                        apiSuccess: function(response, deferred) {
                            response = convertResponseToList(response);
                            var length = response.items.length;

                            if (length === 1) {
                                deferred.resolve(response);
                            } else {
                                deferred.reject({ count: length });
                            }
                        },
                        transformAPIFailure: function(response) {
                            return { message: response.error };
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Get all custom rules as a single text block for mass edit
                 *
                 * @method getCustomConfigText
                 * @return {Promise} Promise that will fulfill the request.
                 */
                getCustomConfigText: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_config_text");
                    apiCall.addArgument("config", "modsec2.user.conf"); /* TODO: EA-4700 */
                    apiCall.addArgument("pagable", 1);
                    apiCall.addPaging(1, NUMBER_OF_DIRECTIVES_PER_BATCH);

                    var that = this;
                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function(response, deferred) {
                            deferred.notify({ text: response.data, type: "page", page: 1 });

                            var meta = response.meta;
                            var totalPages = meta.paginate.total_pages || 1;

                            if (totalPages > 1) {
                                var promise = $q.all({});

                                /**
                                 * Build a function that returns a promise for a specific page of data
                                 * @param  {Number} page Page # to retrieve.
                                 * @return {Promise}
                                 */
                                var pageRequestFactory = function(page) {
                                    return function() {
                                        apiCall.addPaging(page, NUMBER_OF_DIRECTIVES_PER_BATCH);
                                        return that.deferred(apiCall, {
                                            apiSuccess: function(response) {
                                                deferred.notify({ text: response.data, type: "page", page: page, totalPages: totalPages });
                                            },
                                            apiFailure: function(response) {
                                                deferred.notify({ type: "error", error: response.error });
                                            }
                                        },
                                        deferred);
                                    };
                                };

                                for (var page = 2; page <= totalPages; page++) {

                                    // build the promise chain for page 2 to n
                                    promise = promise.then(pageRequestFactory(page));
                                }
                                promise.finally(function() {
                                    deferred.resolve();
                                });
                            } else {
                                deferred.notify({ text: response.data.text, type: "page", page: 1, totalPages: 1, done: true });
                                deferred.resolve();
                            }
                        },
                        apiFailure: function(response) {
                            deferred.notify({ type: "error", error: response.error });
                            deferred.reject();
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Sets the contents of the user defined configuration file
                 *
                 * @method setCustomConfigText
                 * @param {String} text The contents of the configuration file to be set
                 @param {Boolean} deploy   If true, will deploy the rule, if false will only save the rule to the staging file.
                 * @return {Promise}
                 */
                setCustomConfigText: function(text, deploy) {

                    // Splits the text into array of equal parts
                    var lines = text.split(LINE_REGEX);
                    var lineCount = lines.length;
                    var sections = [];
                    for (var i = 0; i < lineCount; i += NUMBER_OF_LINES_PER_BATCH ) {
                        sections.push(lines.slice(i, i + NUMBER_OF_LINES_PER_BATCH).join("\n"));
                    }

                    var pages = sections.length;

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_assemble_config_text");
                    apiCall.addArgument("config", "modsec2.user.conf"); /* TODO: EA-4700 */
                    apiCall.addArgument("text", sections[0]);
                    apiCall.addArgument("init", 1);
                    if (pages === 1) {
                        apiCall.addArgument("final", 1);
                        if (deploy) {
                            apiCall.addArgument("deploy", 1);
                        }
                    }

                    var that = this;
                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function(response, deferred) {
                            if (pages > 1) {

                                // We don't need it for the rest of the pages
                                apiCall.removeArgument("init");
                                var promise = $q.all({});

                                /**
                                 * Build a function that returns a promise for a specific page of data
                                 *
                                 * @name pagePostFactory
                                 * @private
                                 * @param  {Number} page Section of the data to post to the server.
                                 * @param {Boolean} done If true add the final argument. Otherwise don't.
                                 * @param {Boolean} deploy If true deploy the changes, saving another api call. yeah. Otherwise don't. Ignored unless done is also true.
                                 * @return {Promise}
                                 */
                                var pagePostFactory = function(page, done, deploy) {
                                    return function() {
                                        apiCall.addArgument("text", sections[page]);
                                        if (done) {
                                            apiCall.addArgument("final", 1);
                                            if (deploy) {
                                                apiCall.addArgument("deploy", 1);
                                            }
                                        }

                                        return that.deferred(apiCall, {
                                            apiSuccess: function(response) {
                                                deferred.notify({ text: response.data, type: "post", page: page, totalPages: pages });
                                            },
                                            apiFailure: function(response) {

                                                // TODO: Need to clean up the partly assembled item?
                                                deferred.notify({ type: "error", error: response.error });
                                                deferred.reject();
                                            }
                                        },
                                        deferred);
                                    };
                                };

                                // sections[0] already sent, so send the rest
                                for (var page = 1; page < pages; page++) {

                                    // build the promise chain for page 2 to n
                                    var done = (page === pages - 1);
                                    promise = promise.then(pagePostFactory(page, done, deploy));
                                }
                                promise.finally(function() {

                                    // keep the promise
                                    deferred.resolve();
                                });
                            } else {

                                // keep the promise
                                deferred.resolve();
                            }
                        },
                        apiFailure: function(response, deferred) {
                            if ( response.data ? PARSE.parsePerlBoolean(response.data.duplicate) : false ) {
                                if (deploy) {
                                    _deployRules.call(this, deferred);
                                } else {

                                    // ignore the duplicate edit, keep the promise
                                    deferred.resolve();
                                }
                            } else {

                                // pass the error along
                                deferred.notify({ type: "error", error: response.error });
                                deferred.reject();
                            }
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Add a rule and optionally disable and optionally deploy it.
                 *
                 * @method addRule
                 * @param {Strring} ruleText Proposed multi-line modsec2 SecAction or SecRule to add to the staging file.
                 * @param {Boolean} enabled  If true, will save the rule as enabled, if false will save the rule a disabled.
                 * @param {Boolean} deploy   If true, will deploy the rule, if false will only save the rule to the staging file.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                addRule: function(ruleText, enabled, deploy) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_add_rule");
                    apiCall.addArgument("config", "modsec2.user.conf"); /* TODO: EA-4700 */
                    apiCall.addArgument("rule", ruleText);

                    this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function(response) {
                            var rule = normalizeRule(response.data.rule);
                            deferred.notify(LOCALE.maketext("You have successfully added the rule to the staged configuration file."));
                            if (!enabled) {
                                _disableRule.call(this, deferred, rule.config, rule.id, deploy, rule);
                            } else if (deploy) {
                                _deployRules.call(this, deferred, rule);
                            } else {

                                // keep the promise
                                deferred.resolve(rule);
                            }
                        },
                        apiFailure: function(response) {
                            var error = {
                                message: response.error,
                                duplicate: response.data ? PARSE.parsePerlBoolean(response.data.duplicate) : false
                            };
                            deferred.reject(error);
                        }
                    }, deferred);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Clone a rule returning the rule with a unique id.
                 *
                 * @method cloneRule
                 * @param {String} id Original rule id
                 * @param {String} config  Original rule configuration file
                 * @return {Promise} Promise that will fulfill the request.
                 */
                cloneRule: function(id, config) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_clone_rule");
                    apiCall.addArgument("id", id);
                    apiCall.addArgument("config", config);

                    var deferred = this.deferred(apiCall, {
                        transformAPISuccess: function(response) {
                            return normalizeRule(response.data.rule);
                        },
                        transformAPIFailure: function(response) {
                            return {
                                message: response.error,
                                duplicate: response.data ? PARSE.parsePerlBoolean(response.data.duplicate) : false
                            };
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Delete a rule by its id
                 *
                 * @method deleteRule
                 * @param  {Number} ruleId Rule id to delete.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                deleteRule: function(ruleId) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_remove_rule");
                    apiCall.addArgument("config", "modsec2.user.conf"); /* TODO: EA-4700 */
                    apiCall.addArgument("id", ruleId);

                    var deferred = this.deferred(apiCall);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Update an existing rule... not much different than add
                 *
                 * @method updateRule
                 * @param {String} configFile        The config file housing the rule.
                 * @param {String} ruleText          Proposed multi-line modsec2 SecAction or SecRule to update
                 * @param {Boolean} enabled          If true, will save the rule as enabled, if false will save the rule a disabled.
                 * @param {Boolean} enabledChanged   If true, then set the enabled state to the requested enabled value.
                 * @param {Boolean} deploy           If true, will deploy the rule, if false will only save the rule to the staging file.
                 */
                updateRule: function(configFile, ruleId, ruleText, enabled, enabledChanged, deploy) {

                    // make a promise
                    var deferred = $q.defer();
                    var apiCall = new APIREQUEST.Class();

                    /**
                     * Proxies to enable, disable, and deploy as needed
                     *
                     * @method _toggleAndDeploy
                     * @private
                     * @param  {Boolean} deploy   If true, deploy and restart Apache.
                     * @param  {Object} [rule]    Optional rule object to use as the payload for the promise.
                     */
                    var _toggleAndDeploy = function _toggleAndDeploy(deploy, rule) {
                        if (enabledChanged) {
                            if (enabled) {
                                _enableRule.call(this, deferred, configFile, rule.id, deploy, rule);
                            } else {
                                _disableRule.call(this, deferred, configFile, rule.id, deploy, rule);
                            }
                        } else if (deploy) {
                            _deployRules.call(this, deferred, rule);
                        } else {
                            deferred.resolve(rule);
                        }
                    }.bind(this);

                    // We're updating a user-defined rule so they can edit the text and everything.
                    if (configFile.match(/modsec2.user.conf$/)) { /* TODO: EA-4700 */
                        apiCall.initialize(NO_MODULE, "modsec_edit_rule");
                        apiCall.addArgument("config", configFile);
                        apiCall.addArgument("id", ruleId);
                        apiCall.addArgument("rule", ruleText);

                        this.deferred(apiCall, {
                            context: this,
                            apiSuccess: function(response) {
                                var rule = normalizeRule(response.data.rule);
                                deferred.notify(LOCALE.maketext("You have successfully updated the rule in the staged configuration file."));
                                _toggleAndDeploy(deploy, rule);
                            },
                            apiFailure: function(response) {
                                var error = {
                                    message: response.error,
                                    duplicate: response.data ? PARSE.parsePerlBoolean(response.data.duplicate) : false
                                };
                                deferred.reject(error);
                            }
                        },
                        deferred);
                    } else {

                        // We're updating a vendor rule so the only thing they can do is enable, disable, and deploy.
                        _toggleAndDeploy(deploy, {
                            id: ruleId,
                            config: configFile,
                            rule: ruleText
                        });
                    }

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Disable a rule by id and optionally deploy it
                 *
                 * @method disableRule
                 * @param  {String}  config File rule is contained within.
                 * @param  {Number}  id     Rule id.
                 * @param  {Boolean} deploy if true, will deploy the change, if false will only stage the change.
                 * @return {Promise}
                 */
                disableRule: function(config, id, deploy) {

                    // make a promise
                    var deferred = $q.defer();

                    // pass the promise back to the controller
                    return _disableRule.call(this, deferred, config, id, deploy);
                },

                /**
                 * Enable a rule by id and optionally deploy it
                 *
                 * @method enableRule
                 * @param  {String}  config File rule is contained within.
                 * @param  {Number} id [description]
                 * @param  {Boolean} deploy if true, will deploy the change, if false will only stage the change.
                 * @return {Promise}
                 */
                enableRule: function(config, id, deploy) {

                    // make a promise
                    var deferred = $q.defer();

                    // pass the promise back to the controller
                    return _enableRule.call(this, deferred, config, id, deploy);
                },

                /**
                 * Deploy the queued rules if any exist
                 *
                 * @method deployQueuedRules
                 * @return {Promise}
                 */
                deployQueuedRules: function() {

                    // make a promise
                    var deferred = $q.defer();
                    return _deployRules.call(this, deferred);
                },

                /**
                 * Discard the queue rules if any exist
                 *
                 * @method discardQueuedRules
                 * @return {Promise}
                 */
                discardQueuedRules: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_discard_all_rule_changes");

                    var deferred = this.deferred(apiCall);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                *  Helper method that calls convertResponseToList to prepare the data structure
                *
                * @method  prepareList
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return convertResponseToList(response);
                }
            });

            return new RulesService();
        }]);
    }
);

/*
# mod_security/services/reportService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/reportService',[

        // Libraries
        "angular",

        // CJT
        "cjt/util/locale",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService",

        // Feature-specific
        "app/services/hitlistService",
        "app/services/ruleService"
    ],
    function(angular, LOCALE, APIREQUEST) {

        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        /**
         * This service uses the ruleService and hitListService to allow for better front-end
         * visualization of the relationships between hits and rules. Using setHit or setRule
         * will return a promise that will resolve with a report object, which is just a
         * conglomerate object of related rules and hits. The two methods differ slightly in
         * their output and more information is provided in their documentation blocks.
         */
        app.factory("reportService", [
            "$q",
            "APIService",
            "ruleService",
            "hitListService",
            function(
                $q,
                APIService,
                ruleService,
                hitListService
            ) {

                var currentReport; // Will be a promise

                /**
                 * Extracts the vendor id from a config file path.
                 *
                 * @method _getVendorFromFile
                 * @private
                 * @param  {String} file   The full file path to the config file.
                 *
                 * @return {String}        The vendor id if it's a vendor config or undefined if we
                 *                         can't parse the file path properly.
                 */
                function _getVendorFromFile(file) {
                    var VENDOR_REGEX = /\/modsec_vendor_configs\/(\w+)/;

                    var match = file && file.match(VENDOR_REGEX);
                    return match ? match[1] : void 0;
                }

                /**
                 * Given a unique hit ID (the id column from modsec.hits) or an actual hit object,
                 * this method will kick off a promise chain that will package together the full
                 * hit object along with its associated rule. The resolved report object from this
                 * method will differ from the report object provided by the setRule promise in
                 * that it will ONLY include the hit given as an argument.
                 *
                 * @method setHit
                 * @param  {String|Number|Object} hit   Either a bare hit ID or a hit object
                 *
                 * @return {Promise}                    This promise will resolve with a report object,
                 *                                      which essentially just packages a rule object
                 *                                      with an array of associated hits. For this
                 *                                      method, there will only be one hit in the array.
                 */
                function fetchByHit(hit) {
                    var fetched = {}; // This will house the eventual response
                    var hitPromise;

                    if (!angular.isObject(hit)) {

                        // This is a bare hitId so we need to fetch the actual hit object first
                        hitPromise = hitListService.fetchById(hit)
                            .then(function(response) {
                                fetched.hits = response.items;
                                return response.items[0]; // This length is guaranteed by the hitListService
                            });
                    } else {

                        // We already have the hit object, so just wrap it in an array and a promise
                        fetched.hits = [hit];

                        var deferred = $q.defer();
                        deferred.resolve(hit);
                        hitPromise = deferred.promise;
                    }

                    currentReport = hitPromise.then(function(hit) {

                        // Reports only work with vendors right now, so check that this is a vendor rule
                        var vendor = _getVendorFromFile(hit.meta_file);
                        if (!vendor) {
                            return $q.reject( LOCALE.maketext("You can only report [asis,ModSecurity] rules that a vendor provided.") );
                        }

                        // Fetch the rule
                        return ruleService.fetchRulesById(hit.meta_id, vendor);
                    }).then(function(response) {
                        fetched.rule = response.items[0]; // The length is guaranteed by the ruleService
                        return fetched;
                    });

                    return currentReport;
                }


                /**
                 * Given a unique rule ID or an actual rule object, this method will kick off a promise
                 * chain that will package together the full rule object along with any associated hits.
                 * The resolved report object from this method will differ from the report object
                 * provided by the setHit promise in that it will include ALL hits associated with the
                 * rule argument.
                 *
                 * @method setRule
                 * @param  {String|Number|Object} rule     Either a rule ID or a rule object
                 * @param  {String}               vendor   A vendor ID string
                 *
                 * @return {Promise}                       This promise will resolve with a report object,
                 *                                         which essentially just packages a rule object
                 *                                         with an array of associated hits.
                 */
                function fetchByRule(rule, vendor) {
                    var fetched = {};
                    var rulePromise;

                    if (!angular.isObject(rule)) { // This is a bare ruleId so we need to fetch the actual rule object first
                        // Reports only work with vendors right now, so check that one was provided
                        if (!vendor) {
                            return $q.reject( LOCALE.maketext("You can only report [asis,ModSecurity] rules that a vendor provided.") );
                        }

                        rulePromise = ruleService.fetchRulesById(rule, vendor).then(function(response) {
                            fetched.rule = response.items[0]; // The length is guaranteed by the ruleService
                            return fetched.rule;
                        });
                    } else { // We already have the rule object, so just wrap it in a promise

                        // Reports only work with vendors, so check that one was provided
                        if (!rule.vendor_id) {
                            return $q.reject( LOCALE.maketext("Only [asis,ModSecurity] rules provided by vendors may be reported.") );
                        }

                        fetched.rule = rule;

                        var deferred = $q.defer();
                        deferred.resolve(rule);
                        rulePromise = deferred.promise;
                    }

                    currentReport = rulePromise.then(function(rule) {
                        return hitListService.fetchList({
                            filterBy: "meta_id",
                            filterValue: rule.id,
                            filterCompare: "eq"
                        });
                    }).then(function(response) {
                        fetched.hits = response.items;
                        return fetched;
                    });

                    return currentReport;
                }

                /**
                 * Returns the current report promise. This is useful when changing views/controllers.
                 *
                 * @method getCurrent
                 * @return {Promise}   Either undefined if there is no current report promise,
                 *                     or a promise that will resolve with a report object,
                 *                     which essentially just packages a rule object with an
                 *                     array of associated hits.
                 */
                function getCurrent() {
                    return currentReport;
                }

                /**
                 * Unsets the current report so that it doesn't become stale.
                 * @method clearCurrent
                 */
                function clearCurrent() {
                    currentReport = void 0;
                }

                /**
                 * Generates a report but doesn't send it.
                 *
                 * @method viewReport
                 * @param  {Object} reportParams   See _generateReport documentation
                 *
                 * @return {Promise}
                 */
                function viewReport(reportParams) {
                    reportParams.send = false;
                    return _generateReport.call(this, reportParams);
                }

                /**
                 * Generates a report and sends it. Optionally disables the rule as well.
                 *
                 * @method sendReport
                 * @param  {Object} reportParams      See _generateReport documentation
                 * @param  {Object} [disableParams]   A set of params required for disabling the rule.
                 *     @param {Number}  disableParams.ruleId        The id of the rule to be disabled.
                 *     @param {Boolean} disableParams.deployRule    Should the disable change be deployed?
                 *     @param {String}  disableParams.ruleConfig    The path of the config file housing the rule.
                 *
                 * @return {Promise}                  Resolves when both operations are complete (or just the report, if no disableParams were given)
                 */
                function sendReport(reportParams, disableParams) {
                    var promises = {};

                    reportParams.send = true;
                    promises.report = _generateReport.call(this, reportParams);

                    if (disableParams) {
                        promises.disable = ruleService.disableRule(disableParams.ruleConfig, disableParams.ruleId, disableParams.deployRule);
                    }

                    return $q.all(promises);
                }

                /**
                 * Uses the modsec_report_rule API to either send a report or only perform a dry
                 * run and generate what would be sent without actually sending the payload.
                 *
                 * @method _generateReport
                 * @param  {Object}  params           Contains the key/value pairs for the parameters that will be passed with the API call.
                 * @param  {Array}   params.hits      An array of hit IDs that correspond to the id column in the modsec.hits table.
                 * @param  {String}  params.message   A short message to accompany the report.
                 * @param  {String}  params.email     The sender's email address.
                 * @param  {String}  params.reason    The reason for which the report is being submitted.
                 * @param  {Boolean} params.send      If true, the generated report will be sent by the API.
                 *
                 * @return {Promise}                  Resolves with the raw JSON generated by the API.
                 */
                function _generateReport(params) {

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_report_rule");

                    angular.forEach({
                        row_ids: params.hits.join(","),
                        message: params.message,
                        email: params.email,
                        type: params.reason,
                        send: params.send ? 1 : 0
                    }, function(val, key) {
                        apiCall.addArgument(key, val);
                    });

                    return this.deferred(apiCall, {
                        transformAPISuccess: _extractReport
                    }).promise;
                }

                /**
                 * Extracts the report object from the response.
                 * @param  {Object} response   The response from the API.
                 * @return {Object}            The report object.
                 */
                function _extractReport(response) {
                    return response.data.report;
                }


                // Set up the service's constructor and parent
                var ReportService = function() {};
                ReportService.prototype = new APIService();

                // Extend the prototype with any class-specific functionality
                angular.extend(ReportService.prototype, {
                    fetchByHit: fetchByHit,
                    fetchByRule: fetchByRule,
                    getCurrent: getCurrent,
                    clearCurrent: clearCurrent,
                    viewReport: viewReport,
                    sendReport: sendReport
                });

                return new ReportService();
            }
        ]);
    }
);

/*
# templates/mod_security/views/hitlistController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/hitListController',[
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/responsiveSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/hitlistService",
        "app/services/reportService"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller("hitListController", [
            "$scope",
            "$location",
            "$anchorScroll",
            "$routeParams",
            "$timeout",
            "hitListService",
            "alertService",
            "reportService",
            "spinnerAPI",
            "PAGE",
            function(
                $scope,
                $location,
                $anchorScroll,
                $routeParams,
                $timeout,
                hitListService,
                alertService,
                reportService,
                spinnerAPI,
                PAGE
            ) {

                $scope.loadingPageData = true;
                $scope.activeSearch = false;
                $scope.filteredData = false;
                $scope.selectedRow = -1;
                $scope.showAddSuccess = false;

                /**
                 * Extracts the vendor id from a config file path.
                 *
                 * @method _getVendorFromFile
                 * @private
                 * @param  {String} file   The full file path to the config file.
                 * @return {String}        The vendor id if it's a vendor config or undefined if we
                 *                         can't parse the file path properly.
                 */
                function _getVendorFromFile(file) {
                    var VENDOR_REGEX = /\/modsec_vendor_configs\/+([^/]+)/; /* TODO: EA-4700 */
                    var match = file && file.match(VENDOR_REGEX);
                    return match ? match[1] : void 0;
                }

                /**
                 * Checks to see if the given config file is the user config file.
                 *
                 * @method _isUserConfigFile
                 * @private
                 * @param  {String}  file   The full file path to the config file.
                 * @return {Boolean}        True if it is the user config file.
                 */
                function _isUserConfigFile(file) {
                    var USER_CONF_REGEX = /\/modsec2\.user\.conf$/; /* TODO: EA-4700 */
                    return USER_CONF_REGEX.test( file );
                }

                /**
                 * Passes the hit object to the report service to save a fetch and loads the view.
                 *
                 * @method loadReportview
                 * @param  {Object} hit   A hit object that corresponds to a single row from the modsec.hits table.
                 */
                $scope.loadReportView = function(hit) {
                    reportService.fetchByHit(hit);
                    $scope.loadView("report/hit/" + hit.id);
                };

                /**
                 * Load the edit rule view with the  requested rule.
                 *
                 * @method loadEditRuleView
                 * @param  {Number} ruleId
                 */
                $scope.loadEditRuleView = function(ruleId, file) {
                    var viewParams = {
                        ruleId: ruleId,
                        back: "hitList"
                    };
                    var vendorId;

                    if (_isUserConfigFile(file)) {
                        $scope.loadView("editCustomRule", viewParams);
                    } else if ( (vendorId = _getVendorFromFile(file)) ) { // Extra parens needed for jshint: http://www.jshint.com/docs/options/#boss
                        viewParams.vendorId = vendorId;
                        $scope.loadView("editCustomRule", viewParams);
                    } else {
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("An unknown error occurred in the attempt to retrieve the rule."),
                            id: "errorFetchRule"
                        });
                    }
                };

                /**
                 * Clear the search query
                 */
                $scope.clearFilter = function() {
                    $scope.meta.filterValue = "";
                    $scope.activeSearch = false;
                    $scope.filteredData = false;

                    // Leave history so refresh works
                    $location.search("api.filter.enable", 0);
                    $location.search("api.filter.verbose", null);
                    $location.search("api.filter.a.field", null);
                    $location.search("api.filter.a.type", null);
                    $location.search("api.filter.a.arg0", null);

                    // select the first page of search results
                    return $scope.selectPage(1);
                };

                /**
                 * Start a search query
                 */
                $scope.startFilter = function() {
                    $scope.activeSearch = true;
                    $scope.filteredData = false;

                    // Leave history so refresh works
                    $location.search("api.filter.enable", 1);
                    $location.search("api.filter.verbose", 1);
                    $location.search("api.filter.a.field", "*");
                    $location.search("api.filter.a.type", "contains");
                    $location.search("api.filter.a.arg0", $scope.meta.filterValue);

                    // Select the first page of search results
                    $scope.selectPage(1);
                    $scope.filteredData = true;
                };

                /**
                 * Selects a table row
                 * @param  {Number} index The index of selected row
                 */
                $scope.toggleRow = function(index) {
                    if ( index === $scope.selectedRow ) {

                        // collapse the row
                        $scope.selectedRow = -1;

                    } else {

                        // expand the selected row
                        $scope.selectedRow = index;
                    }

                };

                /**
                 * Select a specific page
                 * @param  {Number} [page] Optional page number, if not provided will use the current
                 * page provided by the scope.meta.pageNumber.
                 * @return {Promise}
                */
                $scope.selectPage = function(page) {

                    // clear the selected row
                    $scope.selectedRow = -1;

                    // set the page if requested
                    if (page && angular.isNumber(page)) {
                        $scope.meta.pageNumber = page;
                    }

                    // Leave history so refresh works
                    $location.search("api.chunk.enable", 1);
                    $location.search("api.chunk.verbose", 1);
                    $location.search("api.chunk.size", $scope.meta.pageSize);
                    $location.search("api.chunk.start", ( ($scope.meta.pageNumber - 1) * $scope.meta.pageSize) + 1);

                    return $scope.fetch();
                };

                /**
                 * Sort the list of hits
                 * @param {String} sortBy Field name to sort by.
                 * @param {String} sortDirection Direction to sort by: asc or decs
                 * @param {String} [sortType] Optional sort type applied to the field. Sort type is lexical by default.
                 */
                $scope.sortList = function(meta, defaultSort) {

                    // clear the selected row
                    $scope.selectedRow = -1;

                    // Leave history so refresh works
                    $location.search("api.sort.enable", 1);
                    $location.search("api.sort.a.field", meta.sortBy);
                    $location.search("api.sort.a.method", meta.sortType || "");
                    $location.search("api.sort.a.reverse", meta.sortDirection === "asc" ? 0 : 1);

                    if (!defaultSort) {
                        $scope.fetch();
                    }
                };

                /**
                 * Handles the keybinding for the clearing and searching.
                 * Esc clears the search field.
                 * Enter performs a search.
                 *
                 * @method triggerToggleSearch
                 * @param {Event} event - The event object
                 */
                $scope.triggerToggleSearch = function(event) {

                    // clear on Esc
                    if (event.keyCode === 27) {
                        $scope.toggleSearch(true);
                    }

                    // filter on Enter
                    if (event.keyCode === 13) {
                        $scope.toggleSearch();
                    }
                };

                /**
                 * Toggles the clear button and conditionally performs a search.
                 * The expected behavior is if the user clicks the button or focuses the button and hits enter the button state rules.
                 *
                 * @param {Boolean} isClick Toggle button clicked.
                 */
                $scope.toggleSearch = function(isClick) {
                    var filter = $scope.meta.filterValue;

                    if ( !filter && ($scope.activeSearch  || $scope.filteredData)) {

                        // no query in box, but we prevously filtered or there is an active search
                        $scope.clearFilter();
                    } else if (isClick && $scope.activeSearch ) {

                        // User clicks clear
                        $scope.clearFilter();
                    } else if (filter) {
                        $scope.startFilter();
                    }
                };

                /**
                 * Fetch the list of hits from the server
                 * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                 */
                $scope.fetch = function() {
                    spinnerAPI.start("hitlistSpinner");
                    return hitListService
                        .fetchList($scope.meta)
                        .then(function(results) {
                            $scope.hitList = results.items;
                            $scope.totalItems = results.totalItems;
                            $scope.totalPages = results.totalPages;
                        }, function(error) {

                            // failure
                            alertService.add({
                                type: "danger",
                                message: error,
                                id: "errorFetchHitList"
                            });
                        })
                        .then(function() {
                            $scope.loadingPageData = false;
                            spinnerAPI.stop("hitlistSpinner");
                        });
                };

                // setup data structures for the view
                $scope.hitList = [];
                $scope.totalPages = 0;
                $scope.totalItems = 0;

                var routeHasPaging = $routeParams["api.chunk.enable"] === "1";
                var pageSize = 10;
                var page = 1;
                if (routeHasPaging) {
                    pageSize = parseInt($routeParams["api.chunk.size"], 10);
                    page = Math.floor(parseInt($routeParams["api.chunk.start"], 10) / pageSize) + 1;
                }

                var routeHasSorting = $routeParams["api.sort.enable"] === "1";

                $scope.meta = {
                    filterBy: $routeParams["api.filter.a.field"] || "*",
                    filterCompare: "contains",
                    filterValue: $routeParams["api.filter.a.arg0"] || "",
                    pageSize: routeHasPaging ?  pageSize : 10,
                    pageNumber: routeHasPaging ? page : 1,
                    sortDirection: routeHasSorting ? ( $routeParams["api.sort.a.reverse"] === "1" ? "desc" : "asc" ) : "desc",
                    sortBy: routeHasSorting ? $routeParams["api.sort.a.field"] : "timestamp",
                    sortType: routeHasSorting ? $routeParams["api.sort.a.type"] : "numeric",
                    pageSizes: [10, 20, 50, 100]
                };

                // if the user types something else in the search box, we change the button icon so they can search again.
                $scope.$watch("meta.filterValue", function(oldValue, newValue) {
                    if (oldValue === newValue) {
                        return;
                    }
                    $scope.activeSearch = false;
                });

                // watch the page size and and load the first page if it changes
                $scope.$watch("meta.pageSize", function(oldValue, newValue) {
                    if (oldValue === newValue) {
                        return;
                    }
                    $scope.selectPage(1);
                });

                $scope.activeSearch = $scope.filteredData = $scope.meta.filterValue ? true : false;

                // Setup the installed bit...
                $scope.isInstalled = PAGE.installed;

                // Expose any backend exceptions, ie missing database, missing table,
                $scope.dbException = PAGE.hitList.metadata.result === 0 ? PAGE.hitList.metadata.reason : "";

                $scope.$on("$viewContentLoaded", function() {

                    // check for page data in the template if this is a first load
                    if (app.firstLoad.hitList && PAGE.hitList) {
                        app.firstLoad.hitList = false;
                        $scope.loadingPageData = false;
                        var results = hitListService.prepareList(PAGE.hitList);
                        $scope.hitList = results.items;
                        $scope.totalItems = results.totalItems;
                        $scope.totalPages = results.totalPages;
                    } else {

                        // Otherwise, retrieve it via ajax
                        $timeout(function() {

                            // NOTE: Without this delay the spinners are not created on inter-view navigation.
                            $scope.selectPage(1);
                        });
                    }
                });

                if ($routeParams["addSuccess"]) {
                    $scope.showAddSuccess = true;
                }
            }
        ]);

        return controller;
    }
);

/*
# templates/mod_security/services/vendorService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/vendorService',[

        // Libraries
        "angular",

        // CJT
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app = angular.module("App");

        /**
         * Normalize the vendor to account for any missing data, type conversion, etc.
         *
         * @method _normalizeVendor
         * @private
         * @param  {Object} vendor Vendor returned from the server.
         * @return {Object}        Vendor with all the fields normalized and patched.
         */
        function _normalizeVendor(vendor) {
            vendor.cpanel_provided = PARSE.parsePerlBoolean(vendor.cpanel_provided);
            vendor.enabled = PARSE.parsePerlBoolean(vendor.enabled);
            vendor.update = PARSE.parsePerlBoolean(vendor.update);
            vendor.installed = PARSE.parsePerlBoolean(vendor.installed);
            vendor.totalEnabled = 0;
            vendor.totalDisabled = 0;

            if (vendor.configs) {
                for (var i = 0, l = vendor.configs.length; i < l; i++) {
                    var config = vendor.configs[i];
                    config.enabled = PARSE.parsePerlBoolean(config.active);
                    delete config.active;
                    if (config.enabled) {
                        vendor.totalEnabled++;
                    } else {
                        vendor.totalDisabled++;
                    }
                }

                // Sort initially by config
                vendor.configs.sort(function(configA, configB) {
                    return configA.config.localeCompare(configB.config);
                });
            }

            return vendor;
        }

        /**
         * Converts the response to our application data structure
         * @method _convertResponseToList
         * @private
         * @param  {Object} response
         * @return {Object} Sanitized data structure.
         */
        function _convertResponseToList(response) {
            var items = [];

            if (response.status) {
                var data = response.data;
                for (var i = 0, length = data.length; i < length; i++) {
                    var vendor = data[i];

                    // Mark the record as unchanged
                    vendor.changed = false;

                    items.push(
                        _normalizeVendor(vendor)
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
        }

        /**
         * Normalize the outcome for an enable/disable config operation for
         * missing data, type conversion, etc.
         *
         * @method _normalizeOutcome
         * @private
         * @param  {Object} outcome Outcome returned from the server.
         * @param  {Boolean} enableCalled true if we are trying to enable, false otherwise
         * @return {Object}        Outcome with all the fields normalized and patched.
         */
        function _normalizeOutcome(outcome, enableCalled) {
            var ok = PARSE.parsePerlBoolean(outcome.ok);
            outcome.ok = ok;
            outcome.enabled = enableCalled ? ok : !ok;
            return outcome;
        }

        /**
         * Cleans up the response for outcomes
         *
         * @method _convertOutcomeResponseToList
         * @private
         * @param  {Array} outcomes
         * @param  {Boolean} enableCalled true if we are trying to enable, false otherwise
         * @return {Array} Sanitized data structure.
         */
        function _convertOutcomeResponseToList(data, enableCalled) {
            var configs = [];
            var totalEnabled = 0;
            var totalDisabled = 0;

            if (data) {
                for (var i = 0, length = data.length; i < length; i++) {
                    var config = data[i];

                    configs.push(
                        _normalizeOutcome(config, enableCalled)
                    );
                    if (config.enabled) {
                        totalEnabled++;
                    } else {
                        totalDisabled++;
                    }
                }
            }

            return {
                configs: configs,
                totalEnabled: totalEnabled,
                totalDisabled: totalDisabled
            };
        }

        /**
         * Returns a promise with vendor information that optionally adds the vendor to the list
         *
         * @method _returnVendor
         * @private
         * @param  {Deferred} deferred
         * @param  {String} method      The API method to call.
         * @param  {Object} parameters  Parameters for the add and preview methods
         *   @param  {String} url       Vendor URL for the YAML file describing the vendor configuration.
         * @return {Promise}
         */
        var _returnVendor = function(deferred, method, parameters) {
            var apiCall = new APIREQUEST.Class();
            apiCall.initialize(NO_MODULE, method);
            apiCall.addArgument("url", parameters.url);

            this.deferred(apiCall, {
                transformAPISuccess: function(response) {
                    return response.data;
                }
            }, deferred);

            // pass the promise back to the controller
            return deferred.promise;
        };

        /**
         * Setup the configuration models API service
         */
        app.factory("vendorService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var VendorService = function() {};
            VendorService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(VendorService.prototype, {

                /**
                 * Get a single vendor by its id from the backend.
                 *
                 * @method fetchVendorById
                 * @param {number} vendorId Id of the vendor to fetch.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchVendorById: function(vendorId) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_vendors");
                    apiCall.addArgument("show_uninstalled", 1);
                    apiCall.addFilter("vendor_id", "eq", vendorId);

                    var deferred = this.deferred(apiCall, {
                        apiSuccess: function(response, deferred) {
                            var results = _convertResponseToList(response);
                            if (results.items.length === 1) {
                                deferred.resolve(results.items[0]);
                            } else if (results.items.length > 1) {
                                deferred.reject(LOCALE.maketext("You have multiple vendors with the same [asis,vendor_id]."));
                            } else {
                                deferred.reject(LOCALE.maketext("The system could not find the specified [asis,vendor_id].", vendorId));
                            }
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Get a list of vendors
                 * * @param {object} meta Optional meta data to control sorting, filtering and paging
                 *   @param {string} meta.sortBy Name of the field to sort by
                 *   @param {string} meta.sordDirection asc or desc
                 *   @param {string} meta.sortType Optional name of the sort rule to apply to the sorting
                 *   @param {string} meta.filterBy Name of the field to filter by
                 *   @param {string} meta.filterCompare Optional comparator to use when comparing for filter.
                 *   @param {string} meta.filterValue  Expression/argument to pass to the compare method.
                 *   @param {string} meta.pageNumber Page number to fetch.
                 *   @param {string} meta.pageSize Size of a page, will default to 10 if not provided.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchList: function(meta) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_vendors");
                    apiCall.addArgument("show_uninstalled", 1);
                    if (meta) {
                        if (meta.sortBy && meta.sortDirection) {
                            apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                        }
                        if (meta.pageNumber) {
                            apiCall.addPaging(meta.pageNumber, meta.pageSize || 10);
                        }
                        if (meta.filterBy && meta.filterValue) {
                            apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                        }
                    }

                    return this.deferred(apiCall, {
                        transformAPISuccess: _convertResponseToList
                    }).promise;
                },

                /**
                 * Disable a vendor by id
                 *
                 * @method disableVendor
                 * @param  {Number}  id     Vendor id.
                 * @return {Promise}
                 */
                disableVendor: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_disable_vendor");
                    apiCall.addArgument("vendor_id", id);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Enable a vendor by id
                 *
                 * @method enableRule
                 * @param  {Number} id  Vendor id.
                 * @return {Promise}
                 */
                enableVendor: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_enable_vendor");
                    apiCall.addArgument("vendor_id", id);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Disable a config file by path
                 *
                 * @method disableConfig
                 * @param  {String}  config     Path to the specific config file.
                 * @return {Promise}
                 */
                disableConfig: function(config) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_make_config_inactive");
                    apiCall.addArgument("config", config);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Enable a config file by path
                 *
                 * @method disableConfig
                 * @param  {String}  config     Path to the specific config file.
                 * @return {Promise}
                 */
                enableConfig: function(config) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_make_config_active");
                    apiCall.addArgument("config", config);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Enable all the config files for a vendor
                 *
                 * @method enableAllConfigs
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                enableAllConfigs: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_enable_vendor_configs");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall, {
                        transformAPISuccess: function(response) {
                            return _convertOutcomeResponseToList(response.data, true);
                        },
                        transformAPIFailure: function(response) {
                            return _convertOutcomeResponseToList(response.data, true);
                        }
                    });

                    return deferred.promise;
                },

                /**
                 * Disable all the config files for a vendor
                 *
                 * @method disableAllConfigs
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                disableAllConfigs: function(id) {

                    // make a promise
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_disable_vendor_configs");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall, {
                        transformAPISuccess: function(response) {
                            return _convertOutcomeResponseToList(response.data, false);
                        },
                        transformAPIFailure: function(response) {
                            return _convertOutcomeResponseToList(response.data, false);
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Enable automatic updates for a vendor
                 *
                 * @method enableVendorUpdates
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                enableVendorUpdates: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_enable_vendor_updates");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Disable automatic updates for a vendor
                 *
                 * @method disableVendorUpdates
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                disableVendorUpdates: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_disable_vendor_updates");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Remove a vendor from the system by its id
                 *
                 * @method deleteVendor
                 * @param  {Number} id Vendor id for the vendor to delete.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                deleteVendor: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_remove_vendor");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Retrieves vendor information from a remote URL containing configuration information
                 * stored in a YAML format.
                 *
                 * @method loadVendor
                 * @param  {String} url Vendor URL for the YAML file describing the vendor configuration.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                loadVendor: function(url) {

                    // make a promise
                    var deferred = $q.defer(),
                        parameters = {
                            url: url
                        };

                    // pass the promise back to the controller
                    return _returnVendor.call(this, deferred, "modsec_preview_vendor", parameters);
                },

                /**
                 * Adds a vendor configuration to the list of vendors
                 *
                 * @method saveVendor
                 * @param  {String} url         Vendor URL for the YAML file describing the vendor configuration.
                 * @return {Promise}            Promise that will fulfill the request.
                 */
                saveVendor: function(url) {

                    // make a promise
                    var deferred = $q.defer(),
                        parameters = {
                            url: url,
                        };

                    // pass the promise back to the controller
                    return _returnVendor.call(this, deferred, "modsec_add_vendor", parameters);
                },

                /**
                * Helper method that calls _convertResponseToList to prepare the data structure
                *
                * @method prepareList
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return _convertResponseToList(response);
                }
            });

            return new VendorService();
        }]);
    }
);

/*
# mod_security/views/rulelistController.js        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/rulesListController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/logic",
        "uiBootstrap",
        "cjt/directives/responsiveSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/filters/splitFilter",
        "cjt/filters/htmlFilter",
        "cjt/directives/spinnerDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/services/alertService",
        "app/services/ruleService",
        "app/services/vendorService",
        "cjt/io/whm-v1-querystring-service",
    ],
    function(angular, _, LOCALE, LOGIC) {
        "use strict";

        var USER_CONFIG = "modsec2.user.conf"; /* TODO: EA-4700 */

        var STATUS_ENUM = {
            ENABLED: "enabled",
            DISABLED: "disabled",
            BOTH: "both",
        };

        var PUBLISHED_ENUM = {
            DEPLOYED: "deployed",
            STAGED: "staged",
            BOTH: "both",
        };

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "rulesListController", [
                "$scope",
                "$location",
                "$anchorScroll",
                "$timeout",
                "ruleService",
                "vendorService",
                "alertService",
                "spinnerAPI",
                "queryService",
                "PAGE",
                function(
                    $scope,
                    $location,
                    $anchorScroll,
                    $timeout,
                    ruleService,
                    vendorService,
                    alertService,
                    spinnerAPI,
                    queryService,
                    PAGE) {

                    $scope.loadingPageData = true;
                    $scope.activeSearch = false;
                    $scope.filteredData = false;
                    $scope.advancedSearchApplied = false;

                    /**
                         * Update the advanced search applied flag by checking if the advanced search flags are
                         * in their default state or not.
                         *
                         * @private
                         * @method _updateAdvancedSearchApplied
                         * @return {Boolean} true if there is an advanced search, false otherwise
                         */
                    function _updateAdvancedSearchApplied() {

                        // See if we have an advanced search different from the default
                        if ($scope.meta.advanced.includeUserRules !== true ||
                                $scope.meta.advanced.showEnabledDisabled !== STATUS_ENUM.BOTH ||
                                $scope.meta.advanced.showStagedDeployed !== PUBLISHED_ENUM.BOTH) {
                            $scope.advancedSearchApplied = true;
                        } else {
                            $scope.advancedSearchApplied = false;
                        }

                        // Also update the indicator at this point.
                        $scope.appliedIncludeUserRules = $scope.meta.advanced.includeUserRules;
                    }

                    /**
                         * Update the previous state information for rollback should the fetch fail.
                         * @private
                         * @method _updatePreviousState
                         */
                    function _updatePreviousState() {
                        $scope.previouslySelected = $scope.selectedVendors;
                        $scope.meta.advanced.previousShowStagedDeployed = $scope.meta.advanced.showStagedDeployed;
                        $scope.meta.advanced.previousShowEnabledDisabled = $scope.meta.advanced.showEnabledDisabled;
                        $scope.meta.advanced.previousIncludeUserRules = $scope.meta.advanced.includeUserRules;
                    }

                    /**
                         * Revert to the previous advanced filter setting.
                         * @private
                         * @method _revertToPreviousState
                         */
                    function _revertToPreviousState() {
                        $scope.selectedVendors = $scope.previouslySelected;
                        $scope.meta.advanced.showStagedDeployed = $scope.meta.advanced.previousShowStagedDeployed;
                        $scope.meta.advanced.showEnabledDisabled = $scope.meta.advanced.previousShowEnabledDisabled;
                        $scope.meta.advanced.includeUserRules = $scope.meta.advanced.previousIncludeUserRules;
                        $scope.meta.advanced.changed = false;
                    }

                    /**
                         * Apply the advanced search filters to the query-string.
                         *
                         * @method _addAdvancedSearchToQuery
                         * @private
                         */
                    function _addAdvancedSearchToQuery() {
                        if ($scope.meta.advanced.showStagedDeployed === PUBLISHED_ENUM.STAGED) {
                            queryService.query.addSearchField("c", "staged", "eq", "1");
                        } else {
                            queryService.query.clearSearchField("staged", "eq", "1");
                        }

                        if ($scope.meta.advanced.showStagedDeployed === PUBLISHED_ENUM.DEPLOYED) {
                            queryService.query.addSearchField("b", "staged", "eq", "0");
                        } else {
                            queryService.query.clearSearchField("staged", "eq", "0");
                        }

                        if ($scope.meta.advanced.showEnabledDisabled === STATUS_ENUM.ENABLED) {
                            queryService.query.addSearchField("d", "disabled", "eq", "0");
                        } else {
                            queryService.query.clearSearchField("disabled", "eq", "0");
                        }

                        if ($scope.meta.advanced.showEnabledDisabled === STATUS_ENUM.DISABLED) {
                            queryService.query.addSearchField("e", "disabled", "eq", "1");
                        } else {
                            queryService.query.clearSearchField("disabled", "eq", "1");
                        }

                        if (!$scope.meta.advanced.includeUserRules) {
                            queryService.query.removeParameter("config");
                        } else {
                            queryService.query.addParameter("config", USER_CONFIG);
                        }

                        var vendors = _getSelectedVendorIDs();
                        if (vendors.length === 0) {
                            queryService.query.removeParameter("vendor_id");
                        } else {
                            queryService.query.addParameter("vendor_id", vendors.join(","));
                        }
                    }

                    /**
                         * Event handler triggered when one of the advanced filter options is changed.
                         *
                         * @method onAdvancedChanged
                         * @param  {String} type
                         */
                    $scope.onAdvancedChanged = function(type) {
                        switch (type) {
                            case "vendor":
                                if ( $scope.previouslySelected !== $scope.selectedVendors ) {
                                    $scope.meta.advanced.changed = true;
                                }
                                break;
                            case "userDefined":
                                if ($scope.meta.advanced.previousIncludeUserRules !== $scope.meta.advanced.includeUserRules) {
                                    $scope.meta.advanced.changed = true;
                                }
                                break;
                            default:
                                $scope.meta.advanced.changed = true;
                        }
                    };

                    /**
                         * Check if there are any search criteria applied.  This includes various advanced search
                         * criteria different then their defaults or any unselected vendors.
                         *
                         * @method hasSearchFilter
                         * @return {Boolean} true if the is an active search, false otherwise.
                         */
                    $scope.hasSearchFilter = function() {
                        return $scope.filteredData === true ||
                                   $scope.advancedSearchApplied === true ||
                                   $scope.appliedVendors.length < $scope.vendors.length;
                    };

                    /**
                         * Clear the search query
                         *
                         * @method clearFilter
                         * @returns Promise
                         */
                    $scope.clearFilter = function() {
                        $scope.meta.filterValue = "";
                        $scope.activeSearch = false;
                        $scope.filteredData = false;

                        queryService.query.clearSearchField("*", "contains");
                        _addAdvancedSearchToQuery();

                        // select the first page of search results
                        return $scope.selectPage(1);
                    };

                    /**
                         * Start a search query
                         *
                         * @method startFilter
                         * @returns Promise
                         */
                    $scope.startFilter = function() {
                        $scope.activeSearch = ($scope.meta.filterValue !== "");
                        $scope.filteredData = false;

                        // Leave history so refresh works
                        if ($scope.meta.filterValue) {
                            queryService.query.addSearchField("a", "*", "contains", $scope.meta.filterValue);
                        } else {
                            queryService.query.clearSearchField("*", "contains");
                        }

                        return $scope.selectPage(1)
                            .then(function() {
                                _addAdvancedSearchToQuery();
                                if ($scope.meta.filterValue) {
                                    $scope.filteredData = true;
                                }
                                _updatePreviousState();
                                $scope.meta.advanced.changed = false;
                            }, function() {

                                // Revert to the previous state
                                _revertToPreviousState();
                            }).finally(function() {
                                _updateAdvancedSearchApplied();
                            });
                    };

                    /**
                         * Open the advanced search menu from another button.
                         *
                         * @method openAdvancedSearch
                         * @param  {Event} $event The jQlite event
                         */
                    $scope.openAdvancedSearch = function($event) {
                        $event.preventDefault();
                        $event.stopPropagation();
                        $event.currentTarget.blur();
                        $scope.advancedSearchOpen = !$scope.advancedSearchOpen;
                    };

                    /**
                         * Apply the advanced filter and close the dropdown
                         *
                         * @method applyAdvancedFilter
                         * @param  {Event} $event
                         */
                    $scope.applyAdvancedFilter = function($event) {
                        $event.preventDefault();
                        $event.stopPropagation();
                        $scope.advancedSearchOpen = false;
                        $scope.toggleSearch();
                    };

                    /**
                         * Reset the advanced filter and close the dropdown
                         *
                         * @method resetAdvancedFilter
                         * @param  {Event} $event
                         */
                    $scope.resetAdvancedFilter = function($event) {
                        $event.preventDefault();
                        $event.stopPropagation();
                        $scope.advancedSearchOpen = false;
                        $scope.resetFilter();
                    };

                    /**
                         * Update the applied vendor field.
                         *
                         * @private
                         * @method _updateAppliedVendor
                         */
                    function _updateAppliedVendor() {
                        $scope.appliedVendors = $scope.selectedVendors.slice();
                    }

                    /**
                         * Reset the advanced filter and apply
                         */
                    $scope.resetFilter = function() {
                        $scope.meta.advanced.changed = false;
                        if ($scope.meta.advanced.showStagedDeployed !== PUBLISHED_ENUM.BOTH) {
                            $scope.meta.advanced.showStagedDeployed = PUBLISHED_ENUM.BOTH;
                            $scope.meta.advanced.changed = true;
                        }

                        if ($scope.meta.advanced.showEnabledDisabled !== STATUS_ENUM.BOTH) {
                            $scope.meta.advanced.showEnabledDisabled = STATUS_ENUM.BOTH;
                            $scope.meta.advanced.changed = true;
                        }

                        if (!$scope.meta.advanced.includeUserRules) {
                            $scope.meta.advanced.includeUserRules = true;
                            $scope.meta.advanced.changed = true;
                        }

                        if ($scope.selectedVendors.length < $scope.vendors.length) {
                            $scope.selectedVendors = $scope.vendors;
                            $scope.meta.advanced.changed = true;
                        }

                        if ($scope.meta.advanced.changed) {
                            $scope.startFilter().then(_updateAppliedVendor);
                        }
                    };

                    /**
                         * Handles the keybinding for the clearing and searching.
                         * Esc clears the search field.
                         * Enter performs a search.
                         *
                         * @method triggerToggleSearch
                         * @param {Event} event - The event object
                         */
                    $scope.triggerToggleSearch = function(event) {

                        // clear on Esc
                        if (event.keyCode === 27) {
                            $scope.toggleSearch(true);
                        }

                        // filter on Enter
                        if (event.keyCode === 13) {
                            $scope.toggleSearch();
                        }
                    };

                    /**
                         * Toggles the clear button and conditionally performs a search.
                         * The expected behavior is if the user clicks the button or focuses the button and hits enter the button state rules.
                         *
                         * @method toggleSearch
                         * @scope
                         * @param {Boolean} isClick Toggle button clicked.
                         */
                    $scope.toggleSearch = function(isClick) {
                        var filter = $scope.meta.filterValue;
                        var advancedChanged = $scope.meta.advanced.changed;

                        if ( (!filter && !advancedChanged && ($scope.activeSearch  || $scope.filteredData)))  {

                            // no query in box, but we previously filtered or there is an active search
                            $scope.clearFilter().then(_updateAppliedVendor);
                        } else if (isClick && $scope.activeSearch ) {

                            // User clicks clear
                            $scope.clearFilter().then(_updateAppliedVendor);
                        } else if (filter || advancedChanged) {
                            $scope.startFilter().then(_updateAppliedVendor);
                        }
                    };

                    /**
                         * Select a specific page of rules
                         *
                         * @method selectPage
                         * @param  {Number} [page] Optional page number, if not provided will use the current
                         *                         page provided by the scope.meta.pageNumber.
                         * @return {Promise}
                         */
                    $scope.selectPage = function(page) {

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.pageNumber = page;
                        }

                        queryService.query.updatePagination($scope.meta.pageNumber, $scope.meta.pageSize);
                        return $scope.fetch();
                    };

                    /**
                         * Sort the list of rules
                         *
                         * @param {Object}  meta         The sort model.
                         * @param {Boolean} defaultSort  If true, the sort was not not initiated by the user
                         */
                    $scope.sortList = function(meta, defaultSort) {
                        queryService.query.clearSort();
                        queryService.query.addSortField(meta.sortBy, meta.sortType, meta.sortDirection);
                        if (!defaultSort) {
                            $scope.fetch();
                        }
                    };

                    /**
                         * Disables a rule from the list using the rule service
                         *
                         * @method disable
                         * @param  {Object} rule The rule to disable
                         * @return {Promise}
                         */
                    $scope.disable = function(rule) {
                        var ruleIndentifier = rule.id || "rule";

                        // if message is defined append it to the rule identifier
                        if ( rule.hasOwnProperty("meta_msg") && rule.meta_msg !== "" ) {
                            ruleIndentifier += ": " + rule.meta_msg;
                        }

                        return ruleService
                            .disableRule(rule.config, rule.id, false)
                            .then(function() {

                                // success
                                rule.disabled = true;
                                rule.staged = true;
                                $scope.stagedChanges = true;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully disabled “[_1]” in the list of [asis,ModSecurity™] rules.", _.escape(ruleIndentifier)),
                                    id: "alertDisableSuccess",
                                });

                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDisablingRule",
                                });
                            });
                    };

                    /**
                         * Enables a rule from the list using the rule service
                         *
                         * @method enable
                         * @param  {Object} rule The rule to enable
                         * @return {Promise}
                         */
                    $scope.enable = function(rule) {
                        var ruleIndentifier = rule.id || "rule";

                        // if message is defined append it to the rule identifier
                        if ( rule.hasOwnProperty("meta_msg") && rule.meta_msg !== "" ) {
                            ruleIndentifier += ": " + rule.meta_msg;
                        }

                        return ruleService
                            .enableRule(rule.config, rule.id, false)
                            .then(function() {

                                // success
                                rule.disabled = false;
                                rule.staged = true;
                                $scope.stagedChanges = true;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully enabled “[_1]” in the list of [asis,ModSecurity™] rules.", _.escape(ruleIndentifier)),
                                    id: "alertEnableSuccess",
                                });

                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorEnablingRule",
                                });
                            });
                    };

                    /**
                         * Deletes a rule from the list using the rule service
                         *
                         * @method delete
                         * @param  {Object} rule The rule to delete
                         * @return {Promise}
                         */
                    $scope.delete = function(rule) {
                        var ruleIndentifier = rule.id || "rule";

                        // if message is defined append it to the rule identifier
                        if ( rule.hasOwnProperty("meta_msg") && rule.meta_msg !== "" ) {
                            ruleIndentifier += ": " + rule.meta_msg;
                        }

                        rule.deleting = true;
                        return ruleService
                            .deleteRule(rule.id)
                            .then(function() {

                                // success
                                $scope.fetch();
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully deleted “[_1]” from the list of [asis,ModSecurity™] rules.", _.escape(ruleIndentifier)),
                                    id: "alertDeleteSuccess",
                                });

                            }, function(error) {
                                rule.deleting = false;

                                // reset delete confirmation
                                rule.showDeleteConfirm = false;

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDeletingRule",
                                });
                            });
                    };

                    /**
                         * Deploys staged rules using the rule service
                         *
                         * @method deployChanges
                         * @return {Promise}
                         */
                    $scope.deployChanges = function() {
                        $scope.pendingChanges = true;
                        return ruleService
                            .deployQueuedRules()
                            .then(function() {

                                // success
                                $scope.stagedChanges = false;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully deployed the staged changes and [asis,Apache] received a graceful restart request."),
                                    id: "successDeployChanges",
                                });
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDeployChanges",
                                });
                            }).finally(function() {
                                $scope.pendingChanges = false;
                                $scope.fetch();
                            });
                    };

                    /**
                         * Discards staged rule changes using the rule service
                         *
                         * @method discardChanges
                         * @return {Promise}
                         */
                    $scope.discardChanges = function() {
                        $scope.pendingChanges = true;
                        return ruleService
                            .discardQueuedRules()
                            .then(function() {
                                var replace = false;

                                // discard changes success
                                $scope.stagedChanges = false;
                                return $scope.fetch().then(function() {

                                    // fetch success
                                    replace = true;
                                }, function() {

                                    // fetch failure
                                    replace = false;
                                }).finally(function() {

                                    // display discard changes success
                                    $scope.discardConfirm = false;
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully discarded the staged changes."),
                                        id: "successDiscardingChanges",
                                        replace: replace,
                                    });
                                });
                            }, function(error) {
                                $scope.fetch(); // To update the list to match the new state.
                                // discard changes failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDiscardingChanges",
                                });
                            }).finally(function() {
                                $scope.pendingChanges = false;
                            });
                    };

                    /**
                         * Initialize the selected vendors
                         *
                         * @private
                         * @method initializeSelectedVendors
                         */
                    var _initializeSelectedVendors = function() {
                        var vendorIds = [];
                        var vendor_id_param = queryService.route.getParameter("vendor_id");
                        if (vendor_id_param) {
                            vendorIds = vendor_id_param.split(",");
                        }

                        var config_param = queryService.route.getParameter("config");

                        var vendors = [];
                        if (!angular.isDefined(vendor_id_param) && !angular.isDefined(config_param)) {

                            // This is a default load, so select all vendors
                            vendors = $scope.vendors;
                        } else if (vendorIds.length > 0) {

                            // Some vendors were passed on the querystring, so use those
                            vendors = _.filter($scope.vendors, function(vendor) {

                                // find the vendors by ids from the list of vendorIds
                                var id = _.find(vendorIds, function(id) {
                                    return vendor.vendor_id === id;
                                });
                                return !!id;
                            });
                        }

                        $scope.previouslySelected = $scope.selectedVendors = vendors;

                        // Also update the applied vendors so the ui is updated on load.
                        $scope.appliedVendors = vendors.slice();
                    };

                    /**
                         * Determines if a rule is from a custom set
                         *
                         * @method isCustomVendor
                         * @param {Object} rule The rule to read vendor id from
                         * @return {Boolean} Returns true if the rule is from a custom set
                         */
                    $scope.isCustomVendor = function(rule) {
                        return rule.hasOwnProperty("vendor_id") && rule.vendor_id === "";
                    };

                    /**
                         * Returns the full vendor name for the supplied rule
                         *
                         * @method getVendorName
                         * @param {Object} rule The rule to read vendor id from
                         * @return {String} The full vendor name
                         */
                    $scope.getVendorName = function(rule) {
                        var currentVendor;
                        if ( rule.vendor_id !== "" ) {
                            for ( var i = 0, length = $scope.vendors.length; i < length; i++ ) {
                                currentVendor = $scope.vendors[i];
                                if ( rule.vendor_id === currentVendor.vendor_id ) {
                                    return currentVendor.name;
                                }
                            }
                        }
                        return LOCALE.maketext("Custom");
                    };

                    /**
                         * Get a list of the enabled vendors
                         *
                         * @method _onlyEnabledVendors
                         * @private
                         * @param  {Array} vendor   A list of vendors
                         * @return {Array}          A list of the vendors that were enabled
                         */
                    function _onlyEnabledVendors(vendors) {
                        if (vendors && angular.isArray(vendors)) {
                            return  vendors.filter( function(vendor) {
                                return vendor.enabled;
                            });
                        } else {
                            return [];
                        }
                    }

                    /**
                         * Retrieve the list of vendors
                         *
                         * @method getVendors
                         * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                         */
                    $scope.getVendors = function() {
                        spinnerAPI.start("ruleListSpinner");
                        return vendorService
                            .fetchList()
                            .then(function(results) {
                                if (angular.isArray(results.items)) {
                                    $scope.vendors = _onlyEnabledVendors(results.items);
                                    _initializeSelectedVendors();
                                } else {
                                    alertService.add({
                                        message: "The system was unable to retrieve the list of available vendors.",
                                        type: "danger",
                                    });
                                }
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorLoadingVendorList",
                                });
                            }).finally(function() {
                                spinnerAPI.stop("ruleListSpinner");
                            });
                    };

                    /**
                         * Performs final prep work on the selectedVendors list.
                         * Extracts the vendor ids into an array.
                         *
                         * @method _getSelectedVendorIDs
                         * @return {Array}  A list of vendor ids that is ready for consumption by the ruleService
                         */
                    function _getSelectedVendorIDs() {
                        return $scope.selectedVendors && $scope.selectedVendors.map(function(vendor) {
                            return vendor.vendor_id;
                        });
                    }

                    /**
                         * Fetch the list of rules from the server
                         * @method fetch
                         * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                         */
                    $scope.fetch = function() {
                        $scope.loadingPageData = true;
                        spinnerAPI.start("ruleListSpinner");
                        alertService.removeById("errorFetchRulesList");

                        return ruleService
                            .fetchRulesList(_getSelectedVendorIDs(), $scope.meta)
                            .then(function(results) {
                                $scope.rules = results.items;
                                $scope.stagedChanges = results.stagedChanges;
                                $scope.totalItems = results.totalItems;
                                $scope.totalPages = results.totalPages;
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorFetchRulesList",
                                });

                                // throw an error for chained promises
                                throw error;
                            }).finally(function() {
                                $scope.loadingPageData = false;
                                spinnerAPI.stop("ruleListSpinner");
                            });
                    };

                    /**
                         * Generates the text for the vendor/user-defined indicator button.
                         * This is needed because we need to dynamically determine plurality of phrases.
                         *
                         * @method generateIndicatorText
                         * @param  {String} type The type of vendor count to generate (e.g. "short" or "long")
                         * @return {String}      The formatted vendor count string
                         */
                    $scope.generateIndicatorText = function(type) {
                        switch (type) {
                            case "vendor-short":
                                return $scope.appliedVendors.length;
                            case "vendor-long":
                                return LOCALE.maketext("[quant,_1,Vendor,Vendors]", $scope.appliedVendors.length);
                            case "vendor-title":
                                return $scope.generateVendorTitle();
                            case "user-title":
                                return $scope.meta.advanced.previousIncludeUserRules ?
                                    LOCALE.maketext("Your user-defined rules are included below.") :
                                    LOCALE.maketext("Your user-defined rules are not included below.");
                            default:
                                return LOCALE.maketext("Loading …");
                        }
                    };

                    /**
                         * Generates the text for the title/tooltip that displays when a user hovers over the rule set count.
                         *
                         * @method generateVendorTitle
                         * @return {String} The text for the tooltip
                         */
                    $scope.generateVendorTitle = function() {
                        var vendors = $scope.appliedVendors;

                        if (vendors.length === 0) {
                            return LOCALE.maketext("You have not selected any vendor rule sets.");
                        }

                        var vendorNames = vendors.map(function(vendor) {
                            return vendor.name;
                        });

                        return LOCALE.maketext("The displayed rules are from the following vendor rule [numerate,_1,set,sets]: [list_and,_2]", vendors.length, vendorNames);
                    };

                    /**
                         * Sets the left property so that the dropdown lines up with the input group
                         *
                         * @method _setMenuLeft
                         * @private
                         * @param {Element} menu         The dropdown menu element
                         * @param {Number}  groupWidth   The width of the input group in pixels
                         */
                    function _setMenuLeft(menu, groupWidth) {
                        menu.css("left", -1 * groupWidth);
                        menu.css("right", "auto");
                    }

                    /**
                         * Unsets the left and right properties so that they reset back to the CSS defaults
                         *
                         * @method _setMenuRight
                         * @private
                         * @param {Element} menu   The dropdown menu element
                         */
                    function _setMenuRight(menu) {
                        menu.css("left", "");
                        menu.css("right", "");
                    }

                    /**
                         * Adjusts the position of the dropdown menu depending on whether or not it is being
                         * clipped by the edge of the viewport.
                         *
                         * @method fixMenuClipping
                         * @param  {Event} event   The associated event object
                         */
                    $scope.fixMenuClipping = function(event) {
                        var menu       = this.find(".advanced-filter-menu");
                        var inputGroup = this.siblings("input");
                        var groupWidth = inputGroup.outerWidth();

                        // This keeps the menu from flying around while still allowing offset to work
                        if (event.type === "open") {
                            menu.css("opacity", 0);
                        }

                        $timeout(function() { // We need to queue this up after $digest or the dropdown won't be visible yet and the offset will be incorrect
                            if (menu) {
                                switch (event.type) {

                                    case "resize":
                                        if (menu.offset().left < 0) {
                                            _setMenuLeft(menu, groupWidth);
                                        } else if (groupWidth > menu.outerWidth()) { // If the menu isn't clipping, it could be because we fixed it already or because it fits on the page
                                            _setMenuRight(menu);
                                        }
                                        break;

                                    case "open":
                                        if (menu.offset().left < 0) {
                                            _setMenuLeft(menu, groupWidth);
                                        }
                                        break;

                                    case "close":
                                        _setMenuRight(menu);
                                        break;
                                }

                                menu.css("opacity", 1);
                            }
                        }, 0, false);
                    };

                    // setup data structures for the view
                    $scope.rules = [];
                    $scope.vendors = [];
                    $scope.appliedVendors = []; // Differs from the selectedVendors in that this is only populated once the settings have been applied
                    $scope.totalPages = 0;
                    $scope.totalItems = 0;

                    var pageSize = queryService.route.getPageSize(queryService.DEFAULT_PAGE_SIZE);
                    var page = queryService.route.getPage(pageSize, 1);
                    var sorting = queryService.route.getSortProperties("disabled", "", "asc");


                    /**
                         * Determin if we should check the includeUserRules advanced search option.
                         * @note if neither the config or vendor_id is set in the querystring, then default to
                         * showing the custom config to match the default prefetch rules.
                         * @return {Boolean}
                         */
                    function _includeUserRules() {
                        var config = queryService.route.getParameter("config");
                        var vendor_id = queryService.route.getParameter("vendor_id");
                        if (config !== USER_CONFIG && !vendor_id) {
                            return true; // We default to showing custom rules
                        }
                        return config === USER_CONFIG;
                    }

                    var staged = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("staged"), "1", true);
                    var deployed = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("staged"), "0", true);
                    var disabled = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("disabled"), "1", true);
                    var enabled = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("disabled"), "0", true);

                    $scope.meta = {
                        filterBy: "*",
                        filterCompare: "contains",
                        filterValue: "",
                        pageSize: pageSize,
                        pageNumber: page,
                        sortBy: sorting.field,
                        sortType: sorting.type,
                        sortDirection: sorting.direction,
                        pageSizes: [10, 20, 50, 100],
                        advanced: {
                            showStagedDeployed: LOGIC.translateBinaryAndToState(staged, deployed, PUBLISHED_ENUM.BOTH, PUBLISHED_ENUM.STAGED, PUBLISHED_ENUM.DEPLOYED, PUBLISHED_ENUM.BOTH),
                            showEnabledDisabled: LOGIC.translateBinaryAndToState(enabled, disabled, STATUS_ENUM.BOTH, STATUS_ENUM.ENABLED, STATUS_ENUM.DISABLED, STATUS_ENUM.BOTH),
                            includeUserRules: _includeUserRules(),
                            changed: false,
                        },
                    };

                    $scope.appliedIncludeUserRules = $scope.meta.advanced.includeUserRules;

                    _updatePreviousState();

                    $scope.activeSearch = $scope.filteredData = $scope.meta.filterValue ? true : false;

                    // if the user types something else in the search box, we change the button icon so they can search again.
                    $scope.$watch("meta.filterValue", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.activeSearch = false;
                    });

                    // watch the page size and and load the first page if it changes
                    $scope.$watch("meta.pageSize", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.selectPage(1);
                    });

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {

                        // redirect to the historic view of the hit list if mod_security is not installed
                        $scope.loadView("hitList");
                    }

                    $scope.$on("$viewContentLoaded", function() {

                        // check for page data in the template if this is a first load
                        if (app.firstLoad.rules && PAGE.rules) {
                            app.firstLoad.rules = false;
                            $scope.loadingPageData = false;
                            $scope.advancedSearchOpen = false;

                            var vendors = vendorService.prepareList(PAGE.vendors);

                            // In the rules list page, we only care about
                            // searching for rules from enabled vendors.
                            $scope.vendors =  _onlyEnabledVendors(vendors.items);

                            _initializeSelectedVendors();

                            var rules = ruleService.prepareList(PAGE.rules);

                            $scope.rules = rules.items;
                            $scope.stagedChanges = rules.stagedChanges;
                            $scope.totalItems = rules.totalItems;
                            $scope.totalPages = rules.totalPages;

                            if ( !rules.status ) {

                                // on view load in an error state give the user a chance to discard staged changes
                                $scope.stagedChanges = true;
                                $scope.loadingPageData = "error";
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("There was a problem loading the page. The system is reporting the following error: [_1].", _.escape(PAGE.rules.metadata.reason)),
                                    id: "errorFetchRulesList",
                                });
                            }
                        } else {

                            // Otherwise, retrieve it via ajax
                            $timeout(function() {

                                // NOTE: Without this delay the spinners are not created on inter-view navigation.
                                $scope.getVendors().then(function() {
                                    $scope.selectPage(1);
                                });
                            });
                        }
                    });
                },
            ]);

        return controller;
    }
);

/*
# templates/mod_security/views/addRuleController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/addRuleController',[
        "angular",
        "lodash",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/ruleService",
    ],
    function(angular, _, $, LOCALE, PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "addRuleController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "$q", "spinnerAPI", "alertService", "ruleService", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, $q, spinnerAPI, alertService, ruleService, PAGE) {

                    /**
                 * Disable the save button based on form state
                 *
                 * @method disableSave
                 * @param  {FormController} form
                 * @return {Boolean}
                 */
                    $scope.disableSave = function(form) {
                        return (form.rule.$pristine && form.enabled.$pristine) || (form.$dirty && form.$invalid);
                    };

                    /**
                 * Clear the form
                 *
                 * @method clearForm
                 */
                    $scope.clearForm = function() {
                        $scope.enabled = true;
                        $scope.rule = "";
                        $scope.deploy = false;
                        $scope.clearNotices();
                    };

                    /**
                 * Clear the notices
                 *
                 * @method clearNotices
                 */
                    $scope.clearNotices = function() {
                        alertService.clear();
                        $scope.notice = "";
                    };

                    /**
                 * Navigate to the previous view.
                 *
                 * @method  cancel
                 */
                    $scope.cancel = function() {
                        $scope.clearNotices();
                        $scope.loadView("rulesList");
                    };

                    /**
                 * Save the form and navigate or clean depending on the users choices.
                 *
                 * @method save
                 * @param  {FormController} form
                 * @param  {Boolean} exit If true, will navigate back on completion, if false,
                 * will clear the form and let you add another rule.
                 * @return {Promise}
                 */
                    $scope.save = function(form, exit) {
                        $scope.clearNotices();

                        if (!form.$valid) {
                            return;
                        }

                        spinnerAPI.start("loadingSpinner");
                        return ruleService
                            .addRule($scope.rule, $scope.enabled, $scope.deploy)
                            .then(

                                /**
                                 * Handle successfully adding the rule
                                 * @method success
                                 * @private
                                 * @param  {Rule} rule Rule added to the system
                                 */
                                function success(rule) {
                                    $scope.clearNotices();
                                    form.$setPristine();
                                    spinnerAPI.stop("loadingSpinner");
                                    $scope.clearForm();

                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully saved your [asis,ModSecurity™] rule with the following ID: [_1].", _.escape(rule.id)),
                                        id: "alertAddSuccess",
                                        replace: true,
                                    });

                                    if (exit) {
                                        $scope.loadView("rulesList");
                                    } else {

                                        if ( $scope.isCopy ) {
                                            $scope.getClonedRule(rule);
                                        }

                                        // refocus the user for the next add
                                        $scope.scrollTo("top");
                                        document.getElementById("txtRuleText").focus();
                                    }
                                },

                                /**
                                 * Handle failure of adding the rule
                                 * @method failure
                                 * @private
                                 * @param  {Object} error Error from the backend.
                                 *   @param {String} message
                                 *   @param {Boolean} duplicate true if this is a duplicate queue item, false otherwise.
                                 */
                                function failure(error) {
                                    $scope.notice = "";
                                    if (error && error.duplicate) {
                                        alertService.add({
                                            type: "warning",
                                            message: LOCALE.maketext("There is a duplicate [asis,ModSecurity™] rule in the staged configuration file. You cannot add a duplicate rule."),
                                            id: "alertAddWarning",
                                        });
                                    } else {
                                        var message = error.message || error; // It can come from either structured or unstructured errors
                                        alertService.add({
                                            type: "danger",
                                            message: _.escape(message),
                                            id: "alertAddFailure",
                                        });
                                    }

                                    // ensure the error is in view and focus is in the rule field
                                    $scope.scrollTo("top");
                                    document.getElementById("txtRuleText").focus();
                                },

                                /**
                                 * Handle step wise updating
                                 * @method notify
                                 * @private
                                 * @param  {Rule} rule Rule added to the system
                                 */
                                function notify(notice) {
                                    $scope.notice += notice + "\n";
                                }
                            ).finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    /**
                 * Disable the rule that
                 *
                 * @method disableOriginalRule
                 * @param  {object}  rule            The original rule to be disabled
                 * @param  {string}  rule.id         The id of the original rule
                 * @param  {string}  rule.config     The configuration file of the original file
                 * @param  {Boolean} rule.disabled   Is the rule disabled?
                 * @return {Promise}
                 */
                    $scope.disableOriginalRule = function(rule) {
                        return ruleService
                            .disableRule(rule.config, rule.id, false)
                            .then(

                                /**
                                 * Handle successfully disabling the original rule
                                 * @method success
                                 * @private
                                 */
                                function success() {
                                    rule.disabled = true;
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully disabled the [asis,ModSecurity™] rule with the following ID: [_1]", _.escape(rule.id)),
                                        id: "alertDisableSuccess",
                                    });
                                },

                                /**
                                 * Handle failure of cloning the rule
                                 * @method failure
                                 * @private
                                 * @param  {Object} error Error from the backend.
                                 *   @param {String} message
                                 */
                                function failure(error) {
                                    var message = error.message || error;
                                    alertService.add({
                                        type: "danger",
                                        message: message,
                                        id: "alertDisableFailure",
                                    });
                                }
                            ).finally(function() {

                                // ensure the alert is in view and focus is in the rule field
                                $scope.scrollTo("top");
                                document.getElementById("txtRuleText").focus();
                            });
                    };

                    /**
                 * Retrieve a copy of the rule with a unique id
                 *
                 * @method getClonedRule
                 * @param  {object}  rule            The original rule to be cloned
                 * @param  {string}  rule.id         The id of the original rule
                 * @param  {string}  rule.config     The configuration file of the original file
                 * @param  {Boolean} rule.disabled   Is the rule disabled?
                 * @return {Promise}
                 */
                    $scope.getClonedRule = function(rule) {
                        spinnerAPI.start("loadingSpinner");
                        return ruleService
                            .cloneRule(rule.id, rule.config)
                            .then(

                                /**
                                 * Handle successfully cloning the rule
                                 * @method success
                                 * @private
                                 * @param  {Rule} rule The cloned rule with a unique id ready to be saved
                                 */
                                function success(rule) {
                                    $scope.id = rule.id;
                                    $scope.enabled = !rule.disabled;
                                    $scope.rule = rule.rule;

                                    // activate the save buttons
                                    $scope.form.rule.$pristine = false;
                                },

                                /**
                                 * Handle failure of cloning the rule
                                 * @method failure
                                 * @private
                                 * @param {Object} error           Error from the backend.
                                 * @param {String} error.message   The error message.
                                 */
                                function failure(error) {
                                    var message = error.message || error;
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(message),
                                        id: "alertCopyFailure",
                                    });

                                    // ensure the error is in view and focus is in the rule field
                                    $scope.scrollTo("top");
                                    document.getElementById("txtRuleText").focus();
                                }
                            ).finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {
                        $scope.loadView("hitList");
                    }

                    // Initialize the form on first load.
                    $scope.clearForm();

                    // check for copy of existing rule
                    if ( $location.$$path.indexOf("copy") !== -1 ) {
                        $scope.originalRule = {
                            id: $routeParams["id"],
                            config: $routeParams["config"],
                            disabled: $routeParams["disabled"],
                        };
                        if ( $scope.originalRule.id && $scope.originalRule.config ) {
                            $scope.isCopy = true;
                            $scope.getClonedRule($scope.originalRule);
                        }
                    }
                },
            ]);

        return controller;
    }
);

/*
# templates/mod_security/views/addRuleController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/editRuleController',[
        "angular",
        "lodash",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/ruleService",
    ],
    function(angular, _, $, LOCALE, PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "editRuleController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "spinnerAPI", "alertService", "ruleService", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, spinnerAPI, alertService, ruleService, PAGE) {

                    /**
                 * Disable the save button based on form state
                 *
                 * @method disableSave
                 * @param  {FormController} form
                 * @return {Boolean}
                 */
                    $scope.disableSave = function(form) {
                        var pristineInputs = form.rule.$pristine && form.enabled.$pristine;
                        return ($scope.isEditor && $scope.cantEdit) || pristineInputs || (form.$dirty && form.$invalid);
                    };

                    /**
                 * Clear the form
                 *
                 * @method clearForm
                 */
                    $scope.clearForm = function() {
                        $scope.enabled = false;
                        $scope.oldRule = 0;
                        $scope.ruleText = "";
                        $scope.deploy = false;
                        $scope.clearNotices();
                        $scope.cantEdit = false;
                    };

                    /**
                 * Clear the notices
                 *
                 * @method clearNotices
                 */
                    $scope.clearNotices = function() {
                        alertService.clear();
                        $scope.notice = "";
                    };

                    /**
                 * Navigate to the previous view.
                 *
                 * @method  cancel
                 */
                    $scope.cancel = function() {
                        $scope.clearNotices();
                        $scope.loadView(backRoute);
                    };

                    /**
                 * Save the form and navigate or clean depending on the users choices.
                 *
                 * @method save
                 * @param  {FormController} form
                 * @param  {Boolean} exit If true, will navigate back on completion, if false,
                 * will clear the form and let you add another rule.
                 * @return {Promise}
                 */
                    $scope.save = function(form, exit) {
                        $scope.clearNotices();

                        if (!form.$valid) {
                            return;
                        }

                        spinnerAPI.start("loadingSpinner");
                        return ruleService
                            .updateRule($scope.configFile, $scope.id, $scope.rule, $scope.enabled, $scope.enabled !== $scope.originalEnabled, $scope.deploy)
                            .then(

                                /**
                                 * Handle successfully adding the rule
                                 * @method success
                                 * @private
                                 * @param  {Rule} rule Rule added to the system
                                 */
                                function success(rule) {
                                    $scope.clearNotices();
                                    form.$setPristine();
                                    spinnerAPI.stop("loadingSpinner");
                                    $scope.clearForm();

                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully updated the [asis,ModSecurity™] rule."),
                                        id: "alertAddSuccess",
                                        replace: true,
                                    });

                                    app.firstLoad.rules = false;
                                    $scope.loadView("rulesList");
                                },

                                /**
                                 * Handle failure of adding the rule
                                 * @method failure
                                 * @private
                                 * @param  {Object} error Error from the backend.
                                 *   @param {String} message
                                 *   @param {Boolean} duplicate true if this is a duplicate queue item, false otherwise.
                                 */
                                function failure(error) {
                                    $scope.notice = "";
                                    if (error && error.duplicate) {
                                        alertService.add({
                                            type: "warning",
                                            message: LOCALE.maketext("There is a duplicate [asis,ModSecurity™] rule in the staged configuration file. You cannot add a duplicate rule."),
                                            id: "alertAddWarning",
                                        });
                                    } else {
                                        var message = error.message || error; // It can come from either structured or unstructured errors
                                        alertService.add({
                                            type: "danger",
                                            message: _.escape(message),
                                            id: "alertAddFailure",
                                        });
                                    }

                                    // ensure the error is in view and focus is in the rule field
                                    $scope.scrollTo("top");
                                    document.getElementById("txtRuleText").focus();
                                },

                                /**
                                 * Handle step wise updating
                                 * @method notify
                                 * @private
                                 * @param  {Rule} rule Rule added to the system
                                 */
                                function notify(notice) {
                                    $scope.notice += notice + "\n";
                                }
                            ).then(
                                function finish() {
                                    spinnerAPI.stop("loadingSpinner");
                                }
                            );
                    };

                    /**
                 * Fetch the list of hits from the server
                 *
                 * @method fetchRule
                 * @param {Number} ruleId       The numeric ID of the rule.
                 * @param {String} [vendorId]   Optional unique vendor ID string. If this is not
                 *                              included, we will search for the rule in the user
                 *                              defined rule set.
                 * @return {Promise}            Promise that when fulfilled with contain the matching
                 *                              rules, only one if the file isn't messed up with
                 *                              duplicate id's. Defensive logic is in place for other
                 *                              conditions. > 1 match and no matches.
                 */
                    var fetchRule = function(ruleId, vendorId) {
                        spinnerAPI.start("loadingSpinner");
                        return ruleService
                            .fetchRulesById(ruleId, vendorId)
                            .then(function(results) {

                                // May be useful
                                $scope.stagedChanges = results.stagedChanges;
                                var matchedRule = results.items[0];
                                $scope.id = matchedRule.id;
                                $scope.enabled = !PARSE.parsePerlBoolean(matchedRule.disabled);
                                $scope.originalEnabled = $scope.enabled;
                                $scope.meta_msg = matchedRule.meta_msg;
                                $scope.rule = matchedRule.rule;
                                $scope.cantEdit = false;
                                $scope.configFile = matchedRule.config;

                                // If the vendor or config isn't active, we should let the user know
                                if (matchedRule.vendor_id && (!matchedRule.vendor_active || !matchedRule.config_active)) {
                                    var message = !matchedRule.vendor_active ?
                                        LOCALE.maketext("The vendor that provides the rule “[_1]” is disabled. Whether enabled or disabled, the rule will have no visible effect until you enable that vendor.", matchedRule.vendor_id) :
                                        LOCALE.maketext("The configuration file that provides the rule “[_1]” is disabled. Whether enabled or disabled, the rule will have no visible effect until you enable the configuration file for the “[_2]” vendor.", matchedRule.config, matchedRule.vendor_id);

                                    alertService.add({
                                        type: "warning",
                                        message: message,
                                        id: "alertDisabledWarning",
                                        replace: false,
                                    });
                                }

                            }, function(error) {
                                var message;
                                if (error.count > 1) {
                                    message = vendorId ?
                                        LOCALE.maketext("The rule with ID number “[_1]” is not unique. There are multiple rules that use the same ID number within the “[_2]” vendor rule set.", ruleId, vendorId) :
                                        LOCALE.maketext("The rule with ID number “[_1]” is not unique. There are multiple rules that use the same ID number within your user-defined rule set.", ruleId);

                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(message),
                                        id: "alertEditError",
                                    });
                                } else if (error.count < 1) {
                                    message = vendorId ?
                                        LOCALE.maketext("The system could not find the rule with ID number “[_1]” from the “[_2]” vendor rule set.", ruleId, vendorId) :
                                        LOCALE.maketext("The system could not find the rule with ID number “[_1]” from your user-defined rule set.", ruleId);

                                    alertService.add({
                                        type: "warning",
                                        message: _.escape(message),
                                        id: "alertEditWarning",
                                    });
                                } else {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error.message),
                                        id: "errorFetchRulesList",
                                    });
                                }

                                $scope.cantEdit = true;
                            })
                            .finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {
                        $scope.loadView("hitList");
                    }

                    // Initialize the form on first load.
                    $scope.isVendor = !!$routeParams.vendorId;
                    $scope.isEditor = true;
                    $scope.cantEdit = true;
                    $scope.clearForm();

                    var ruleId = $routeParams["ruleId"];
                    var vendorId = $routeParams["vendorId"];
                    var backRoute = $routeParams["back"];
                    if (!backRoute) {
                        backRoute = "rulesList";
                    }

                    if (angular.isUndefined(ruleId)) {
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("The system could not find the ID number for this rule."),
                            id: "alertNoIdError",
                        });
                        $scope.cantEdit = true;
                    } else {

                        // Let the user know that they can only toggle it on or off if it's a vendor rule
                        if ($scope.isVendor) {
                            alertService.add({
                                type: "info",
                                message: LOCALE.maketext("A vendor configuration file provides this rule. You cannot edit vendor rules. You can enable or disable this rule with the controls below."),
                                id: "alertVendorRuleInfo",
                            });
                        }
                        fetchRule(ruleId, vendorId);
                    }

                },
            ]);

        return controller;
    }
);

/*
# templates/mod_security/views/massEditRuleController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/massEditRuleController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "jquery",
        "cjt/jquery/plugins/rangeSelection",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/ruleService",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "massEditRuleController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "$q", "$timeout", "ruleService", "alertService", "spinnerAPI", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, $q, $timeout, ruleService, alertService, spinnerAPI, PAGE) {

                    // CONSTANTS
                    var ANIMATION_INTER_STEP_DELAY = 500; // in milliseconds.

                    /**
                 * Disable the save button based on form state
                 *
                 * @method disableSave
                 * @param  {FormController} form
                 * @return {Boolean}
                 */
                    $scope.disableSave = function(form) {
                        return $scope.cantEdit || form.txtRules.$pristine || (form.$dirty && form.$invalid);
                    };

                    /**
                 * Clear the form
                 *
                 * @method clearForm
                 */
                    $scope.clearForm = function() {
                        $scope.enabled = true;
                        $scope.rules = "";
                        $scope.deploy = false;
                        $scope.clearNotices();
                        $scope.cantEdit = false;
                    };

                    /**
                 * Clear the notices
                 *
                 * @method clearNotices
                 */
                    $scope.clearNotices = function() {
                        alertService.clear();
                        $scope.notice = "";
                    };

                    /**
                 * Navigate to the previous view.
                 *
                 * @method  cancel
                 */
                    $scope.cancel = function() {
                        $scope.clearNotices();
                        $scope.loadView("rulesList");
                    };

                    /**
                 * Save the form and navigate or clean depending on the users choices.
                 *
                 * @method save
                 * @param  {FormController} form
                 * @return {Promise}
                 */
                    $scope.save = function(form) {
                        $scope.clearNotices();

                        if (!form.$valid) {
                            return;
                        }

                        spinnerAPI.start("loadingSpinner");
                        $scope.progress = 0;
                        $scope.cantEdit = true;
                        return ruleService
                            .setCustomConfigText($scope.rules, $scope.deploy)
                            .then(function() {

                                // on success, update alert and load the view
                                spinnerAPI.stop("loadingSpinner");
                                $timeout(function() {
                                    $scope.progress = 100;
                                    $timeout(function() {

                                        // success
                                        if ($scope.deploy) {
                                            alertService.add({
                                                type: "success",
                                                message: LOCALE.maketext("You have successfully saved and deployed your [asis,ModSecurity™] rules."),
                                                id: "alertSaveSuccess",
                                            });
                                        } else {
                                            alertService.add({
                                                type: "success",
                                                message: LOCALE.maketext("You have successfully saved your [asis,ModSecurity™] rules."),
                                                id: "alertSaveSuccess",
                                            });
                                        }

                                        $timeout(function() {
                                            $scope.loadView("rulesList");
                                            $scope.showProgress = false;
                                        }, 2 * ANIMATION_INTER_STEP_DELAY);
                                    }, 2 * ANIMATION_INTER_STEP_DELAY);
                                }, 2 * ANIMATION_INTER_STEP_DELAY);
                            }, function(error) {
                                spinnerAPI.stop("loadingSpinner");
                                $scope.cantEdit = false;
                                if (error) {

                                    // failures like timeout, lost connection, etc.
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        id: "errorFetchRules",
                                    });
                                }

                                // ensure the any notifications and/or the final error is in view and focus is in the rule field
                                $timeout(function() {
                                    $scope.scrollTo("top");
                                    document.getElementById("txtRules").focus();
                                }, 2 * ANIMATION_INTER_STEP_DELAY);

                            }, function(data) {

                                switch (data.type) {
                                    case "post":

                                        // Only show the progress if there are more then 2 pages
                                        if (data.totalPages > 2) {
                                            $scope.showProgress = true;
                                        }

                                        // Update the progress
                                        $scope.progress = Math.floor(data.page / data.totalPages * 100);
                                        break;
                                    case "error":

                                        // api related failures.
                                        alertService.add({
                                            type: "danger",
                                            message: _.escape(data.error),
                                            id: "errorSaveRules",
                                        });
                                        break;
                                }
                            });
                    };

                    /**
                 * Fetch the config text from the user defined rules file
                 * @return {Promise} Promise that will fulfill the request.
                 */
                    var fetchRules = function() {
                        spinnerAPI.start("loadingSpinner");
                        $scope.progress = 0;
                        $scope.cantEdit = true;
                        return ruleService
                            .getCustomConfigText()
                            .then(angular.noop, function(error) {
                                if (error) {

                                    // failures like timeout, lost connection, etc.
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        id: "errorFetchRules",
                                    });
                                }
                            }, function(data) {
                                switch (data.type) {
                                    case "page":

                                        // Only show the progress if there are more then 2 pages
                                        if (data.totalPages > 2) {
                                            $scope.showProgress = true;
                                        }

                                        if (data.text) {

                                            // Update the progress
                                            $scope.progress = Math.floor(data.page / data.totalPages * 100);

                                            // Append
                                            $scope.rules += data.text.join("");
                                        }
                                        break;
                                    case "error":

                                        // api related failures.
                                        alertService.add({
                                            type: "danger",
                                            message: _.escape(data.error),
                                            id: "errorFetchRules",
                                        });
                                        break;
                                }
                            })
                            .finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                                $timeout(function() {
                                    $scope.progress = 100;
                                    $timeout(function() {

                                        // delayed for a little so the progress bar can finish
                                        $scope.cantEdit = false;
                                        $scope.showProgress = false;
                                        $timeout(function() {
                                            $scope.progress = 0;
                                            angular.element(document.querySelector( "#txtRules" )).selectRange(0);
                                        }, ANIMATION_INTER_STEP_DELAY);
                                    }, ANIMATION_INTER_STEP_DELAY);
                                }, ANIMATION_INTER_STEP_DELAY);

                            });
                    };

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {
                        $scope.loadView("hitList");
                    }

                    // Initialize the form on first load.
                    $scope.showProgress = false;
                    $scope.cantEdit = true;
                    $scope.clearForm();
                    fetchRules();
                },
            ]);

        return controller;
    }
);

/*
# templates/mod_security/views/reportController.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                             All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define('app/views/reportController',[
    "angular",
    "cjt/util/locale",
    "uiBootstrap",
    "app/services/reportService",
    "cjt/validator/email-validator",
    "cjt/directives/validationContainerDirective",
    "cjt/directives/validationItemDirective",
    "cjt/directives/spinnerDirective",
    "cjt/filters/wrapFilter",
    "cjt/filters/breakFilter",
],
function(angular, LOCALE) {
    angular.module("App")
        .controller("reportController", [
            "$scope",
            "reportService",
            "alertService",
            "$route",
            "$window",
            "$location",
            "spinnerAPI",
            function(
                $scope,
                reportService,
                alertService,
                $route,
                $window,
                $location,
                spinnerAPI
            ) {

                var view, report;

                function initialize() {

                    /**
                         * The view model. Contains items only needed for the view.
                         *
                         * @property {String}  step                     The name of the form submission step the user is on
                         * @property {String}  vendorId                 The vendor_id from the API
                         * @property {Object}  isDisabled               Contains various standardized disabled flags
                         *     @property {Boolean} isDisabled.rule      Is the rule itself disabled?
                         *     @property {Boolean} isDisabled.config    Is the config housing this rule disabled?
                         *     @property {Boolean} isDisabled.vendor    Is the vendor providing this rule disabled?
                         *     @property {Boolean} isDisabled.overall   Is the rule disabled at any of the previous levels?
                         * @property {Number}  includedHitCount         The number of included hits in the report
                         * @property {Object}  expandedHit              The hit object that is currently expanded
                         * @property {Object}  form                     The angular form controller for the main form
                         * @property {Object}  loading                  An object with basic loading flags.
                         *     @property {Boolean} loading.init         Are the hits and rule loading?
                         *     @property {Boolean} loading.report       Is the generated report loading?
                         * @property {Boolean} submitting               Is the report submitting?
                         * @property {Boolean} rawReportActive          Is the rawReport tab active?
                         * @property {Array}   lastIncludedHitIds         This is an array of hit IDs that were included in the last report generated for the raw report tab
                         */
                    view = $scope.view = {
                        step: "input",
                        loading: {
                            init: false,
                            report: false
                        },
                        submitting: false,
                        ruleExpanded: false
                    };

                    /**
                         * This object stores all of the items relevant to generating and submitting a report.
                         *
                         * @property {Array}  hits     An array of hit objects that are associated with the rule
                         * @property {Object} rule     The rule object for the rule being reported
                         * @property {Object} inputs   The values that the user inputs on the form
                         */
                    report = $scope.report = {
                        hits: null,
                        rule: null,
                        inputs: {}
                    };

                    // pathParams should include hitId or ruleId properties
                    _getReport($route.current.pathParams).then(_updateViewModel);
                }

                /**
                     * Attempts to get the last promise from the report service that was created using fetchByHit
                     * or fetchByRule. If it's not available, use the lookup object to get a new one. This promise
                     * resolves with a rule object a list of associated hits and is used to populate the report
                     * $scope object.
                     *
                     * @param  {Object} lookup   This object should have either a hitId or ruleId/vendorId property
                     * @return {Promise}         This is either cached or newly fetched promise
                     */
                function _getReport(lookup) {
                    view.loading.init = true;

                    // Check to see if there's a cached promise. If not, get a new one depending on the lookup data.
                    var reportPromise = reportService.getCurrent();
                    if (!reportPromise) {
                        if (lookup.hitId) {
                            reportPromise = reportService.fetchByHit(lookup.hitId);
                        } else if (lookup.ruleId && lookup.vendorId) {
                            reportPromise = reportService.fetchByRule(lookup.ruleId, lookup.vendorId);
                        } else {
                            throw new ReferenceError("Cannot populate the report without a ruleId or hitId.");
                        }
                    }

                    reportPromise.then(
                        function success(response) {
                            if (report.invalid) {
                                delete report.invalid;
                            }

                            report.rule = response.rule;
                            report.hits = response.hits.map(function(hit) {
                                hit.included = true;
                                return hit;
                            });
                            view.includedHitCount = report.hits.length;
                        },
                        function failure(error) {
                            report.invalid = true;
                            if (error && error.message) {
                                alertService.add({
                                    type: "danger",
                                    message: error.message,
                                    id: "report-retrieval-error"
                                });
                            } else {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "report-retrieval-error"
                                });
                            }
                        }
                    ).finally(function() {
                        view.loading.init = false;
                    });

                    return reportPromise;
                }

                /**
                     * Update various bits of the view model with the results from the initial fetch.
                     *
                     * @method _updateViewModel
                     */
                function _updateViewModel() {
                    view.vendorId = report.rule.vendor_id;
                    view.isDisabled = {
                        overall: report.rule.disabled || !report.rule.config_active || !report.rule.vendor_active,
                        rule: report.rule.disabled,
                        config: !report.rule.config_active,
                        vendor: !report.rule.vendor_active
                    };
                }

                /**
                     * Get the text for the page title. If we have a vedor ID string, then we'll use it.
                     *
                     * @method getTitleText
                     * @return {String}   The title
                     */
                function getTitleText() {
                    return view.vendorId ?
                        LOCALE.maketext("Report a [asis,ModSecurity] Rule to [_1]", view.vendorId) :
                        LOCALE.maketext("Report a [asis,ModSecurity] Rule");
                }

                /**
                     * Is the hit currently expanded?
                     *
                     * @method isExpanded
                     * @param  {Object}  hit   A hit object
                     *
                     * @return {Boolean}       Is it expanded?
                     */
                function isExpanded(hit) {
                    return view.expandedHit === hit;
                }

                /**
                     * Toggle the expanded or collapsed state of a hit in the table
                     * view. Only one hit will be expanded at a time.
                     *
                     * @method toggleExpandCollapse
                     * @param  {Object} hit   A hit object
                     */
                function toggleExpandCollapse(hit) {
                    view.expandedHit = view.expandedHit === hit ? null : hit;
                }

                /**
                     * Toggles the state of the hit as included or excluded from the report.
                     *
                     * @method toggleIncludeExclude
                     * @param  {Object} hit   A hit object
                     */
                function toggleIncludeExclude(hit) {
                    if (view.includedHitCount === 1) {
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("You must include at least one hit record with your report."),
                            id: "report-last-hit-info"
                        });
                        return;
                    }

                    hit.included = !hit.included;
                    view.includedHitCount--;
                }

                /**
                     * Generates an array of hit IDs that the user has elected to include with the report.
                     * @return {Array}   An array of numbers corresponding to hit IDs.
                     */
                function _includedHitIds() {
                    var includedHits = [];

                    if (report.hits) {
                        report.hits.forEach(function(hit) {
                            if (hit.included) {
                                includedHits.push(hit.id);
                            }
                        });
                    }

                    return includedHits;
                }

                /**
                     * Gathers all of the required report parameters together.
                     *
                     * @method _consolidateReportInputs
                     * @return {Object}   An object suitable to pass to the reportService as reportParams
                     */
                function _consolidateReportInputs() {
                    return {
                        hits: _includedHitIds(),
                        email: report.inputs.email,
                        reason: report.inputs.reason,
                        message: report.inputs.comments
                    };
                }

                /**
                     * Duct tape for a bug with UI Bootstrap tabs that has already been fixed upstream.
                     * Basically the select callbacks are run on $destroy so it resulted in extra net
                     * requests for no reason.
                     *
                     * Issue thread here: https://github.com/angular-ui/bootstrap/issues/2155
                     * Fixed here: https://github.com/lanetix/bootstrap/commit/4d77f3995bb357741a86bcd48390c8bb2e9954e7
                     */
                var destroyed;
                $scope.$on("$destroy", function() {
                    destroyed = true;
                });

                /**
                     * Callback when changing tabs.
                     *
                     * @method changeToTab
                     * @param  {String} tabName   The name of the tab
                     */
                function changeToTab(tabName) {
                    if (!destroyed) { // See workaround documentation directly above this method

                        // Trying to remove the last hit in the associated hit list gives an alert, so remove it if we're heading to another tab
                        if (tabName !== "hitList") {
                            alertService.removeById("report-last-hit-info");
                        }

                        // If it's the raw report tab, fetch the report
                        if (tabName === "rawReport") {
                            _updateRawTab();
                        }
                    }
                }

                /**
                     * Check to see if the included hits have changed since the last preview was generated.
                     *
                     * @method _includedHitIdsChanged
                     * @return {Boolean}   True if the included hit ids have changed
                     */
                function _includedHitIdsChanged() {
                    var currentIds = _includedHitIds();

                    if (!view.lastIncludedHitIds || currentIds.length !== view.lastIncludedHitIds.length) {
                        return false;
                    } else {
                        return currentIds.some(function(val, index) {
                            return view.lastIncludedHitIds.indexOf(val) === -1;
                        });
                    }
                }

                /**
                     * Check to see if the generated report in the raw tab is stale, i.e. there
                     * is new information in the form or if the selected/included hits differ from
                     * the last time the report was generated.
                     *
                     * @method rawTabIsStale
                     * @return {Boolean}   True if the generated report is stale
                     */
                function rawTabIsStale() {
                    return view.form.$dirty || _includedHitIdsChanged();
                }

                /**
                     * Fetches the JSON for the generated report and updates report.json
                     *
                     * @method _updateRawTab
                     */
                function _updateRawTab() {
                    if (rawTabIsStale()) {

                        // Reset the two stale conditions
                        view.form.$setPristine();
                        view.lastIncludedHitIds = _includedHitIds();

                        viewReport().then(
                            function(response) {
                                report.json = JSON.stringify(response, false, 2);
                            },
                            function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "fetch-generated-report-error"
                                });
                            }
                        );
                    }
                }

                /**
                     * Fetch a generated report.
                     *
                     * @method viewReport
                     * @return {Promise}   Resolves with the report as a parsed object.
                     */
                function viewReport() {
                    view.loading.report = true;

                    return reportService.viewReport(_consolidateReportInputs()).finally(function() {
                        view.loading.report = false;
                    });
                }

                /**
                     * Submit the report and optionally disable the rule.
                     *
                     * @method submitReport
                     * @return {Promise}   Resolves when the report has been sent and the rule has
                     *                     been disabled, if the user chose to disable the rule.
                     */
                function submitReport() {
                    alertService.clear();
                    view.submitting = true;

                    var promise, disableParams;

                    // Send disable params if the rule is enabled and the user wants to disable
                    if (!view.isDisabled.rule && report.inputs.disableRule) {
                        disableParams = {
                            deployRule: report.inputs.deployRule,
                            ruleConfig: report.rule.config,
                            ruleId: report.rule.id
                        };

                        promise = reportService.sendReport(_consolidateReportInputs(), disableParams);
                    } else {
                        promise = reportService.sendReport(_consolidateReportInputs());
                    }

                    promise.then(
                        function success(response) {
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("You have successfully submitted a report for the rule ID “[_1]” to “[_2]”.", report.rule.id, view.vendorId),
                                id: "report-rule-submit-success"
                            });

                            $scope.loadView("hitList");
                        },
                        function failure(error) {
                            alertService.add({
                                type: "warning",
                                message: error,
                                id: "report-rule-submit-error"
                            });
                        }
                    ).finally(function() {
                        view.submitting = false;
                    });

                    return promise;
                }

                /**
                     * The user no longer wants to submit the report, so send them back to where
                     * they came from if we have history. If not, take them to the appropriate
                     * place based on their route params.
                     *
                     * @method cancelSubmission
                     */
                function cancelSubmission() {
                    alertService.clear();

                    if ($location.state) {
                        $window.history.back();
                    } else if ($route.current.pathParams.hitId) {
                        $scope.loadView("hitList");
                    } else {
                        $scope.loadView("rulesList");
                    }
                }

                /**
                     * Changes the submission step.
                     *
                     * @param  {String} newStep   The name of the new step
                     */
                function changeStep(newStep) {
                    view.step = newStep;

                    // If we're coming back to the review page and the raw tab is active,
                    // we need to update the report.
                    if (newStep === "review" && view.rawReportActive) {
                        _updateRawTab();
                    }
                }

                // Extend scope with the public methods
                angular.extend($scope, {
                    getTitleText: getTitleText,
                    isExpanded: isExpanded,
                    toggleExpandCollapse: toggleExpandCollapse,
                    toggleIncludeExclude: toggleIncludeExclude,
                    changeToTab: changeToTab,
                    viewReport: viewReport,
                    submitReport: submitReport,
                    cancelSubmission: cancelSubmission,
                    changeStep: changeStep,
                    rawTabIsStale: rawTabIsStale
                });

                initialize();
            }
        ])
        .filter("onlyTrueHitFields", function() {
            var EXCLUDED_KEYS = ["included", "reportable", "file_exists"];

            /**
                 * Filters out any fields that are added to modsec_get_log results that don't exist in the database.
                 * @param  {Object} hitObj   The hit object
                 *
                 * @return {Object}          A copy of the hit object with synthetic keys filtered out
                 */
            return function(hitObj) {
                var filteredObj = {};
                angular.forEach(hitObj, function(val, key) {
                    if (EXCLUDED_KEYS.indexOf(key) === -1) {
                        filteredObj[key] = val;
                    }
                });

                return filteredObj;
            };
        });
}
);

/*
# templates/mod_security/index.js                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
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
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",

                    // Application Modules
                    "cjt/views/applicationController",
                    "cjt/filters/breakFilter",
                    "app/views/commonController",
                    "app/views/hitListController",
                    "app/views/rulesListController",
                    "app/views/addRuleController",
                    "app/views/editRuleController",
                    "app/views/massEditRuleController",
                    "app/views/reportController",
                    "cjt/services/autoTopService",
                    "cjt/services/whm/breadcrumbService"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        hitList: true,
                        rules: true
                    };

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/hitList", {
                                controller: "hitListController",
                                templateUrl: CJT.buildFullPath("mod_security/views/hitListView.ptt"),
                                breadcrumb: LOCALE.maketext("Hits List"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/rulesList", {
                                controller: "rulesListController",
                                templateUrl: CJT.buildFullPath("mod_security/views/rulesListView.ptt"),
                                breadcrumb: LOCALE.maketext("Rules List"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/addCustomRule", {
                                controller: "addRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/addEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Add Custom Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/copyCustomRule", {
                                controller: "addRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/addEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Copy Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editCustomRule", {
                                controller: "editRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/addEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Edit Custom Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editCustomRules", {
                                controller: "massEditRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/massEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Edit Custom Rules"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/report/hit/:hitId", {
                                controller: "reportController",
                                templateUrl: CJT.buildFullPath("mod_security/views/reportView.ptt"),
                                breadcrumb: LOCALE.maketext("Report ModSecurity Hit"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/report/:vendorId/rule/:ruleId", {
                                controller: "reportController",
                                templateUrl: CJT.buildFullPath("mod_security/views/reportView.ptt"),
                                breadcrumb: LOCALE.maketext("Report ModSecurity Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                redirectTo: function(routeParams, path, search) {
                                    return "/hitList?" + window.location.search;
                                }
                            });
                        }
                    ]);

                    app.run(["autoTopService", "breadcrumbService", function(autoTopService, breadcrumbService) {

                        // Setup the automatic scroll to top for view changes
                        autoTopService.initialize();

                        // Setup the breadcrumbs service
                        breadcrumbService.initialize();
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

