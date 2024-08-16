/*
 * index.js                                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global PAGE, $ */

$(function() {
    "use strict";

    // Set all progress icons to their greyed-out default states
    setProgressIcon("grant", "default");
    setProgressIcon("ssh-test", "default");
    setProgressIcon("redirect", "default");

    // Set up the event listener for the button
    $("#grant-access-form").on("submit", function(e) {
        e.preventDefault();
        processAll(ticketId, serverNum);
    });

    // Gather our initial query args
    var ticketId = PAGE.ticket_id;
    var serverNum = PAGE.server_num;
    var redirectUri = PAGE.redirect_uri;

    if ( !ticketId || ticketId < 1 ) {
        throw "Developer Error: ticketId must be a number above 0";
    }
    if ( !serverNum || serverNum < 1 ) {
        throw "Developer Error: serverNum must be a number above 0";
    }
    if ( !redirectUri ) {
        throw "Developer Error: redirectUri must be provided";
    }

    /**
     * Initiates the API calls and manages the overall process.
     *
     * @method processAll
     * @param  {Number} ticketId    The ticket ID that's being granted access.
     * @param  {Number} serverNum   The server number (as listed in the ticket).
     */
    function processAll(ticketId, serverNum) {

        // Move to the progress view
        $("#grant-access-form").hide();
        $("#progress-view").show();

        // Start the API calls
        var grantStatus, grantError;
        grantAccess(ticketId, serverNum).then(
            function success(status) {
                grantStatus = 200;
                return startSshTest(ticketId, serverNum);
            },
            function failure(error) {
                grantStatus = 400;
                grantError = error;
            }
        ).always(function() {
            redirectToCustomerPortal(grantStatus, grantError);
        });
    }

    /**
     * Grants access and sends the server information to the ticket system.
     *
     * @method grantAccess
     * @param  {Number} ticketId    The ticket ID that's being granted access.
     * @param  {Number} serverNum   The server number (as listed in the ticket).
     * @return {Promise}            Tied to the grant API call. When complete it will resolve
     *                              or reject with an object containing a numeric status and
     *                              conditional error string.
     */
    function grantAccess(ticketId, serverNum) {

        // Start the Grant spinner
        setProgressIcon("grant", "run");

        // Submit the API request
        return whmApi1({
            method: "ticket_grant",
            queryObj: {
                ticket_id: ticketId,
                server_num: serverNum,
            }
        }).then(
            function success(resp) {

                // Stop the spinner
                setProgressIcon("grant", "done");
                return resp;
            },
            function failure(error) {

                // Stop the spinner
                setProgressIcon("grant", "error");
                return $.Deferred().reject(error);
            }
        );
    }

    /**
     * Initiates an SSH test without waiting for the response.
     *
     * @method startSshTest
     * @param  {Number} ticketId    The ticket ID that contains the server information you wish to test.
     * @param  {Number} serverNum   The server number (as listed in the ticket) to test.
     * @return {Promise}            Tied to the SSH test API call.
     */
    function startSshTest(ticketId, serverNum) {

        // Start the SSH test spinner
        setProgressIcon("ssh-test", "run");

        // Submit the API request
        return whmApi1({
            method: "ticket_ssh_test_start",
            queryObj: {
                ticket_id: ticketId,
                server_num: serverNum,
            }
        }).then(
            function success(resp) {

                // Stop the spinner
                setProgressIcon("ssh-test", "done");
                return resp;
            },
            function failure(error) {

                // Stop the spinner
                setProgressIcon("ssh-test", "error");
                return $.Deferred().reject(error);
            }
        );
    }

    /**
     * Sends the user to the redirect_uri with the status of the Grant step.
     *
     * @method redirectToCustomerPortal
     * @param  {Number} status     The RESTful status code related to the execution of the Grant
     *                             step. This value will be passed as a query arg to the redirect_uri.
     * @param  {String} [error]    Optional. A more detailed error string if the Grant step wasn't
     *                             successful.
     */
    function redirectToCustomerPortal(status, error) {

        // Start the redirect spinner
        setProgressIcon("redirect", "run");

        // Get the current query as a hash
        var queryObj = _parseQuery();

        // Add our specific query args
        queryObj.status = status;
        if (error) {
            queryObj.error = error;
        }

        // Set the location to the redirect_uri
        var queryStr = $.param(queryObj, true);
        location.href = redirectUri + "?" + queryStr;
    }

    /**
     * Makes a WHM API 1 call and executes a callback function.
     *
     * @param  {Object} args
     *     @param {String} method         The WHM API 1 method to call.
     *     @param {Object} [queryObj]     Optional. A hash of query arguments to include in the query string.
     *     @param {Function} [callback]   Optional. A callback function.
     * @return {jqXHR}                    The jqXHR object for the API request.
     */
    function whmApi1(args) {

        // Set the WHM API version to 1
        args.queryObj = args.queryObj || {};
        args.queryObj["api.version"] = 1;

        var urlBase = location.href.match(/^.*\/cpsess\d+\//) + "json-api/";
        var fullUrl = urlBase + args.method;

        var xhr = $.ajax({
            url: fullUrl,
            method: "GET",
            data: args.queryObj,
            dataType: "json",
            timeout: 300000, // 300 seconds = 5 minutes
        }).then(
            function success(resp) {

                // Handle malformed responses.
                if (!resp || !resp.metadata) {
                    return $.Deferred().reject("Unknown API error");
                } else if (resp.metadata.result === 0) {

                    // WHM usually gives a 200 HTTP status even when there is an API error returned.
                    return $.Deferred().reject(resp.metadata.reason);
                } else {

                    // The happy path.
                    return resp;
                }
            },
            function failure(jqXHR, textStatus, error) {
                if (textStatus === "timeout") {
                    return $.Deferred().reject("API timeout");
                } else if (error) {
                    return $.Deferred().reject("API error " + jqXHR.status + " (" + error + ")");
                } else if (jqXHR.status >= 200 && jqXHR.status < 400) {

                    // For issues not related to transport (parse failures etc.) that don't have a
                    // descriptive error string to use.
                    return $.Deferred().reject("API error: " + textStatus);
                } else {

                    // No error string, and no helpful textStatus, so just give the HTTP status code.
                    return $.Deferred().reject("API error " + jqXHR.status);
                }
            }
        );

        return xhr;
    }

    /**
     * Take the location's current query string and transform it into a hash. Ignore any
     * query arguments that don't have values associated with them.
     *
     * @method  _parseQuery
     * @return {Object}   An objectified version of the query string.
     */
    function _parseQuery() {
        var queryObj = {};
        location.search.substring(1).split("&").forEach(function(singleParamStr) {
            var split = singleParamStr.split("=");
            if (split.length > 1) { // Ignore value-less param names
                queryObj[ split[0] ] = split[1];
            }
        });
        return queryObj;
    }

    /**
     * Shows the specified progress icon for the specified process. Only one icon
     * will show at a time for a given process.
     *
     * @method setProgressIcon
     * @param {String} processName    The name of the process whose icon will be modified.
     * @param {String} newIconState   The name of the state represented by the icon.
     */
    function setProgressIcon(processName, newIconState) {

        var $icons = $("#" + processName + "-progress .fas");
        var $newIcon = $icons.filter("[icon-state=" + newIconState + "]");

        $icons.hide();
        $newIcon.show();
    }

});
