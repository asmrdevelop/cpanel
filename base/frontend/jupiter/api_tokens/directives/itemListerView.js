/*
# api_tokens/directives/itemListerView.js                               Copyright 2022 cPanel, L.L.C.
#                                                                                All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/locale",
        "app/filters/htmlSafeString",
    ],
    function(angular, _, CJT, LOCALE, HTMLSafeString) {

        "use strict";

        /**
         * Item Lister View is a view that pairs with the item lister to
         * display items manage link. It must
         * be nested within an item lister
         *
         * @module item-lister-view
         * @restrict EA
         * @memberof cpanel.apiTokens
         *
         * @example
         * <item-lister>
         *     <item-lister-view></item-lister-view>
         * </item-lister>
         *
         */

        var MODULE_NAMESPACE = "cpanel.apiTokens.itemListerView.directive";
        var MODULE_REQUIREMENTS = [ HTMLSafeString.namespace ];

        var TEMPLATE = "directives/itemListerView.ptt";
        var RELATIVE_PATH = "api_tokens/" + TEMPLATE;
        var TEMPLATE_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE;
        var CONTROLLER_INJECTABLES = ["$scope", "$location", "ITEM_LISTER_CONSTANTS"];
        var CONTROLLER = function ItemListViewController($scope, $location, ITEM_LISTER_CONSTANTS) {

            $scope.toggleSelection = function toggleSelection(item) {
                if (item.selected) {
                    $scope.$emit(ITEM_LISTER_CONSTANTS.TABLE_ITEM_SELECTED, { item: item } );
                } else {
                    $scope.$emit(ITEM_LISTER_CONSTANTS.TABLE_ITEM_DESELECTED, { item: item } );
                }
            };

            $scope.getCreationLabel = function getCreationLabel(createdOn) {
                return LOCALE.local_datetime(createdOn, "datetime_format_medium");
            };

            $scope.getExpirationLabel = function getExpirationLabel(expiresAt) {
                return expiresAt ? LOCALE.local_datetime(expiresAt, "datetime_format_medium") : "";
            };

            $scope.getRestrictionLabel = function getRestrictionLabel(isUnrestricted) {
                return isUnrestricted ? LOCALE.maketext("Unrestricted") : LOCALE.maketext("Limited");
            };

            $scope.getItems = function getItems() {
                return $scope.items;
            };

            $scope.manageToken = function manageToken(token) {
                $location.path("/manage").search("token", token.id);
            };

        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        module.value("PAGE", PAGE);

        var DIRECTIVE_LINK = function($scope, $element, $attrs, $ctrl) {
            $scope.items = [];
            $scope.headerItems = $ctrl.getHeaderItems();
            $scope.updateView = function updateView(viewData) {
                $scope.items = viewData;
            };
            $ctrl.registerViewCallback($scope.updateView.bind($scope));

            $scope.$on("$destroy", function() {
                $ctrl.deregisterViewCallback($scope.updateView);
            });
        };
        module.directive("itemListerView", function itemListerItem() {

            return {
                templateUrl: TEMPLATE_PATH,
                restrict: "EA",
                replace: true,
                require: "^itemLister",
                link: DIRECTIVE_LINK,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER)

            };

        });

        return {
            "class": CONTROLLER,
            "namespace": MODULE_NAMESPACE,
            "link": DIRECTIVE_LINK,
            "template": TEMPLATE
        };
    }
);
