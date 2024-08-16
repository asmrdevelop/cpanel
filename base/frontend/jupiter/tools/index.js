/*
# cpanel - base/frontend/jupiter/tools/index.js     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "ngSanitize",
        "cjt/modules",
        "app/views/sslStatus",
        "uiBootstrap",
        "angular-chosen",
        "cjt/services/alertService",
    ],
    function(angular, CJT) {

        "use strict";

        return function() {

            // First create the application
            angular.module("App", ["ngSanitize", "ui.bootstrap", "cjt2.cpanel", "angular-growl", "localytics.directives", "cpanel.tools.views.sslStatus", "cpanel.tools.service.nginxService", "cpanel.tools.service.wordPressService"]);

            // Then load the application dependencies
            var app = require(
                [

                    // Application Modules
                    "cjt/bootstrap",
                    "cjt/util/locale",
                    "app/views/applicationListController",
                    "app/views/statisticsController",
                    "app/views/themesController",
                    "app/views/nginxController",
                    "app/views/accountsController",
                    "app/services/wordPressService",
                ], function(BOOTSTRAP, LOCALE) {
                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.config(["$httpProvider", function($httpProvider) {
                        $httpProvider.useApplyAsync(true);
                    }]);
                    app.run(["wordPressService", "alertService", "PAGE", "$rootScope", function(wordPressService, alertService, PAGE, $rootScope) {

                        // This event comes from the welcome modal web component.
                        document.addEventListener("wordPressInstallPoll", function() {
                            $rootScope.$apply(function() {
                                alertService.add({
                                    type: "info",
                                    message: LOCALE.maketext("Your WordPress site is being created."),
                                    closeable: true,
                                    replace: true,
                                });
                                pollForWordPressInstall();
                            });
                        });

                        function pollForWordPressInstall() {

                            // Let the users know the install is continuing
                            var pollingIntervalId;
                            pollingIntervalId = setInterval(function() {
                                wordPressService.startPolling().then(function(uapiResponse) {
                                    if (uapiResponse.data.install_status === "success") {
                                        clearInterval(pollingIntervalId);
                                        pollingIntervalId = null;
                                        alertService.add({
                                            type: "success",
                                            message: LOCALE.maketext("Your website is ready. Start adding content and personalizing “[output,strong,_1]” using [output,url,_2,WP Toolkit,title,WP Toolkit interface].", PAGE.domain, PAGE.wpToolkitUrl),
                                            closeable: true,
                                            replace: true,
                                            autoClose: 10000,
                                        });
                                    }
                                })
                                    .catch(function(errors) {
                                        clearInterval(pollingIntervalId);
                                        pollingIntervalId = null;
                                        alertService.add({
                                            type: "danger",
                                            message: LOCALE.maketext("Something went wrong. Your website failed to create. Try creating your website manually using [output,url,_1,WP Toolkit,title,WP Toolkit interface].", PAGE.wpToolkitUrl),
                                            closeable: true,
                                            replace: true,
                                        });
                                    });
                            }, 5000);
                        }

                        // Account UUID copy event handler.
                        var copyUuidLinkEl = document.getElementById("linkCopyUuid");
                        var copyUuidIconEl = document.getElementById("iconCopyUuid");
                        copyUuidLinkEl.addEventListener("click", copyUuidHandler);
                        copyUuidIconEl.addEventListener("click", copyUuidHandler);

                        function copyUuidHandler() {

                            var uuidTxtEl = document.getElementById("txtAcctUuid");
                            var copyMsgEl = document.getElementById("copyMsgContainer");
                            const copyText = uuidTxtEl.textContent;

                            navigator.clipboard
                                .writeText(copyText)
                                .then(() => {
                                    copyMsgEl.classList.add("show-copy-success");
                                    window.setTimeout(function() {
                                        copyMsgEl.classList.remove("show-copy-success");
                                    }, 3000);
                                },
                                (err) => {
                                    console.error(err);
                                });


                        }
                    }]);
                    BOOTSTRAP("#content", "App");
                });
            return app;
        };
    }
);
