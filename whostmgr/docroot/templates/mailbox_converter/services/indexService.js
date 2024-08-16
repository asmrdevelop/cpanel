/*
# templates/mailbox_converter/services/indexService.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
    ],
    function(angular) {

        var app = angular.module("App");

        function indexServiceFactory() {
            var indexService = {};
            var _format;
            var _accounts;

            indexService.set_accounts = function(accounts) {
                _accounts = accounts;
                return _accounts;
            };

            indexService.get_accounts = function() {
                return _accounts;
            };

            indexService.set_format = function(format) {
                if (format !== _format && Array.isArray(_accounts)) {

                    // reset selected accounts in case we swap our maildir choice
                    _accounts.forEach(function(item) {
                        item.selected = 0;
                    });
                }
                _format = format;
                return _format;
            };

            indexService.get_format = function() {
                return _format;
            };

            return indexService;
        }

        return app.factory("indexService", indexServiceFactory);
    });
