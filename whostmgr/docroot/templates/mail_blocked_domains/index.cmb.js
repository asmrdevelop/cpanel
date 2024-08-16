/*
# mail_blocked_domains/services/parser.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/services/parser',[
        "punycode",
        "cjt/util/locale",
        "cjt/validator/domain-validators",
        "cjt/validator/validator-utils",
    ],
    function mailBlockedDomainsParser(PUNYCODE, LOCALE, domainValidators, valUtils) {
        "use strict";

        var _validateDomain = domainValidators.methods.wildcardFqdnAllowTld;

        function _discardEmpty(a) {
            return !!a.length;
        }

        /**
        * @function parseDomainsFromText
        * @param txt String The text input to parse.
        * @returns Array The array of domains parsed from the string.
        *
        * On failure, this throws an array:
        *
        *   [
        *       [ domain1, failureReason ],
        *       [ domain2, failureReason ],
        *       ...
        *   ]
        */

        function parseDomainsFromText(txt) {
            var domains = txt.
                trim().
                split(/\s*\n\s*/).
                filter(_discardEmpty)
            ;

            var failures = [];

            var appear = {};

            domains.forEach( function(d, di) {
                var result = _validateDomain(d);

                if (result.isValid) {
                    var uvalue = PUNYCODE.toUnicode(d);

                    if (!appear[uvalue]) {
                        appear[uvalue] = 1;
                    } else {
                        if (appear[uvalue] === 1) {
                            var vresult = valUtils.initializeValidationResult();
                            vresult.addError( "duplicate", LOCALE.maketext("You may not enter any domain more than once.") );
                            failures.push( [uvalue, vresult] );
                        }

                        appear[uvalue]++;
                    }

                    domains[di] = uvalue;
                } else {
                    failures.push( [d, result] );
                }
            } );

            if (failures.length) {
                throw failures;
            }

            return domains;
        }

        return {
            parseDomainsFromText: parseDomainsFromText,
        };
    }
);

/*
# templates/mail_blocked_domains/services/manageService.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */
/* jshint -W100 */
/* jshint -W089 */

define(
    'app/services/manageService',[
        "lodash",
        "angular",
        "punycode",
        "cjt/util/locale",
        "cjt/io/batch-request",
        "cjt/io/whm-v1-request",
        "cjt/services/APICatcher",
        "cjt/services/alertService",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function mailBlockedDomainsService(_, angular, PUNYCODE, LOCALE, BATCH, APIREQUEST) {
        "use strict";

        var NO_MODULE = "";

        // ----------------------------------------------------------------------

        var app = angular.module("whm.mailBlockedDomains.Service", ["cjt2.services.apicatcher", "cjt2.services.api"]);

        function manageServiceFactory(api, alertService) {
            var savedDomains;

            function setSavedDomains(domains) {
                savedDomains = domains.map( PUNYCODE.toUnicode ).sort();
            }

            return {
                setSavedDomains: setSavedDomains,

                getSavedDomains: function getSavedDomains() {
                    return savedDomains.slice();
                },

                saveBlockedDomains: function saveBlockedDomains(domains) {
                    domains = domains.map( PUNYCODE.toASCII );
                    var oldDomains = savedDomains.map( PUNYCODE.toASCII );

                    var apicalls = [];

                    // It’s inefficient to do each addition and removal
                    // in its own transaction, but hopefully there won’t
                    // be much need for optimizing it.

                    var adds = _.difference(domains, oldDomains);
                    if (adds.length) {
                        apicalls.push( new APIREQUEST.Class().initialize( NO_MODULE, "block_incoming_email_from_domain", { domain: adds } ) );
                    }

                    var removes = _.difference(oldDomains, domains);
                    if (removes.length) {
                        apicalls.push( new APIREQUEST.Class().initialize( NO_MODULE, "unblock_incoming_email_from_domain", { domain: removes } ) );
                    }

                    // Last batch call is a re-fetch of the data.
                    apicalls.push( new APIREQUEST.Class().initialize(NO_MODULE, "list_blocked_incoming_email_domains") );

                    var batch = new BATCH.Class( apicalls );

                    alertService.add( {
                        type: "info",
                        message: LOCALE.maketext("Submitting updates …"),
                        replace: true,
                    } );

                    return api.promise(batch).then( function(result) {
                        var newDomains = result.data[ result.data.length - 1 ].data;
                        newDomains = newDomains.map( function(o) {
                            return PUNYCODE.toUnicode(o.domain);
                        } );

                        setSavedDomains(newDomains);

                        alertService.success(LOCALE.maketext("Success!"));
                    } );
                },
            };
        }

        manageServiceFactory.$inject = ["APICatcher", "alertService"];
        return app.factory("manageService", manageServiceFactory);
    }
);

define(
    'app/validators/domainList',[
        "lodash",
        "angular",
        "cjt/validator/validator-utils",
        "app/services/parser",
        "cjt/validator/validateDirectiveFactory",
    ],
    function domainListValidator(_, angular, validationUtils, PARSER) {
        "use strict";

        var methods = {
            domainList: function domainList(input) {
                var result = validationUtils.initializeValidationResult();

                try {
                    PARSER.parseDomainsFromText(input);
                } catch (e) {
                    var errorHTMLs = e.map( function(o) {
                        return ( "<span class='code'>" + _.escape(o[0]) + "</span>: " + _.escape(o[1]) );
                    } );

                    var errorHTML;

                    if (errorHTMLs.length === 1) {
                        errorHTML = errorHTMLs[0];
                    } else {
                        errorHTML = "<ul><li>";
                        errorHTML += errorHTMLs.join("</li><li>");
                        errorHTML += "</li></ul>";
                    }

                    result.addError("domainList", errorHTML);
                }

                return result;
            },
        };

        var validatorModule = angular.module("cjt2.validate");

        validatorModule.run(["validatorFactory", function(validatorFactory) {
            validatorFactory.generate(methods);
        } ] );

        return {
            methods: methods,
            name: "domain-list",
            description: "Validate a list of domains, allowing wildcard.",
            version: 1.0,
        };
    }
);

/*
# whostmgr/docroot/templates/mail_blocked_tlds/index.js
                                                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */

define(
    'app/index',[
        "lodash",
        "angular",
        "punycode",
        "cjt/util/locale",
        "app/services/parser",
        "cjt/core",
        "cjt/util/parse",
        "cjt/modules",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
    ],
    function mailBlockedDomainsDefine(_, angular, PUNYCODE, LOCALE, PARSER) {
        "use strict";

        var PAGE = window.PAGE;

        return function inDefine() {
            angular.module("whm.mailBlockedDomains", [
                "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
                "ui.bootstrap",
                "cjt2.whm",
                "cjt2.services.alert",
                "whm.mailBlockedDomains.Service",
            ] );

            return require(
                [
                    "cjt/bootstrap",
                    "uiBootstrap",
                    "app/services/manageService",
                    "app/validators/domainList",
                ],
                function toRequire(BOOTSTRAP) {
                    var app = angular.module("whm.mailBlockedDomains");

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "manageService",
                        function($rootScope, $scope, manageService) {
                            manageService.setSavedDomains(PAGE.initial_blocked_domains);

                            var state = {
                                viewPunycodeYN: PAGE.initial_view_punycode,
                            };

                            function _parseDomainsFromView() {
                                return PARSER.parseDomainsFromText(state.domainsText);
                            }

                            function _pushDomainsToView(domains) {
                                state.domainsText = domains.join("\n");
                            }

                            function _syncDomainsText() {
                                var domains = manageService.getSavedDomains();

                                if (state.viewPunycodeYN) {
                                    domains = domains.map( PUNYCODE.toASCII );
                                }

                                _pushDomainsToView(domains);
                            }

                            _syncDomainsText();

                            _.assign(
                                $scope,
                                {
                                    updateViewPunycode: function updateViewPunycode() {
                                        var domains = _parseDomainsFromView();
                                        var xform = PUNYCODE[ state.viewPunycodeYN ? "toASCII" : "toUnicode" ];

                                        _pushDomainsToView(domains.map(xform));
                                    },

                                    domainsAreChanged: function domainsAreChanged() {
                                        var domains = _parseDomainsFromView();
                                        var saved = manageService.getSavedDomains();

                                        return !!_.xor(domains, saved).length;
                                    },

                                    submit: function submit() {
                                        var domains = PARSER.parseDomainsFromText(state.domainsText);

                                        $scope.inProgress = true;

                                        return manageService.saveBlockedDomains(domains).then( _syncDomainsText ).finally( function() {
                                            $scope.inProgress = false;
                                        } );
                                    },

                                    state: state,
                                }
                            );
                        },
                    ] );

                    BOOTSTRAP(document, "whm.mailBlockedDomains");
                }
            );
        };
    }
);

