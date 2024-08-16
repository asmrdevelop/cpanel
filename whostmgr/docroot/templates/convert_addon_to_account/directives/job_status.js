/*
# convert_addon_to_account/directives/job_status.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
    ],
    function(angular, LOCALE, CJT) {

        var app = angular.module("App");
        app.directive("jobStatus",
            [
                function() {
                    var TEMPLATE_PATH = "directives/job_status.phtml";
                    var RELATIVE_PATH = "templates/convert_addon_to_account/" + TEMPLATE_PATH;
                    var IN_PROGRESS_TEXT = LOCALE.maketext("In Progress");
                    var DONE_TEXT = LOCALE.maketext("Done");
                    var FAILED_TEXT = LOCALE.maketext("Failed");
                    var DEFAULT_TEXT = "";

                    function update_status(status, scope) {
                        scope.success = false;
                        scope.error = false;
                        scope.pending = false;

                        if (status === "INPROGRESS") {
                            scope.label = IN_PROGRESS_TEXT;
                            scope.pending = true;
                        } else if (status === "DONE") {
                            scope.label = DONE_TEXT;
                            scope.success = true;
                        } else if (status === "FAILED") {
                            scope.label = FAILED_TEXT;
                            scope.error = true;
                        } else {
                            scope.label = DEFAULT_TEXT;
                        }
                    }

                    return {
                        replace: true,
                        require: "ngModel",
                        restrict: "E",
                        scope: {
                            ngModel: "=",
                        },
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        link: function(scope, element, attrs) {
                            update_status(scope.ngModel, scope);

                            scope.$watch("ngModel", function(newValue, oldValue) {
                                if (newValue && newValue !== oldValue) {
                                    update_status(newValue, scope);
                                }
                            });
                        }
                    };
                }
            ]);
    }
);
