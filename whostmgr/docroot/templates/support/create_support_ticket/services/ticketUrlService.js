/*
 * whostmgr/docroot/templates/support/create_support_ticket/services/ticketUrlService.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        var app = angular.module("whm.createSupportTicket");

        app.service("ticketUrlService", [
            "$httpParamSerializer",
            "pageState",
            function($httpParamSerializer, pageState) {
                return {

                    /**
                     * Fetch a ticket system url for a specific support scenario.
                     *
                     * @service urlService
                     * @method getTicketUrl
                     * @param  {String} service  Name of the support scenario. @see whostmgr7::create_support_ticket for list of valid names.
                     * @param  {Object} [params] Optional additional query-string parameters as a JavaScript object.
                     * @return {String}          Url in the ticket system to use.
                     */
                    getTicketUrl: function(service, params) {
                        var urls = pageState.new_ticket_urls;
                        var url = urls[service] || urls.generic;
                        var serializedParams = "";
                        if (params) {
                            serializedParams = $httpParamSerializer(params);
                        }
                        return url + (serializedParams ? "&" + serializedParams : "");
                    }
                };
            }
        ]);
    }
);
