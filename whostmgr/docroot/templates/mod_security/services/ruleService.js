/*
# mod_security/services/ruleService.js            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [

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
