/*
# autossl/directives/starRating.js                                            Copyright(c) 2020 cPanel, L.L.C.
#                                                                                      All rights reserved.
# copyright@cpanel.net                                                                    http://cpanel.net
# This code is subject to the cPanel license.                            Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/starRating',[
        "angular",
        "cjt/core"
    ],
    function(angular, CJT) {

        "use strict";

        var module = angular.module("whostmgr.autossl.starRating", []);

        var TEMPLATE_PATH = "directives/starRating.phtml";

        module.directive("starRating", function() {

            return {
                templateUrl: TEMPLATE_PATH,
                restrict: "EA",
                replace: true,
                transclude: true,
                scope: {
                    max: "=",
                    rating: "="
                },
                controller: ["$scope", function($scope) {

                    function _buildStars() {
                        $scope.stars = [];
                        while ($scope.stars.length < $scope.max) {
                            $scope.stars.push($scope.rating > $scope.stars.length ? 1 : 0);
                        }
                    }

                    $scope.$watch("max", _buildStars);
                    $scope.$watch("rating", _buildStars);

                    _buildStars();
                }]
            };
        });
    }
);

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
    'app/services/manageService',[
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

/*
# templates/autossl/views/select_provider_controller.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/select_provider_controller',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/formWaiting",
    ],
    function(_, angular, LOCALE, CJT_PARSE) {
        "use strict";

        // Retrieve the current application
        // Or mock it for testing.
        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", []);
        }

        // Setup the controller
        var controller = app.controller(
            "select_provider_controller", [
                "$scope",
                "manageService",
                "growl",
                function($scope, manageService, growl) {
                    function _growlError(result) {
                        result.data && result.data.forEach(function(batchResponse) {
                            var parsedResponse = batchResponse.parsedResponse;
                            parsedResponse.messages.forEach(function(message) {
                                growl[message.level](_.escape(message.content));
                            });
                        });
                    }

                    function _convertMS(ms) {
                        var d, h, m, s, y;
                        s = Math.floor(ms / 1000);
                        m = Math.floor(s / 60);
                        s = s % 60;
                        h = Math.floor(m / 60);
                        m = m % 60;
                        d = Math.floor(h / 24);
                        h = h % 24;
                        y = Math.floor(d / 365);
                        d = d % 365;

                        return { y: y, d: d, h: h, m: m, s: s };
                    }

                    function _generateTimeString(timeObject) {
                        var timeString = [];
                        if (timeObject.y) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,year,years]", timeObject.y);
                        }
                        if (timeObject.d) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,day,days]", timeObject.d);
                        }
                        if (timeObject.h) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,hour,hours]", timeObject.h);
                        }
                        if (timeObject.m) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,minute,minutes]", timeObject.m);
                        }
                        if (timeObject.s) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,second,seconds]", timeObject.s);
                        }
                        return timeString.join("/");
                    }

                    function _getTimeString(value, unsetValue) {
                        if (!value) {
                            return unsetValue;
                        }

                        var fullTimeObject = _convertMS(value * 1000);

                        return _generateTimeString(fullTimeObject);
                    }

                    function _getFormattedSpec(specValue, specKey) {
                        specValue = _.isNil(specValue) ? "" : specValue;
                        var formattedSpec = specValue.toString();
                        switch (specKey) {
                            case "list_and_quoted":
                                formattedSpec = LOCALE.list_and_quoted(specValue);
                                break;
                            case "numf":
                                formattedSpec = LOCALE.numf(specValue);
                                break;
                            case "time_string":
                                formattedSpec = _getTimeString(specValue, LOCALE.maketext("[output,em,Unspecified]"));
                                break;
                            case "rate_limit":
                                formattedSpec = specValue.toString() === "0" ? LOCALE.maketext("unlimited") : specValue;
                        }
                        return formattedSpec.toString() === "" ? LOCALE.maketext("[output,em,Unspecified]") : formattedSpec.toString();
                    }

                    function _gather_save_data() { // eslint-disable-line camelcase
                        var providerModule = $scope.current_provider_module_name;

                        var providerObj = $scope.get_current_provider();

                        var tosAccepted = providerObj ? providerObj.x_terms_of_service_accepted : "";

                        var toSave = {
                            provider: providerModule
                        };
                        if (providerObj && providerObj.x_terms_of_service) {
                            toSave.x_terms_of_service_accepted = tosAccepted;
                        }

                        return toSave;
                    }

                    angular.extend($scope, {
                        providers: manageService.get_providers(),
                        showScoreDetails: false,
                        provider_by_module_name: {},
                        provider_submit_type: {},
                        current_provider_module_name: "",
                        getFormattedSpec: _getFormattedSpec,

                        toggleShowScoreDetails: function() {
                            $scope.showScoreDetails = !$scope.showScoreDetails;
                        },

                        get_current_provider: function() {
                            if ($scope.current_provider_module_name) {
                                return $scope.provider_by_module_name[$scope.current_provider_module_name];
                            }

                            return null;
                        },

                        getTableColumns: manageService.getTableColumns.bind(manageService),
                        getDetailsExplaination: function() {
                            var tableColumns = manageService.getTableColumns();
                            tableColumns = tableColumns.filter(function(column) {
                                return column.isScorePart;
                            }).map(function(column) {
                                return column.getLabel();
                            });
                            return LOCALE.maketext("This interface uses the following parameters to calculate the usability score: [list_and,_1].", tableColumns);
                        },

                        get_saved_provider_module_name: manageService.get_saved_provider_module_name,

                        do_submit: function() {
                            var toSave = _gather_save_data();

                            var providerObj = $scope.get_current_provider();

                            var toReset = ($scope.provider_submit_type[$scope.current_provider_module_name] === "reset");

                            var method;
                            if (toReset) {
                                method = "reset_provider_data";
                            } else {
                                method = "save_provider_data";
                            }

                            return manageService[method](toSave).then(
                                function() {
                                    var newProviderObj = $scope.provider_by_module_name[toSave.provider];

                                    if (toReset) {
                                        growl.success(LOCALE.maketext("You have created a new registration for this system with “[_1]” and configured [asis,AutoSSL] to use that provider.", _.escape(newProviderObj.display_name)));
                                    } else if (newProviderObj) {
                                        growl.success(LOCALE.maketext("You have configured [asis,AutoSSL] to use the “[_1]” provider.", _.escape(newProviderObj.display_name)));
                                    } else {
                                        growl.success(LOCALE.maketext("You have disabled [asis,AutoSSL]. Any users with [asis,SSL] certificates from [asis,AutoSSL] will continue to use them, but the system will not automatically renew these certificates."));
                                    }

                                    if (providerObj) {
                                        providerObj.saved_x_terms_of_service_accepted = providerObj.x_terms_of_service_accepted;
                                    }

                                    $scope.provider_submit_type[$scope.current_provider_module_name] = "";
                                },
                                _growlError
                            ).finally(function() {
                                $scope.$emit("provider-module-updated");
                            });
                        },
                    });

                    $scope.providers.forEach(function(p) {
                        if (CJT_PARSE.parsePerlBoolean(p.enabled)) {
                            $scope.current_provider_module_name = p.module_name;
                        }

                        $scope.provider_by_module_name[p.module_name] = p;
                    });

                    manageService.restore_and_save_scope(
                        "select_provider",
                        $scope, [
                            "current_provider_module_name",
                        ]
                    );
                }
            ]
        );

        return controller;
    }
);

/*
# templates/autossl/views/view_logs_controller.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100, -W089 */
/* eslint-disable camelcase */

define(
    'app/views/view_logs_controller',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/formWaiting",
    ],
    function(_, angular, LOCALE, CJT, CJT_PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "view_logs_controller", [
                "$scope",
                "$timeout",
                "manageService",
                "growl",
                "PAGE",
                function($scope, $timeout, manageService, growl, PAGE) {
                    function growlError(result) {
                        return growl.error( _.escape(result.error) );
                    }

                    manageService.groom_logs_catalog(PAGE.logs_catalog);

                    var providerDisplayName = {};
                    PAGE.provider_info.forEach( function(p) {
                        providerDisplayName[p.module_name] = p.display_name;
                    } );

                    // do this while CJT2’s CLDR is broken.
                    var cjt1_LOCALE = window.LOCALE;

                    var log_level_fontawesome = {

                        // warn: "fa-exclamation-triangle",
                        warn: "exclamation-triangle",
                        error: "minus-square",
                        out: "info-circle",
                        success: "check",
                    };

                    var log_level_localized = {
                        success: LOCALE.maketext("SUCCESS"),
                        warn: LOCALE.maketext("WARN"),
                        error: LOCALE.maketext("ERROR"),
                    };

                    var unparsable_template = LOCALE.maketext("Unparsable log data ([_1]):", "__ERR__");

                    angular.extend( $scope, {
                        log_level_localized: log_level_localized,

                        log_level_fontawesome: log_level_fontawesome,

                        logs_catalog: manageService.get_logs_catalog(),
                        chosen_log: manageService.get_logs_catalog()[0],

                        datetime: cjt1_LOCALE.local_datetime.bind(cjt1_LOCALE),

                        get_provider_display_name: manageService.get_provider_display_name,

                        fetch_logs_catalog: function() {
                            return manageService.refresh_logs_catalog().then(
                                function(catalog) {
                                    $scope.logs_catalog = catalog;
                                    var old_chosen_log = $scope.chosen_log;
                                    $scope.chosen_log = null;

                                    if (old_chosen_log) {
                                        for (var c = 0; c < catalog.length; c++) {
                                            if (old_chosen_log.provider !== catalog[c].provider) {
                                                continue;
                                            }
                                            if (old_chosen_log.start_time !== catalog[c].start_time) {
                                                continue;
                                            }

                                            $scope.chosen_log = catalog[c];
                                            break;
                                        }
                                    }

                                    if (!$scope.chosen_log) {
                                        $scope.chosen_log = catalog[0];
                                    }

                                    return;
                                },
                                growlError
                            );
                        },

                        // This optimization is ugly, but AngularJS was too slow
                        // when rendering thousands of DOM nodes.
                        _log_data_to_html: function(logs) {
                            var rows = [];

                            var log_level_html = {};
                            for (var key in log_level_localized) {
                                log_level_html[key] = _.escape(log_level_localized[key]);
                            }

                            var indentTimestamp;

                            for (var l = 0; l < logs.length; l++) {
                                var entry = logs[l];
                                var div_class = "logentry-" + entry.type;
                                if (("" + entry.indent) !== "0") {
                                    div_class += " indent" + entry.indent;
                                }
                                var r_html = "<div class='" + div_class + "'>";
                                if (log_level_fontawesome[entry.type]) {
                                    r_html += " <span class='fas fa-" + log_level_fontawesome[entry.type] + "'></span>";
                                }

                                var curIndentTimestamp = [entry.indent, entry.timestamp_epoch].join();

                                if ((curIndentTimestamp !== indentTimestamp) && entry.timestamp_epoch) {
                                    indentTimestamp = curIndentTimestamp;
                                    r_html += " <span>" + LOCALE.local_datetime(entry.timestamp_epoch, "time_format_medium") + "</span>";
                                }


                                if (log_level_localized[entry.type]) {
                                    r_html += " <span>" + log_level_html[entry.type] + "</span>";
                                }

                                if ("contents" in entry) {
                                    r_html += " " + _.escape(entry.contents);
                                } else {
                                    r_html += " <span class='log-unparsed'>??? " + unparsable_template.replace(/__ERR__/, _.escape(entry.parse_error)) + " " + _.escape(entry.raw) + "</span>";
                                }

                                r_html += "</div>";

                                rows.push(r_html);
                            }

                            return rows.join("");
                        },

                        log_submit: function() {
                            var loadData = Object.create($scope.chosen_log);

                            $scope.log_load_in_progress = true;

                            return manageService.get_log(loadData).then(
                                function(resp) {
                                    $scope.current_loaded_log = resp;
                                    $timeout(
                                        function() {
                                            document.getElementById("current_loaded_log_html").innerHTML = $scope._log_data_to_html(resp);
                                        }
                                    );

                                    loadData.start_time_epoch = $scope.chosen_log.start_time_epoch;
                                    $scope.last_load_data = loadData;
                                },
                                growlError
                            ).then( function() {
                                $scope.log_load_in_progress = false;
                            } );
                        },
                    } );

                    manageService.restore_and_save_scope(
                        "view_logs",
                        $scope,
                        [
                            "chosen_log",
                            "last_load_data",
                            "current_loaded_log",
                        ]
                    );
                }
            ]
        );

        return controller;
    }
);

/* global define, PAGE */

define(
    'app/services/AutoSSLConfigureService',[
        "angular",
        "lodash",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it’s ready
    ],
    function(angular, _, API, APIREQUEST) {

        var app = angular.module("App");

        function AutoSSLConfigureServiceFactory($q, PAGE) {
            var AutoSSLConfigureService = {};

            var users = [];
            var usermap = {};
            var NO_MODULE = null;

            function _call_api(module, call, params, filters) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(module, call);

                angular.forEach(params, function(param, key) {
                    apiCall.addArgument(key, param);
                });

                if (filters) {
                    angular.forEach(filters, function(filter) {
                        apiCall.addFilter(filter.key, filter.operator, filter.value);
                    });
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

            }

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

            AutoSSLConfigureService._set_auto_ssl_for_users = function(items, enable) {

                /* enable the feature means disable the override */
                var features = JSON.stringify({
                    autossl: enable ? "1" : "0"
                });

                // This gets added to in the foreach loop. Format is necessary for batching.
                var params = {
                    command: []
                };

                angular.forEach(items, function(item) {
                    item.updating = true;
                    params.command.push(_build_batch_command("add_override_features_for_user", {
                        user: item.user,
                        features: features
                    }));
                });

                return _call_api(NO_MODULE, "batch", params).then(function() {
                    angular.forEach(items, function(item) {
                        item.auto_ssl_enabled = enable ? "enabled" : "disabled";
                    });
                }).finally(function() {
                    angular.forEach(items, function(item) {
                        item.updating = false;
                    });
                });
            };

            AutoSSLConfigureService.enable_auto_ssl_for_users = function(items) {
                return AutoSSLConfigureService._set_auto_ssl_for_users(items, true);
            };

            AutoSSLConfigureService.disable_auto_ssl_for_users = function(items) {
                return AutoSSLConfigureService._set_auto_ssl_for_users(items, false);
            };

            AutoSSLConfigureService.reset_auto_ssl_for_users = function(items) {

                /* enable the feature means disable the override */
                var features = JSON.stringify(["autossl"]);

                // This gets added to in the foreach loop. Format is necessary for batching.
                var params = {
                    command: []
                };

                angular.forEach(items, function(item) {

                    item.updating = true;
                    params.command.push(_build_batch_command("remove_override_features_for_user", {
                        user: item.user,
                        features: features
                    }));
                });

                return _call_api(NO_MODULE, "batch", params).then(function() {
                    angular.forEach(items, function(item) {
                        item.auto_ssl_enabled = "inherit";
                    });
                }).finally(function() {
                    angular.forEach(items, function(item) {
                        item.updating = false;
                    });
                });

            };

            AutoSSLConfigureService.get_user_by_username = function(username) {
                var user_i = usermap[username];
                return users[user_i];
            };

            AutoSSLConfigureService.get_users = function() {
                return users;
            };

            AutoSSLConfigureService.fetch_users = function() {

                function _update(data) {
                    users = [];
                    usermap = {};
                    angular.forEach(data, function(user) {
                        usermap[user.user] = users.length;
                        users.push({
                            "user": user.user,
                            "rowSelected": 0,
                            "updating": true,
                            "auto_ssl_settings": {}
                        });

                        /* set to true (has ssl) if not set to false by fetch_disabled */
                    });
                    return AutoSSLConfigureService.get_users();
                }

                if (PAGE.users) {
                    return _update(PAGE.users);
                } else {
                    PAGE.users = [];
                }

            };

            AutoSSLConfigureService.fetch_users_features_settings = function(users) {

                function _update(data) {
                    angular.forEach(data, function(setting) {
                        var user = AutoSSLConfigureService.get_user_by_username(setting.user);
                        user.feature_list = setting.feature_list;
                        user.auto_ssl_settings = setting;
                        user.auto_ssl_enabled = "inherit";
                        if (setting.cpuser_setting === "0" || setting.cpuser_setting === "1") {
                            user.auto_ssl_enabled = setting.cpuser_setting === "1" ? "enabled" : "disabled";
                        }
                    });
                    return AutoSSLConfigureService.get_users();
                }

                /* The API call will fail if no users are provided. */
                if (!users.length) {
                    return $q.reject();
                }

                return _call_api(NO_MODULE, "get_users_features_settings", {
                    "user": users.map(function(user) {
                        return user.user;
                    }),
                    "feature": "autossl"
                }).then(function(result) {
                    _update(result.data);
                }).finally(function() {
                    angular.forEach(users, function(user) {
                        user.updating = false;
                    });
                });

            };

            AutoSSLConfigureService.start_autossl_for_user = function(username) {
                return _call_api(
                    NO_MODULE,
                    "start_autossl_check_for_one_user", {
                        username: username
                    }
                );
            };

            return AutoSSLConfigureService;
        }

        AutoSSLConfigureServiceFactory.$inject = ["$q", "PAGE"];
        return app.factory("AutoSSLConfigureService", AutoSSLConfigureServiceFactory);
    });

/* global define: false */

define(
    'app/views/ManageUsersController',[
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

/*
# templates/autossl/views/OptionsController.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

define(
    'app/views/OptionsController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/formWaiting",
    ],
    function(_, angular, LOCALE, CJT, CJT_PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var AUTOSSL_NOTIFICATIONS = {
            disable: [ ],
            certFailures: [ "notify_autossl_expiry", "notify_autossl_expiry_coverage", "notify_autossl_renewal_coverage_reduced", "notify_autossl_renewal_coverage" ]
        };

        AUTOSSL_NOTIFICATIONS.failWarnDefer = _.concat( AUTOSSL_NOTIFICATIONS.certFailures, "notify_autossl_renewal_uncovered_domains" );
        AUTOSSL_NOTIFICATIONS.all           = _.concat( AUTOSSL_NOTIFICATIONS.failWarnDefer, "notify_autossl_renewal" );

        // Setup the controller
        return app.controller(
            "OptionsController", [
                "$scope",
                "manageService",
                "growl",
                "PAGE",
                function($scope, manageService, growl, PAGE) {
                    function growlError(result) {
                        return growl.error( _.escape(result.error) );
                    }

                    angular.extend( $scope, {
                        metadata: manageService.metadata,

                        clobber_externally_signed_string: function() {
                            return LOCALE.maketext("This option will allow [asis,AutoSSL] to replace certificates that the [asis,AutoSSL] system did not issue. When you enable this option, [asis,AutoSSL] will install certificates that replace users’ [output,abbr,CA,Certificate Authority]-issued certificates if they are invalid or expire within [quant,_1,day,days].", PAGE.constants.MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED);
                        },

                        do_submit: function() {

                            _.each(AUTOSSL_NOTIFICATIONS.all, function(n) {
                                manageService.metadata[n] = 0;
                                manageService.metadata[n + "_user"] = 0;
                            });

                            _.each(AUTOSSL_NOTIFICATIONS[$scope.adminNotifications], function(n) {
                                manageService.metadata[n] = 1;
                            });

                            _.each(AUTOSSL_NOTIFICATIONS[$scope.userNotifications], function(n) {
                                manageService.metadata[n + "_user"] = 1;
                            });

                            return manageService.save_metadata().then(
                                function() {
                                    growl.success( LOCALE.maketext("Success!") );
                                },
                                growlError
                            );
                        }
                    } );

                    if ( manageService.metadata.notify_autossl_renewal ) {
                        $scope.adminNotifications = "all";
                    } else if ( manageService.metadata.notify_autossl_renewal_uncovered_domains ) {
                        $scope.adminNotifications = "failWarnDefer";
                    } else if ( _.find(AUTOSSL_NOTIFICATIONS.certFailures, function(n) {
                        return manageService.metadata[n];
                    }) ) {
                        $scope.adminNotifications = "certFailures";
                    } else {
                        $scope.adminNotifications = "disable";
                    }

                    if ( manageService.metadata.notify_autossl_renewal_user ) {
                        $scope.userNotifications = "all";
                    } else if ( manageService.metadata.notify_autossl_renewal_uncovered_domains_user ) {
                        $scope.userNotifications = "failWarnDefer";
                    } else if ( _.find(AUTOSSL_NOTIFICATIONS.certFailures, function(n) {
                        return manageService.metadata[n + "_user"];
                    }) ) {
                        $scope.userNotifications = "certFailures";
                    } else {
                        $scope.userNotifications = "disable";
                    }

                }
            ]
        );
    }
);

/*
# whostmgr/docroot/templates/autossl/index.js        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */
/* eslint-disable camelcase */

define(
    'app/index',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/util/parse",
        "cjt/modules",
        "uiBootstrap",
        "cjt/directives/actionButtonDirective",
        "app/directives/starRating",
    ],
    function(_, angular, LOCALE, CJT) {
        "use strict";

        CJT.config.html5Mode = false;

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
                "ngRoute",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "whostmgr.autossl.starRating",
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "app/services/manageService",
                    "app/views/select_provider_controller",
                    "app/views/view_logs_controller",
                    "app/services/AutoSSLConfigureService",
                    "app/views/ManageUsersController",
                    "app/views/OptionsController",
                ],
                function(BOOTSTRAP) {

                    var tab_configs = [{
                        path: "/providers/",
                        label: LOCALE.maketext("Providers"),
                        controller: "select_provider_controller",
                        templateUrl: CJT.buildFullPath("autossl/views/select_provider.ptt"),
                    }, {
                        path: "/options/",
                        label: LOCALE.maketext("Options"),
                        controller: "OptionsController",
                        templateUrl: CJT.buildFullPath("autossl/views/options.ptt"),
                    }, {
                        path: "/view-logs/",
                        label: LOCALE.maketext("Logs"),
                        controller: "view_logs_controller",
                        templateUrl: CJT.buildFullPath("autossl/views/view_logs.ptt"),
                    }, {
                        path: "/manage-users/",
                        label: LOCALE.maketext("Manage Users"),
                        controller: "ManageUsersController",
                        templateUrl: CJT.buildFullPath("autossl/views/manage-users.ptt"),
                        resolve: {
                            "ssl_users": ["AutoSSLConfigureService",
                                function(service) {
                                    return service.fetch_users();
                                },
                            ],
                        },
                    }];
                    var default_tab = tab_configs[0].path;

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "$route",
                        "$location",
                        "manageService",
                        "AutoSSLConfigureService",
                        "growl",
                        function($rootScope, $scope, $route, $location, manageService, AutoSSLConfigureService, growl) {
                            $scope.loading = false;
                            $scope.activeTabs = [];

                            // Convenience functions so we can track changing views for loading purposes
                            $rootScope.$on("$routeChangeStart", function(eo, next) {
                                $scope.onLoadTab(next.path);
                                $scope.active_path = next.path;
                                $scope.loading = true;
                            });
                            $rootScope.$on("$routeChangeSuccess", function() {
                                $scope.loading = false;
                            });
                            $rootScope.$on("$routeChangeError", function() {
                                $scope.loading = false;
                                $scope.go("providers");
                            });

                            $scope.current_route_matches = function(key) {
                                return $location.path().match(key);
                            };

                            $scope.onLoadTab = function(loaded_path) {
                                $scope.activeTabs.forEach(function(value, key) {
                                    if (value.path === loaded_path) {
                                        $scope.currentTab = key;
                                    }
                                });
                            };

                            $scope.updated_current_module = function() {
                                $scope.current_provider_module = manageService.get_saved_provider_module_name();
                            };

                            $scope.$on("provider-module-updated", function() {
                                $scope.updated_current_module();
                            });

                            $scope.go = function(path) {
                                $location.path(path);
                            };

                            function init() {
                                $scope.activeTabs = tab_configs;
                                $scope.updated_current_module();
                            }

                            init();

                            // ----------------------------------------------------------------------
                            // Should the following be in its own view?
                            function _growl_error(result) {
                                return growl.error(_.escape(result.error));
                            }

                            angular.extend($scope, {
                                next_check_time_string: function() {
                                    var time = manageService.get_next_autossl_check_time();
                                    if (time) {

                                        // datetime() always kicks out UTC.
                                        // We could use local_datetime(), but
                                        // that would break compatibility with
                                        // Perl’s Locale, which doesn’t have
                                        // local_datetime(). So, instead we
                                        // “trick” datetime() by feeding it
                                        // an offset epoch seconds count.
                                        var compensated_time = time;
                                        compensated_time -= 60 * 1000 * time.getTimezoneOffset();
                                        compensated_time /= 1000;

                                        return LOCALE.maketext("This system’s next regular [asis,AutoSSL] check will occur at [datetime,_1,time_format_short].", Math.round(compensated_time));
                                    }
                                },

                                getSavedProviderAccountID: manageService.getSavedProviderAccountID.bind(manageService),

                                getCurrentProviderDisplayName: function() {
                                    return manageService.get_provider_display_name(manageService.get_saved_provider_module_name());
                                },

                                get_saved_provider_module_name: manageService.get_saved_provider_module_name,

                                start_autossl_for_all_users: function() {
                                    return manageService.start_autossl_for_all_users().then(
                                        function(result) {
                                            growl.success(LOCALE.maketext("[asis,AutoSSL] is now checking all users. The process has [asis,ID] “[_1]”.", result.data.pid));
                                        },
                                        _growl_error
                                    );
                                },
                            });
                        },
                    ]);

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            tab_configs.forEach(function(tab) {
                                $routeProvider.when(tab.path, tab);
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": default_tab,
                            });
                        },
                    ]);

                    BOOTSTRAP();

                });

            return app;
        };
    }
);

