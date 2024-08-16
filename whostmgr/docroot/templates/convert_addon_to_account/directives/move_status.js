/*
# directives/move_status.js                       Copyright(c) 2020 cPanel, L.L.C.
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
        app.directive("itemMoveStatus",
            [
                function() {
                    var TEMPLATE_PATH = "directives/move_status.phtml";
                    var RELATIVE_PATH = "templates/convert_addon_to_account/" + TEMPLATE_PATH;
                    var MOVE_TEXT = LOCALE.maketext("Selected");
                    var DO_NOT_MOVE_TEXT = LOCALE.maketext("Not Selected");

                    return {
                        replace: true,
                        require: "ngModel",
                        restrict: "E",
                        scope: {
                            ngModel: "=",
                        },
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        link: function(scope, element, attrs) {
                            scope.moveLabel = MOVE_TEXT;
                            scope.noMoveLabel = DO_NOT_MOVE_TEXT;
                        }
                    };
                }
            ]);
    }
);
