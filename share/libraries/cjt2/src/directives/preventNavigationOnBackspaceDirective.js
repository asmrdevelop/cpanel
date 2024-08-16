/*
# cjt/directives/preventNavigationOnBackspaceDirective.js
#                                                   Copyright(c) 2020 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        var module = angular.module("cjt2.directives.preventNavigationOnBackspace", []);

        /**
         * Directive that prevents navigation when the backspace key is hit.
         *
         * @example
         * <div prevent-navigation-on-backspace />
         */
        module.directive("preventNavigationOnBackspace", [
            "$document",
            function($document) {
                return {
                    restrict: "A",
                    link: function(scope, element, attrs, ngModel) {
                        $document.unbind("keydown").bind("keydown", function(event) {
                            var doPrevent = false;
                            if (event.keyCode === 8) {
                                var target = event.srcElement || event.target;
                                if ((target.tagName.toUpperCase() === "INPUT" &&
                                     (
                                         target.type.toUpperCase() === "TEXT" ||
                                         target.type.toUpperCase() === "PASSWORD" ||
                                         target.type.toUpperCase() === "FILE" ||
                                         target.type.toUpperCase() === "SEARCH" ||
                                         target.type.toUpperCase() === "EMAIL" ||
                                         target.type.toUpperCase() === "NUMBER" ||
                                         target.type.toUpperCase() === "DATE" )
                                ) ||
                                     target.tagName.toUpperCase() === "TEXTAREA" ||
                                     target.isContentEditable) {
                                    doPrevent = target.readOnly || target.disabled;
                                } else {
                                    doPrevent = true;
                                }
                            }

                            if (doPrevent) {
                                event.preventDefault();
                            }
                        });
                    }
                };
            }
        ]);
    }
);
