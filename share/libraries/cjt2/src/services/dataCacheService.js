/*
# cjt/services/dataCacheService.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [

        // Libraries
        "angular"
    ],
    function(angular) {

        var module = angular.module("cjt2.services.dataCache", []);
        module.factory("dataCache", function() {
            var _data = {};

            /**
             * Store some application data in the name slot
             * @method set
             * @param {String} name
             * @param {Any} data
             */
            function set(name, data) {
                _data[name] = data;
            }

            /**
             * Fetch some application data in the name slot
             * @method get
             * @param  {String} name
             * @return {Any}
             */
            function get(name) {
                return _data[name];
            }

            /**
             * Remove data from a name slot
             * @method remove
             * @param  {String} name
             * @return {Any}    Returns the data from the slot that is removed.
             */
            function remove(name) {
                return delete _data[name];
            }

            /**
             * Clears all the data in the appData cache.
             * @method clear
             */
            function clear() {
                _data = {};
            }

            /**
             * Returns the full cache object
             * @method cache
             * @return {Object}   The full cache object
             */
            function cache() {
                return _data;
            }

            return {
                set: set,
                get: get,
                remove: remove,
                clear: clear,
                cache: cache,
            };
        });
    }
);
