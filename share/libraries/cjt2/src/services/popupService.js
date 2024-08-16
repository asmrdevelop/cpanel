/*
 * services/popupService.js                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * DEVELOPERS NOTES:
 */

/* global define: false */

define([
    "angular",
    "lodash"
], function(
        angular,
        _
    ) {

    var module = angular.module("cjt2.services.popupService", []);

    // Applications can customize the defaults by
    // injecting it in startup code replacing values
    // as needed.
    module.value("popupServiceDefaults", {
        top: 0,
        left: 0,
        width: 400,
        height: 300,
        autoCenter: true,
        name: "_blank"
    }
    );

    module.service("popupService", [
        "$window",
        "popupServiceDefaults",
        function(
            $window,
            DEFAULTS
        ) {

            var numberProps  = { "top": true, "left": true, "width": true, "height": true };
            var booleanProps = { "scrollbar": true, "menubar": true, "toolbar": true, "location": true, "status": true };
            var ignoredProps = { "autoCenter": true, "newTab": true, "name": true };

            /**
             * Generate a window.open() style specification string.
             *
             * @private
             * @name  _makeWindowSpec
             * @param  {Object} opts
             *   @param {Number}  [opts.top]    Optional. Top position of dialog
             *   @param {Number}  [opts.left]   Optional. Left position of dialog
             *   @param {Number}  [opts.width]  Optional. Width of the dialog
             *   @param {Number}  [opts.height] Optional. Height of the dialog
             *   @param {Boolean} [opts.scrollBar] Optional. Shows scrollbar if true, hides it if false.
             *   @param {Boolean} [opts.autoCenter] Optional. Centers the popup if true, does not center if false. Defaults to auto centering.
             * @return {String}
             */
            function _makeWindowSpec(opts) {
                var spec         = [];
                _.each(opts, function(value, key) {
                    if (numberProps[key] && !angular.isUndefined(value) && angular.isNumber(value)) {
                        spec.push(key + "=" + value);
                    } else if (booleanProps[key] && !angular.isUndefined(value)) {
                        spec.push(key + "=" + (value ? "yes" : "no"));
                    } else if (!ignoredProps[key]) {
                        throw "Unsupported property: " + key;
                    }
                });
                return spec.join(",");
            }

            return {

                /**
                 * Show a popup window with the provided url and name. Additional
                 * options are available in the opts as described below:
                 *
                 * @method openPopupWindow
                 * @public
                 * @param  {String} url    Url to navigate to in the window.
                 * @param  {String} [name] Optional. Name of the window.
                 * @param  {Object} [opts] Optional. With the following possible properties:
                 *   @param {Number}  [opts.top]    Optional. Top position of dialog
                 *   @param {Number}  [opts.left]   Optional. Left position of dialog
                 *   @param {Number}  [opts.width]  Optional. Width of the dialog
                 *   @param {Number}  [opts.height] Optional. Height of the dialog
                 *   @param {Boolean} [opts.scrollbars] Optional. Shows scrollbar if true, hides it if false.
                 *   @param {Boolean} [opts.autoCenter] Optional. Centers the popup if true, does not center if false. Defaults to auto centering.
                 *   @param {Boolean} [opts.newTab] Optional. Opens in a new tab instead of a popup. top/left/width/height are ignored.
                 * @return {WindowHandle} Handle to the popup.
                 */
                openPopupWindow: function(url, name, opts) {
                    if (!opts) {
                        opts = {};
                    }

                    name = name || DEFAULTS.name;

                    // Initialize the defaults
                    _.each(numberProps, function(value, key) {
                        if (!angular.isUndefined(opts[key]) ||
                            !angular.isUndefined(DEFAULTS[key])) {
                            opts[key] = opts[key] || DEFAULTS[key];
                        }

                    });
                    _.each(booleanProps, function(value, key) {
                        if (!angular.isUndefined(opts[key]) ||
                            !angular.isUndefined(DEFAULTS[key])) {
                            opts[key] = opts[key] || DEFAULTS[key];
                        }
                    });

                    // Calculate the centering if needed
                    if (!opts.newTab && opts.autoCenter) {

                        // Since IE does not support availTop and availLeft, we degrade to showing the
                        // popup in the primary monitor using screen.top and screen.left to help decide
                        // NOTE: Auto centering does not work on IEEdge if the parent window is not full
                        // screen. This seems to be related to this bug:
                        //   https://connect.microsoft.com/IE/Feedback/Details/2434857
                        var top    = !angular.isUndefined($window.screen.availTop) ? $window.screen.availTop : $window.screenTop;
                        var left   = !angular.isUndefined($window.screen.availLeft) ? $window.screen.availLeft : $window.screenLeft;
                        var height = !angular.isUndefined($window.screen.availHeight) ? $window.screen.availHeight : $window.screen.height;
                        var width  = !angular.isUndefined($window.screen.availWidth) ? $window.screen.availWidth : $window.screen.width;

                        // Now do the centering
                        opts.top  = (top + height / 2) - (opts.height / 2);
                        opts.left = (left + width / 2) - (opts.width / 2);
                    }

                    if (opts.newTab) {
                        delete opts.top;
                        delete opts.left;
                        delete opts.width;
                        delete opts.height;
                    }

                    var spec = _makeWindowSpec(opts);

                    return $window.open(url, name, spec);
                },

                defaults: DEFAULTS,
            };
        }
    ]);
});
