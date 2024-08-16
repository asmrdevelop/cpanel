/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/contactService.js
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* jshint -W089 */
/* jshint -W018 */

define(
    [

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        "cjt/services/APICatcher",
    ],
    function(angular, API, APIREQUEST) {
        "use strict";

        // Fetch the current application
        var app = angular.module("customize.services.contactService", [
            "cjt2.services.apicatcher",
            "cjt2.services.api",
        ]);

        app.factory("contactService", ["APICatcher", function(APICatcher) {

            // return the factory interface
            return {

                /**
                 * Update the contact data for the company.
                 *
                 * @param {ContactInfo} contactInfo
                 * @returns
                 */
                setPublicContact: function(contactInfo) {
                    var apicall = new APIREQUEST.Class().initialize(
                        "", "set_public_contact", contactInfo
                    );

                    return APICatcher.promise(apicall);
                },
            };
        },
        ]);
    });
