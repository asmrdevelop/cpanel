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
    [
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
