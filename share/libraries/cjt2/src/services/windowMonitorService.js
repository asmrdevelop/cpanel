/*
 * services/windowMonitorService.js                Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * DEVELOPERS NOTES:
 * 1) Currently this service sets up a separate monitor for each window.
 * It may be more efficient to setup a single monitor when the first window
 * is registered with the service and keep it around until the last window
 * monitored is detached.
 * 2) I'm not sure the current _isWindow() method provides enough verification
 * if the passed object is a window though its adequate to keep from getting
 * exceptions.
 */

/* global define: false */

define([
    "angular",
    "lodash"
], function(
        angular,
        _
    ) {

    var module = angular.module("cjt2.services.windowMonitor", []);

    module.constant("windowMonitorServiceConfig", {

        /**
         * The windowMonitorService polls windows handels registered
         * with it to detect if the window is closed. Once it detects
         * a closed window, it will call a callback. This interval is
         * the time between polling runs.
         *
         * @name  windowMonitorServiceConfig.monitorInterval
         * @type {Number} Number of milliseconds to wait between polls of the
         * windows to see if they have closed.
         */
        monitorInterval: 250 // millisecond
    });

    module.factory("windowMonitorService", [
        "$q",
        "$interval",
        "windowMonitorServiceConfig",
        function(
            $q,
            $interval,
            windowMonitorServiceConfig
        ) {

            var _id = 0;
            var _intervals = {};

            /**
             * Performs a very basic check to see if the passed object is of type Window.
             * This is helpful since we can't rely on instanceof for window objects and
             * there's no uniform standard for identifying a window object, particularly
             * once it has been closed.
             *
             * @method _isWindow
             * @private
             * @param  {Object} obj   The object to be tested.
             * @return {Boolean}      True if it's a Window object.
             */
            function _isWindow(obj) {
                return angular.isDefined(obj.closed);
            }

            /**
             * Stop a referenced window monitor and cleanup
             *
             * @method   _stop
             * @private
             * @param  {Object} reference
             */
            function _stop(reference) {
                if (reference) {
                    $interval.cancel(reference.promise);
                    delete _intervals[reference.id];
                }
            }

            var api = {

                /**
                 * Periodically check to see if a window in storage is closed or not, and execute a
                 * callback function, if it is closed.
                 *
                 * @method start
                 * @param  {Window}   handle      The window to monitor.
                 * @param  {Function} callback    The function to execute if the window is closed.
                 * @param  {Number}   [frequency] The interval in milliseconds. Defaults to what is
                 *                                set in the windowMonitorServiceConfig.monitorInterval.
                 */
                start: function(handle, callback, frequency) {
                    var promise;
                    var id = _id++;
                    var interval = frequency || windowMonitorServiceConfig.monitorInterval;

                    var fn = function() {
                        if (handle.closed) {
                            callback("closed", handle);
                            api.stop(handle, true);
                        }
                    };

                    if (handle && angular.isFunction(callback)) {
                        promise = $interval(fn, interval);

                        // Save the interval information
                        _intervals[id] = {
                            id: id,
                            handle: handle,
                            promise: promise,
                            callback: callback
                        };
                    } else {
                        throw new ReferenceError("Both an window and a callback function are required.");
                    }

                    return handle;
                },

                /**
                 * Stop monitoring a window that is being watched
                 *
                 * @method stop
                 * @param  {Window} handle  The window being monitored
                 * @param  {Boolean} [auto] Used internally only.
                 */
                stop: function(handle, auto) {
                    if (!handle) {
                        throw new ReferenceError("The stop method requires an window handle argument.");
                    }

                    var reference;
                    if (_isWindow(handle)) {
                        reference = _.find(_intervals, function(ref) {
                            return handle === ref.handle;
                        });
                    }

                    if (reference) {
                        if (!auto) {
                            reference.callback("canceled", reference.handle);
                        }
                        _stop(reference);
                    }
                },

                /**
                 * Check if the service is monitoring anything.
                 *
                 * @method isMonitoring
                 * @return {Boolean} true if monitoring anything, false otherwise.
                 */
                isMonitoring: function() {
                    return _intervals && Object.keys(_intervals).length > 0;
                },

                /**
                 * Stop all registered monitors
                 *
                 * @method stopAll
                 */
                stopAll: function() {
                    angular.forEach(_intervals, function(reference) {
                        _stop(reference);
                    });
                }

            };

            return api;
        }
    ]);
});
