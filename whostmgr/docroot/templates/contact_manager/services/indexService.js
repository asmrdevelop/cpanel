/*
# templates/contact_manager/services/indexService.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */


define(
    [

        // Libraries
        "angular",
        "cjt/io/whm-v1-request",
        "cjt/services/APICatcher",
    ],
    function(angular, APIREQUEST) {

        var app = angular.module("whm.contactManager.indexService", ["cjt2.services.apicatcher"]);

        var NO_MODULE = "";

        function indexServiceFactory(PAGE, api) {
            var indexService = {};

            /**
             * Create a User Session to transfer to cPanel
             *
             * @method createUserSession
             *
             * @return {Promise.<string,Error>} returns the string url to redirect to
             *
             */

            indexService.createUserSession = function() {

                var apicall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "create_user_session",
                    {
                        "user": PAGE.REMOTE_USER,
                        "service": "cpaneld",
                        "app": "ContactInfo_Change"
                    }
                );

                return api.promise(apicall).then(function(result) {
                    return result.data.url;
                });
            };

            return indexService;
        }

        indexServiceFactory.$inject = ["PAGE", "APICatcher"];
        return app.factory("indexService", indexServiceFactory);
    });
