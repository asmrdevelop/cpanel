/*
# cjt/directives/alertList.js                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "jquery", // Used for the height/width methods
        "cjt/core",
        "lodash",
        "ngAnimate",
        "ngSanitize",
        "cjt/directives/alert",
        "cjt/config/componentConfiguration",
        "cjt/services/alertService",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, $, CJT, _) {
        "use strict";

        var DEFAULT_INLINE = false;

        var RELATIVE_PATH = "libraries/cjt2/directives/alertList.phtml";

        var module = angular.module("cjt2.directives.alertList", [
            "cjt2.config.componentConfiguration",
            "cjt2.templates",
            "ngAnimate",
            "ngSanitize",
            "cjt2.directives.alert",
        ]);

        /**
         * We don't want to include the top bar in our calculations of available space
         * for the alertList content. These values are duplicated in alertList.less, so
         * please update them in both places if they ever change.
         */
        var TOP_BAR_OFFSETS = {

            whostmgrSm: 120,
            cpanelSm: 52,
            webmailSm: 52,

            whostmgrXs: 70,
            cpanelXs: 30,
            webmailXs: 30,
        };

        /**
         * Validate a position.
         *
         * @method _validatePosition
         * @param  {String}  position A potential value.
         * @return {Boolean} true if valid, false otherwise.
         */
        function _validatePosition(position) {
            if (!position) {
                return true;
            } // It's ok for it not to be set
            switch (position) {
                case "top-left":
                case "top-middle":
                case "top-right":
                case "bottom-left":
                case "bottom-middle":
                case "bottom-right":
                case "middle-left":
                case "middle-middle":
                case "middle-right":
                    return true;
                default:
                    window.console.log("Invalid alertList.position set. It must be one of: top-left, top-middle, top-right, bottom-left, bottom-middle, bottom-right, middle-left, middle-middle, middle-right");
                    return false;
            }
        }

        /**
         * This is a directive that creates a list of alert directives using the alertService.
         *
         * Basic usage in a template:
         * <cp-alert-list></cp-alert-list>
         *
         * Template usage with a non-default alert group and auto-close:
         * <cp-alert-list alert-group="'testGroup'" auto-close="2000"></cp-alert-list>
         *
         * Please note that quotes are required in the alert-group attribute when
         * using a string.
         *
         * Now to add an alert, you can do something like any of the following:
         * alertService.add({
         *     message: "This is my alert message that is not closeable",
         *     closeable: false
         * });
         *
         * alertService.add({
         *     message: "This alert will stack with any alerts already present",
         *     replace: false
         * });
         *
         * alertService.add({
         *     message: "This alert specifies the type instead of using the default",
         *     type: "danger"
         * });
         *
         * alertService.add({
         *     message: "This alert add to the specified group instead of the default",
         *     type: "info",
         *     group: "testGroup"
         * });
         *
         * Please see the alertService documentation for more information.
         */
        module.directive("cpAlertList", [
            "alertService",
            "componentConfiguration",
            function(
                alertService,
                componentConfiguration
            ) {

                return {
                    restrict: "E",
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                    replace: true,
                    scope: {
                        alertGroup: "=",
                        autoClose: "=",
                        position: "=",
                    },
                    controller: ["$scope", "$element", "$window", "$attrs",
                        function($scope, $element, $window, $attrs) {

                            $scope.rules = {
                                position: null,
                                inline: DEFAULT_INLINE
                            };

                            $scope.$watch("inline", function() {
                                if ($scope.rules.inline !== $scope.inline) {
                                    refreshPositionRules();
                                }
                            });

                            $scope.$watch("position", function() {
                                if ($scope.rules.position !== $scope.position && _validatePosition($scope.position)) {
                                    refreshPositionRules();
                                }
                            });

                            $scope.$watchCollection(function() {
                                return componentConfiguration.getComponent("alertList");
                            }, function() {
                                refreshPositionRules();
                            });

                            // NOTE: Due to the dynamic nature of the whm header with breadcrumbs
                            // causing the header to grow in an unpredictable way, we have to
                            // dynamically adjust the top from the static value defined above.
                            // These expensive adjustments are only needed right now for whm.
                            // All code that uses them will check if the contentContainer is
                            // defined to make the decisions about applying the expensive extra
                            // adjustments.
                            //
                            // Other solutions I looked at:
                            //   * ResizeObserver - not native except for Chrome
                            //   * MutationObserver - complex to implement
                            //   * ResizeObserverPolyfill - ok, but requires adding an RPM, requires inefficent timers for some browsers.
                            //
                            // The current solution just addresses the problem where it exists
                            // presently without adding a polyfill or providing other signifigant
                            // cross-browser complex solutions at least for the size testing.

                            var contentContainer = CJT.isWhm() ? angular.element("#contentContainer") : null;
                            var contentContainerTop = getDefaultContainerTop();

                            /**
                             * Fetch the default top position. This is the hardcoded minimum.
                             *
                             * @return {Number} Pixel location to set as the top based only
                             * on the static minimums defined by them and grid size.
                             */
                            function getDefaultContainerTop() {
                                var customApplicationWidth = CJT.isWebmail() ? 667 : 768;

                                // We need a default even for whm or the fixed top will get set to 0 which will
                                // trigger the hidden top of the application problem.
                                return $window.innerWidth < customApplicationWidth ?
                                    TOP_BAR_OFFSETS[CJT.applicationName + "Xs"] :
                                    TOP_BAR_OFFSETS[CJT.applicationName + "Sm"];
                            }

                            /**
                             * Update contentContainerTop with the actual top of the contentContainer
                             * in WHM, in case the contentContainer has been pushed down below its default
                             * top. For other environments, we will just use the defaults, since their
                             * contents will always start at the default position for a given width.
                             *
                             * In either case, this method has the side effect of setting the alertList's
                             * top property if it has changed.
                             *
                             * @method updateContentContainerTop
                             */
                            function updateContentContainerTop() {
                                var defaultTopForCurrentWidth = getDefaultContainerTop();
                                if (contentContainer && contentContainer.length) {

                                    // Handle WHM
                                    var actualContainerTop = contentContainer[0].getBoundingClientRect().top;
                                    if (actualContainerTop !== contentContainerTop) {
                                        contentContainerTop = Math.max(actualContainerTop, defaultTopForCurrentWidth);
                                        $element.css("top", contentContainerTop);
                                    }
                                } else if (contentContainerTop !== defaultTopForCurrentWidth) {

                                    // Handle everything else, if the default top has changed
                                    contentContainerTop = defaultTopForCurrentWidth;
                                    $element.css("top", contentContainerTop);
                                }
                            }

                            /**
                             * Calculate the height at which to turn on the scrollbar
                             * for the alert list.
                             *
                             * @method calculateHeightToTurnOnScroll
                             */
                            function calculateHeightToTurnOnScroll() {
                                var windowHeight = $window.innerHeight;
                                $scope.heightToTurnOnScroll = windowHeight - contentContainerTop;
                            }

                            /**
                             * Update the position properties
                             *
                             * @method updatePosition
                             * @param  {String}  position Position of the alertList if inline is false.
                             * @param  {Boolean} inline   Inline if true, positioned otherwise.
                             */
                            function updatePosition(position, inline) {
                                if (position !== null) {
                                    $scope.rules.position = position;
                                }
                                if (inline !== null) {
                                    $scope.rules.inline = inline;
                                }
                            }

                            /**
                             * Refresh the positioning rules from the attributes and
                             * the componentConfiguration service.
                             *
                             * @method refreshPositionRules
                             */
                            function refreshPositionRules() {
                                var rules = componentConfiguration.getComponent("alertList");
                                updatePosition(rules.position, rules.inline);

                                if ($attrs.hasOwnProperty("inline")) {
                                    updatePosition(null, true);
                                }

                                if (angular.isDefined($scope.position) && $scope.position && _validatePosition($scope.position)) {
                                    updatePosition($scope.position, null);
                                }
                            }

                            /**
                             * Handle resize to adjust the heightToTurnOnScroll
                             * scope variable.
                             *
                             * @method  onResize
                             * @private
                             */
                            function onResize() {

                                updateContentContainerTop();
                                calculateHeightToTurnOnScroll();

                                // manual $digest required as resize event
                                // is outside of angular
                                $scope.$digest();
                            }

                            /**
                             * This method allows the user to close the alert only when it appears
                             * in the center of the page, by pressing escape key or by clicking
                             * anywhere but the alert popup.
                             *
                             * @method closeAlerts
                             * @param {Event} event - The keyboard/mouse event.
                             */
                            function closeAlerts(event) {
                                if ($scope.rules.inline || $scope.rules.position !== "middle-middle" || !$scope.alertsPresent) {
                                    return;
                                }

                                // close all alerts when the ESC key is pressed or when a click is caught outside of the alert itself
                                // we use closest here to ensure that we are not clicking inside of the alert container
                                if ((event.type === "keyup" && event.keyCode === 27) ||
                                    (event.type === "click" && angular.element(event.target).closest(".alert-container").length === 0)) {
                                    alertService.clear(null, $scope.alertGroup);

                                    // Unregister the click & key events.
                                    angular.element($window).off("keyup click", closeAlerts);
                                    $scope.$digest();
                                }
                            }

                            var debounceOnResizeFn = _.throttle(onResize, 60);
                            angular.element($window)
                                .on("resize", debounceOnResizeFn)
                                .on("toggle-navigation", onResize);

                            $scope.$on("$destroy", function() {
                                angular.element($window)
                                    .off("resize", debounceOnResizeFn)
                                    .off("toggle-navigation", onResize)
                                    .off("keyup click", closeAlerts);
                            });

                            // Get the initial UI height.
                            updateContentContainerTop();
                            calculateHeightToTurnOnScroll();
                            refreshPositionRules();

                            /**
                             * Gets the position classes to apply to the list container based on the
                             * user's settings in nvdata:alert-list-rules. If this is an inline list,
                             * then we don't provide the user's preference. This should only be used
                             * in special cases where local feedback is required.
                             *
                             * @method getPositionClasses
                             * @scope
                             * @return {String} css classname list to apply to the alertList class attribute.
                             */
                            $scope.getPositionClasses = function() {
                                return "position-" + ($scope.rules.inline ? "inline" : $scope.rules.position);
                            };

                            /**
                             * Determines whether or not the alert list has exceeded the viewable
                             * height of the page.
                             *
                             * @return {Boolean}   True if the list of alerts is taller than the
                             *                     visible space below the top bar.
                             */
                            $scope.needsScrollbar = function() {
                                if ($scope.rules.inline) {
                                    return false;
                                }

                                if (!angular.isDefined($scope.heightToTurnOnScroll)) {
                                    calculateHeightToTurnOnScroll();
                                }

                                var listHeight = $element.find(".alert-list").height();
                                return ($scope.alerts && $scope.alerts.length > 0 && listHeight >= $scope.heightToTurnOnScroll);
                            };

                            /**
                             * Set the height of the directive container equal to the visible space
                             * below the top bar if we need a scrollbar or the height has changed.
                             */
                            $scope.$watchGroup([
                                "needsScrollbar()",
                                "heightToTurnOnScroll",
                            ], function(newVals) {
                                var needsScrollbar = newVals[0];
                                var heightToTurnOnScroll = newVals[1];

                                if (needsScrollbar) {
                                    $element.css("height", heightToTurnOnScroll + "px");
                                } else {
                                    $element.css("height", "auto");
                                }
                            });

                            // Bind to the alert array from the service
                            $scope.alerts = alertService.getAlerts($scope.alertGroup);

                            $scope.$watchCollection("alerts", function(alerts) {
                                var applyAutoClose = !CJT.isE2E() && $scope.autoClose;
                                if (alerts.length) {
                                    $scope.alertsPresent = true;
                                } else {
                                    $scope.alertsPresent = false;
                                }
                                alerts.forEach(function(alert) {

                                    // If an autoClose is provided add it to any of the alerts
                                    // that don't define their own auto close.
                                    // NOTE: If we are running in an e2e test, we want to disable
                                    // auto-close.
                                    if (applyAutoClose && !alert.autoClose) {
                                        alert.autoClose = $scope.autoClose;
                                    }

                                    /**
                                     * Add the closable property as true to any non-inline alert
                                     * since these were not originally designed to cover up stuff
                                     * and will now. This means that far less of the code needs to
                                     * be modified to make these alertList changes work.
                                     */
                                    if (!$scope.rules.inline) {
                                        alert.closeable = true;
                                    }
                                });
                            });

                            /**
                             * Event addAlertCalled used to register
                             * click/keypup events for center positioned
                             * alerts.
                            */
                            $scope.$on("addAlertCalled", function(event) {
                                angular.element($window).on("keyup click", closeAlerts);
                            });

                            /**
                             * Close the alert
                             *
                             * @method closeAlert
                             * @param  {Number} index Position in the list to close.
                             */
                            $scope.$on("closeAlertCalled", function(event, args) {
                                alertService.removeById(args.id, $scope.alertGroup);
                                angular.element($window).off("keyup click", closeAlerts);
                            });
                        }
                    ]
                };

            }
        ]);

        module.animation(".alert-container", ["$animateCss", function($animateCss) {
            return {
                enter: function(elem, done) {
                    var height = elem[0].offsetHeight;
                    return $animateCss(elem, {
                        from: { height: "0" },
                        to: { height: height + "px" },
                        duration: 0.3,
                        easing: "ease-out",
                        event: "enter",
                        structural: true
                    })
                        .start()
                        .finally(function() {
                            elem[0].style.height = "";
                            done();
                        });
                },
                leave: function(elem, done) {
                    var height = elem[0].offsetHeight;
                    return $animateCss(elem, {
                        event: "leave",
                        structural: true,
                        from: { opacity: "1" },
                        to: { opacity: "0", transform: "translateX(50px)" },
                        duration: 0.3,
                        easing: "ease-out",
                    })
                        .start()
                        .done(function() {
                            $animateCss(elem, {
                                event: "leave",
                                structural: true,
                                from: { height: height + "px" },
                                to: { height: "0" },
                                duration: 0.3,
                                easing: "ease-out",
                            }).start().finally(function() {
                                done();
                            });
                        });
                },
            };
        }]);
    }
);
