/*
# cjt/services/APIFailures.js                     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* A service that functions as a custom event for uncaught API failures.
   This, in tandem with APICatcher and modules like growlAPIReporter,
   can ensure that no API failure goes unreported (or errantly reported).

   See APICatcher for more information.
 */

/* global define: false */

define([
    "angular",
],
function(angular) {
    var module = angular.module("cjt2.services.apifailures", []);

    module.factory( "APIFailures", function() {
        var listeners = [];

        return {
            register: listeners.push.bind(listeners),

            emit: function(evt) {
                listeners.forEach( function(todo) {
                    todo(evt);
                } );
            },
        };
    } );
}
);
