/*
# cjt/decorators/paginationDecorator.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, LOCALE) {

        // Set up the module in the cjt2 space
        var module = angular.module("cjt2.decorators.paginationDecorator", ["ui.bootstrap.pagination"]);

        module.config(["$provide", function($provide) {

            // Extend the ngModelDirective to interpolate its name attribute
            $provide.decorator("uibPaginationDirective", ["$delegate", function($delegate) {
                var RELATIVE_PATH = "libraries/cjt2/directives/pagination.phtml";
                var uiPaginationDirective = $delegate[0];

                /**
                 * Update the ids in the page collection
                 *
                 * @method updateIds
                 * @param  {Array} pages
                 * @param  {String} id    Id of the directive, used as a prefix
                 */
                var updateIds = function(pages, id) {
                    if (!pages) {
                        return;
                    }

                    pages.forEach(function(page) {
                        page.id = id + "_" + page.text;
                    });
                };

                var updateAriaLabel = function(pages) {
                    if (!pages) {
                        return;
                    }

                    pages.forEach(function(page) {
                        page.ariaLabel = LOCALE.maketext("Go to page “[_1]”.", page.text);
                    });
                };

                uiPaginationDirective.templateUrl = CJT.buildFullPath(RELATIVE_PATH);

                // Extend the page model with the id field.
                var linkFn = uiPaginationDirective.link;

                uiPaginationDirective.compile = function() {
                    return function(scope, element, attrs, ctrls) {
                        var paginationCtrl = ctrls[0];

                        linkFn.apply(this, arguments);

                        scope.parentId = attrs.id;
                        scope.ariaLabels = {
                            title: LOCALE.maketext("Pagination"),
                            firstPage: LOCALE.maketext("Go to first page."),
                            previousPage: LOCALE.maketext("Go to previous page."),
                            nextPage: LOCALE.maketext("Go to next page."),
                            lastPage: LOCALE.maketext("Go to last page."),
                        };

                        var render = paginationCtrl.render;
                        paginationCtrl.render = function() {
                            render.apply(paginationCtrl);
                            updateIds(scope.pages, scope.parentId);
                            updateAriaLabel(scope.pages);
                        };

                    };
                };

                return $delegate;
            }]);
        }]);
    }
);
