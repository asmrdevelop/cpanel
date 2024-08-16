/*
 * cjt/decorators/angularChosenDecorator.js           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define(
    [
        "angular",
        "jquery-chosen",
        "angular-chosen",
    ],
    function(angular) {
        "use strict";

        angular
            .module("cjt2.decorators.angularChosenDecorator", ["localytics.directives"])
            .config(["$provide", function($provide) {

                $provide.decorator("chosenDirective", ["$delegate", function($delegate) {
                    var directive = $delegate[0];
                    var originalLinkFn = directive.link;
                    directive.compile = function() {
                        return function(scope, selectElem) {
                            originalLinkFn.apply(directive, arguments);

                            selectElem.on("chosen:ready", function() {
                                selectElem = selectElem.get(0);
                                var chosenElem = selectElem.nextElementSibling;

                                if (!chosenElem || !chosenElem.classList.contains("chosen-container")) {
                                    throw new Error("Developer Error: Chosen has not initialized properly. The .chosen-container element is not next to the select element");
                                }

                                var inputElem = chosenElem.querySelector(".chosen-search input");
                                var labelElem = selectElem.id && document.querySelector("label[for=\"" + selectElem.id + "\"]");

                                if (inputElem && labelElem && labelElem.id) {
                                    inputElem.setAttribute("aria-labelledby", labelElem.id);
                                }
                            });
                        };
                    };
                    return $delegate;
                }]);

            }]);
    }
);
