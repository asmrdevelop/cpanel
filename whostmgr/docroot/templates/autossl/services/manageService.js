/*
# Copyright 2022 cPanel, L.L.C. - All rights reserved.
# copyright@cpanel.net
# https://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */
/* jshint -W089 */

define(
    [
        "lodash",
        "angular",
        "cjt/util/parse",
        "cjt/util/query",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it’s ready
    ],
    function(_, angular, CJT_PARSE, QUERY, API, APIREQUEST) {
        "use strict";

        var app = angular.module("App");

        var NO_MODULE = "";

        // Calculated by:
        // +1 for each supported DCV method (x2 if provider supports ancestor DCV)
        // +1 for lowest AVERAGE_DELIVERY_TIME
        // +1 for highest RATE_LIMIT_CERTIFICATES_PER_REGISTERED_DOMAIN_PER_WEEK
        // +1 for highest MAX_DOMAINS_PER_CERTIFICATE
        // +1 for highest HTTP_DCV_MAX_REDIRECTS
        // +1 for SUPPORTS_WILDCARD
        var MAX_USABILITY_SCORE = 8;

        var _tableColumns = [];

        function TableColumn(label, desc, starRating) {
            this.label = label;
            this.desc = desc;
            this.isScorePart = starRating ? true : false;
            this.starRating = starRating || 0;
            this.getLabel = function() {
                return this.label;
            };
            this.getDescription = function() {
                if (!this.desc) {
                    return "";
                }
                var combinedDesc = "";
                combinedDesc += this.desc;
                if (this.starRating) {
                    combinedDesc += "<br />";
                    combinedDesc += "<em>";
                    combinedDesc += this._starDescription();
                    combinedDesc += "</em>";
                }
                return combinedDesc;
            };
            this._starDescription = function() {
                return LOCALE.maketext("A maximum of [quant,_1,star,stars] is possible.", this.starRating);
            };
        }

        function DCVMethodsColumn(label, desc, starRating) {
            TableColumn.call(this, label, desc, starRating);
            this._starDescription = function() {
                var desc = "";
                desc += LOCALE.maketext("A maximum of 2 stars per method if the provider supports Ancestor DCV.");
                desc += " ";
                desc += LOCALE.maketext("Otherwise, a maximum of 1 star per method.");
                return desc;
            };
        }
        function SummaryColumn(label, desc, starRating) {
            TableColumn.call(this, label, desc, starRating);
            this.isScorePart = false;
        }

        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Provider") );
        _tableColumns[_tableColumns.length] = new SummaryColumn( LOCALE.maketext("Usability Score"), LOCALE.maketext("The capabilities of a provider determine the provider’s rank."), MAX_USABILITY_SCORE);
        _tableColumns[_tableColumns.length] = new DCVMethodsColumn( LOCALE.maketext("DCV Methods"), LOCALE.maketext("The Domain Control Validation methods that the provider offers."), 4 );
        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Ancestor DCV Support"), LOCALE.maketext("Whether the successful Domain Control Validation of a parent domain implies the success of a subdomain. For example, if “example.com” succeeds, “store.example.com” would succeed.") );
        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Domains per Certificate"), LOCALE.maketext("The number of unique domains each certificate can contain."), 1 );
        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Delivery Method"), LOCALE.maketext("The method that the provider uses to issue the certificate.") );
        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Average Delivery Time"), LOCALE.maketext("The amount of time that the provider requires to issue a certificate."), 1 );
        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Validity Period"), LOCALE.maketext("The amount of time before the certificate expires.") );
        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Maximum Number of Redirects"), LOCALE.maketext("The maximum number of redirections a domain can use and still pass an HTTP-based Domain Control Validation."), 1 );

        _tableColumns[_tableColumns.length] = new TableColumn( LOCALE.maketext("Wildcard Support"), LOCALE.maketext("The provider supports wildcard domains."), 1 );

        function manageServiceFactory($q, $interval, PAGE) {

            function apiCallPromise(apiCall) {
                var deferred = $q.defer();
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;

                        deferred[response.status ? "resolve" : "reject"](response);
                    });

                return deferred.promise;
            }

            // XXX TODO: Refactor this to be reusable.
            function _call_apiv1(call_info) {

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, call_info.func);

                if (call_info.data) {
                    for (var k in call_info.data) {
                        apiCall.addArgument(k, call_info.data[k]);
                    }
                }

                return apiCallPromise(apiCall);
            }

            // XXX TODO: Refactor this to be reusable.
            function _batch_apiv1(calls_infos) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "batch");

                calls_infos.forEach(function(call, i) {
                    apiCall.addArgument(
                        ("command-" + i),
                        call.func + "?" + QUERY.make_query_string(call.data)
                    );
                });

                return apiCallPromise(apiCall);
            }

            // NB: There’s no particular reason to use epoch seconds here;
            // that’s just what this started off as, and changing it now
            // isn’t really worthwhile.
            function _convert_iso_to_epoch(things, key) {
                for (var r = 0; r < things.length; r++) {
                    if (!things[r][key]) {
                        continue;
                    }

                    things[r][key + "_epoch"] = Date.parse(things[r][key]) / 1000;
                }
            }

            var _bestSpecsList = ["AVERAGE_DELIVERY_TIME", "MAX_DOMAINS_PER_CERTIFICATE", "HTTP_DCV_MAX_REDIRECTS"];
            var _bestScores = {};

            function _updateUsabilityScore(provider) {
                var usabilityScore = 0;

                // For each DCV method ...
                usabilityScore += provider.specs.DCV_METHODS.length;

                // ... and counts double if ancestor dcv is supported
                if (provider.specs.SUPPORTS_ANCESTOR_DCV.toString() === "1") {
                    provider.specSpecifics["SUPPORTS_ANCESTOR_DCV"] = 1;
                    usabilityScore *= 2;
                }
                if (provider.specs.SUPPORTS_WILDCARD && provider.specs.SUPPORTS_WILDCARD.toString() === "1") {
                    provider.specSpecifics["SUPPORTS_WILDCARD"] = 1;
                    usabilityScore += 1;
                }
                _bestSpecsList.forEach(function(spec) {
                    if (provider.specs[spec] === _bestScores[spec]) {
                        provider.specSpecifics[spec] = 1;
                        usabilityScore++;
                    }
                });


                return usabilityScore;

            }

            var nullDefaults = {
                AVERAGE_DELIVERY_TIME: 1000000,
                RATE_LIMIT_CERTIFICATES_PER_REGISTERED_DOMAIN_PER_WEEK: -1,
                MAX_DOMAINS_PER_CERTIFICATE: -1,
            };

            // Find the best score based on
            function _findBestSpecScore(providers, spec) {

                if (_bestScores[spec]) {
                    return _bestScores[spec];
                }

                var findLowest = false;

                // These are best when they are highest
                // everything else is best when it's lowest
                if (["AVERAGE_DELIVERY_TIME"].indexOf(spec) !== -1) {
                    findLowest = true;
                }

                providers.forEach(function(provider) {
                    var value = _.isNil(provider.specs[spec]) && nullDefaults[spec] ? nullDefaults[spec] : provider.specs[spec];
                    if ( _.isUndefined(_bestScores[spec]) ) {
                        _bestScores[spec] = value;
                    } else if (spec === "RATE_LIMIT_CERTIFICATES_PER_REGISTERED_DOMAIN_PER_WEEK") {
                        if (_bestScores[spec] === 0) {

                            // Zero is the best score for this cause it's unlimited
                            return;
                        } else if (value.toString() === "0") {
                            _bestScores[spec] = 0;
                        } else {
                            if (value > _bestScores[spec]) {
                                _bestScores[spec] = value;
                            }
                        }
                    } else if ( findLowest && value < _bestScores[spec]) {
                        _bestScores[spec] = value;
                    } else if ( !findLowest && value > _bestScores[spec] ) {
                        _bestScores[spec] = value;
                    }
                });

                return _bestScores[spec];

            }

            // i.e., the system’s provider module setting
            var savedProviderModuleName;
            var currentProviderAccountID = PAGE.currentAccountID;

            PAGE.provider_info.forEach(function(p) {
                if (CJT_PARSE.parsePerlBoolean(p.enabled)) {
                    savedProviderModuleName = p.module_name;
                }
            });

            var metadataVars = [
                "clobber_externally_signed",
                "notify_autossl_expiry",
                "notify_autossl_expiry_coverage",
                "notify_autossl_renewal_coverage",
                "notify_autossl_renewal_coverage_reduced",
                "notify_autossl_renewal_uncovered_domains",
                "notify_autossl_renewal",
            ];

            metadataVars.forEach( function(v) {
                PAGE.metadata[v] = CJT_PARSE.parseInteger( PAGE.metadata[v] );
                if ( v !== "clobber_externally_signed" ) {
                    PAGE.metadata[v + "_user"] = CJT_PARSE.parseInteger( PAGE.metadata[v + "_user"] );
                }
            } );

            PAGE.constants.MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED = CJT_PARSE.parseInteger(
                PAGE.constants.MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED
            );

            var logsCatalog = _.sortBy(PAGE.logs_catalog, "start_time").reverse();

            // We save references to the $scope variables here upon view load.
            // That way, when/if the view is reloaded, we can grab any values
            // that we want to restore and put them into the controller.
            //
            // Note that the values on a saved scope will change after its
            // reference here is created.
            var SAVED_SCOPE = {};

            var providers = PAGE.provider_info;

            // Update the best scores because too many nest loops makes me uncomfortable
            _bestSpecsList.forEach(function(spec) {
                _findBestSpecScore(providers, spec);
            });

            providers.forEach(function(p) {

                p.specSpecifics = {};

                // so this checks the radio button correctly
                if (!p.x_terms_of_service_accepted) {
                    p.x_terms_of_service_accepted = "";
                }

                p.saved_x_terms_of_service_accepted = p.x_terms_of_service_accepted;

                p.usabilityScore = _updateUsabilityScore(p);
                p.maxUsabilityScore = MAX_USABILITY_SCORE;
            });

            providers.sort(function(a, b) {
                return b.usabilityScore - a.usabilityScore;
            });

            var nextAutosslCheckTime;
            var afterNextCheckRefresh;

            function refreshNextAutosslCheckTime() {
                return _call_apiv1({
                    func: "get_autossl_check_schedule",
                }).then(
                    function(resp) {
                        nextAutosslCheckTime = new Date(resp.data.next_time);
                        if (afterNextCheckRefresh) {
                            afterNextCheckRefresh(nextAutosslCheckTime);
                            afterNextCheckRefresh = null;
                        }

                        return nextAutosslCheckTime;
                    }
                );
            }

            // This is an interval, not a timeout, because it’s conceivable
            // that someone might tinker with their cron so that it only
            // runs once monthly. JS can’t handle timeouts greater than a
            // signed 32-bit integer, which gives us about 24 days.
            var nextTimeInterval;

            function nextTimeChecker() {
                var time = nextAutosslCheckTime;
                if (!time || time <= (new Date())) {
                    refreshNextAutosslCheckTime().then(function() {
                        if (!nextTimeInterval) {
                            nextTimeInterval = $interval(
                                nextTimeChecker,
                                60000 // 1 minute
                            );
                        }
                    });
                }
            }

            if (savedProviderModuleName) {
                nextTimeChecker();
            }

            function callProviderSetter(funcName, payload) {
                return _batch_apiv1([{
                    func: funcName,
                    data: payload,
                }, {
                    func: "get_autossl_check_schedule",
                }, {
                    func: "get_autossl_providers",
                }]).then(function(resp) {
                    var nextTimeIso = resp.data[1].parsedResponse.next_time;
                    nextAutosslCheckTime = new Date(nextTimeIso);

                    savedProviderModuleName = payload.provider;

                    var updatedProviders = resp.data[2].parsedResponse.data;

                    updatedProviders.forEach(function(provider) {
                        if (provider.enabled.toString() === "1") {
                            currentProviderAccountID = provider.x_account_id;
                        }
                    });

                    // This will set the interval to check whether
                    // it’s time to poll again.
                    nextTimeChecker();
                });
            }

            function _groom_logs_catalog(entries) {
                _convert_iso_to_epoch(entries, "start_time");
                for (var t = 0; t < entries.length; t++) {
                    entries[t].in_progress = CJT_PARSE.parsePerlBoolean(entries[t].in_progress);
                }
            }

            return {
                groom_logs_catalog: _groom_logs_catalog,

                get_next_autossl_check_time: function() {
                    return nextAutosslCheckTime;
                },

                refresh_next_autossl_check_time: refreshNextAutosslCheckTime,

                after_next_check_refresh: function(todoFn) {
                    if (typeof todoFn !== "function") {
                        throw "Needs a function!";
                    }

                    afterNextCheckRefresh = todoFn;
                },

                getTableColumns: function() {
                    return _tableColumns;
                },

                get_providers: function() {
                    return providers;
                },

                get_provider_display_name: function(p_mod_name) {
                    for (var p = 0; p < providers.length; p++) {
                        if (providers[p].module_name === p_mod_name) {
                            return providers[p].display_name;
                        }
                    }

                    return p_mod_name;
                },

                get_saved_provider_module_name: function() {
                    return savedProviderModuleName;
                },

                getSavedProviderAccountID: function getSavedProviderAccountID() {
                    return currentProviderAccountID;
                },

                // Called at the end of controller initialization.
                // The “key” identifies the view. If SAVED_SCOPE contains
                // a saved scope by that name, then we copy each of “props”
                // into the new scope. Once that’s done, “new_scope”
                // becomes the new SAVED_SCOPE[key], whose values will
                // be imported when/if the view is reloaded later.
                restore_and_save_scope: function(key, new_scope, props) {
                    if (SAVED_SCOPE[key]) {
                        props.forEach(function(p) {
                            new_scope[p] = SAVED_SCOPE[key][p];
                        });
                    }
                    SAVED_SCOPE[key] = new_scope;
                },

                get_logs_catalog: function() {
                    return logsCatalog;
                },

                refresh_logs_catalog: function() {
                    return _call_apiv1({
                        func: "get_autossl_logs_catalog",

                        // TODO: use abstraction layer
                        data: {
                            "api.sort.enable": 1,
                            "api.sort.a.field": "start_time",
                            "api.sort.a.reverse": 1,
                        },
                    }).then(
                        function(resp) {
                            resp = resp.data;
                            _groom_logs_catalog(resp, "start_time");
                            logsCatalog = resp;
                            return resp;
                        }
                    );
                },

                get_log: function(payload) {
                    return _call_apiv1({
                        func: "get_autossl_log",
                        data: payload,
                    }).then(
                        function(resp) {
                            resp = resp.data;
                            _convert_iso_to_epoch(resp, "timestamp");
                            return resp;
                        }
                    );
                },

                get_autossl_pending_queue: function() {
                    return _call_apiv1({
                        func: "get_autossl_pending_queue",
                    }).then(function(result) {
                        return result.data;
                    });
                },

                start_autossl_for_all_users: function() {
                    return _call_apiv1({
                        func: "start_autossl_check_for_all_users",
                    });
                },

                reset_provider_data: function(payload) {
                    return callProviderSetter(
                        "reset_autossl_provider",
                        payload
                    );
                },

                save_provider_data: function(payload) {
                    var promise;
                    if (payload.provider) {
                        promise = callProviderSetter(
                            "set_autossl_provider",
                            payload
                        );
                    } else {
                        promise = _call_apiv1({
                            func: "disable_autossl",
                        }).then(function() {
                            savedProviderModuleName = null;
                            $interval.cancel(nextTimeInterval);
                            nextAutosslCheckTime = null;
                        });
                    }

                    return promise;
                },

                metadata: PAGE.metadata,

                save_metadata: function() {
                    return _call_apiv1({
                        func: "set_autossl_metadata",
                        data: {
                            metadata_json: JSON.stringify(PAGE.metadata),
                        },
                    });
                },
            };
        }

        manageServiceFactory.$inject = ["$q", "$interval", "PAGE"];
        return app.factory("manageService", manageServiceFactory);
    }
);
