/*
# base/frontend/jupiter/sql/userrights/index.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */


define(
    'app/index',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/uapi-request",
        "cjt/io/uapi",  // preload
        "cjt/modules",
        "cjt/directives/formWaiting",
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",

        // "cjt/decorators/growlAPIReporter",
        "uiBootstrap",
        "cjt/services/APICatcher",
    ],
    function(angular, _, LOCALE, APIREQUEST) {
        "use strict";

        return function() {

            var app = require(
                [

                    // Application Modules
                    "cjt/bootstrap",
                ], function(BOOTSTRAP) {

                    // First create the application
                    var app = angular.module("App", [
                        "cjt2.cpanel",

                        // "cjt2.decorators.growlAPIReporter",
                        "ui.bootstrap",
                    ]);

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "APICatcher",
                        "alertService",
                        function($rootScope, $scope, api, alertService) {
                            angular.extend(
                                $scope,
                                {
                                    save_privs: function savePrivs(ngForm) {

                                        // HACK ..
                                        var theForm = document.forms[ngForm.$name];

                                        var privsStr;
                                        if (theForm.ALL.checked) {
                                            privsStr = "ALL";
                                        } else {
                                            privsStr = "";
                                            var privs = [].slice.call(theForm.privileges);
                                            for (var p = 0; p < privs.length; p++) {
                                                if (privs[p].checked) {
                                                    privsStr += "," + privs[p].value;
                                                }
                                            }

                                            privsStr = privsStr.replace(/^,/, "");
                                        }

                                        var apicall = new APIREQUEST.Class().initialize(
                                            "Mysql",
                                            "set_privileges_on_database",
                                            {
                                                user: CPANEL.PAGE.username,
                                                database: CPANEL.PAGE.dbname,
                                                privileges: privsStr,
                                            }
                                        );

                                        return api.promise(apicall).then( function(resp) {
                                            var els = [].slice.call(theForm.elements);

                                            // So that a reset() will now treat the
                                            // saved values as default.
                                            for (var e = 0; e < els.length; e++) {
                                                if (els[e].type === "checkbox") {
                                                    els[e].defaultChecked = els[e].checked;
                                                }
                                            }

                                            // growl.success( LOCALE.maketext("You saved “[_1]”’s privileges on the database “[_2]”.", _.escape(CPANEL.PAGE.username), _.escape(CPANEL.PAGE.dbname)) );
                                            alertService.add({
                                                type: "success",
                                                message: LOCALE.maketext("You saved “[_1]”’s privileges on the database “[_2]”.", _.escape(CPANEL.PAGE.username), _.escape(CPANEL.PAGE.dbname)),
                                                closeable: true,
                                                replace: false,
                                                autoClose: 10000,
                                                group: "userrights",
                                            });
                                        } );
                                    },
                                }
                            );
                        },
                    ]);

                    BOOTSTRAP("#ng_content", "App");
                });

            return app;
        };
    }
);

