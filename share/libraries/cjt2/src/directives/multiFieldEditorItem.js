/*
# mail/spam/directives/multiFieldEditorItem.js           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/core",
        "cjt/directives/multiFieldEditor",
        "cjt/directives/validationContainerDirective"
    ],
    function(angular, _, LOCALE, CJT) {

        "use strict";

        var app = angular.module("cjt2.directives.multiFieldEditorItem", []);

        app.directive("multiFieldEditorItem", ["$timeout", function($timeout) {

            function _link(scope, element, attr, controllers) {

                scope.canRemove = _.isUndefined(scope.canRemove) || !(scope.canRemove.toString() === "0" || scope.canRemove.toString() === "false" );

                var MFE = controllers.pop();

                if (scope.index === MFE.getAddingRow() ) {
                    $timeout(function() {
                        MFE.itemBeingAdded = -1;
                        if (element.find("select").length) {
                            if (element.find("select").chosen) {
                                element.find("select").chosen()
                                    .trigger("chosen:activate")
                                    .trigger("chosen:open");
                            }
                        } else {
                            element.find("input").focus();
                        }
                    }, 10);
                }

                scope.requiredFieldMessage = function() {
                    return LOCALE.maketext("This field is required.");
                };

                scope.numericValueMessage = function() {
                    return LOCALE.maketext("This value must be numeric.");
                };

                scope.remove = function() {
                    MFE.removeRow(scope.index);
                };
            }

            var RELATIVE_PATH = "libraries/cjt2/directives/";
            var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;

            var TEMPLATE = TEMPLATES_PATH + "multiFieldEditorItem.phtml";

            return {
                templateUrl: TEMPLATE,
                restrict: "EA",
                require: ["^^multiFieldEditor"],
                transclude: true,
                scope: {
                    "index": "=",
                    "label": "@",
                    "labelFor": "@",
                    "canRemove": "=",
                    "parentID": "@id"
                },
                link: _link
            };
        }]);
    }
);
