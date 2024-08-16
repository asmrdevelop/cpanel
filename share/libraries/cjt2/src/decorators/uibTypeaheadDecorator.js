/*
 * cjt/decorators/uibTypeaheadDecorator.js            Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define(
    [
        "angular",
        "uiBootstrap",
    ],
    function(angular) {
        "use strict";

        angular
            .module("cjt2.decorators.uibTypeaheadDecorator", ["ui.bootstrap.typeahead"])
            .config(["$provide", function($provide) {

                $provide.decorator("uibTypeaheadDirective", ["$delegate", function($delegate) {
                    var directive = $delegate[0];
                    var originalLinkFn = directive.link;
                    directive.compile = function() {
                        return function(scope, elem, attrs) {
                            originalLinkFn.apply(directive, arguments);
                            attrs.$set("role", "combobox");
                        };
                    };
                    return $delegate;
                }]);

            }]);
    }
);
