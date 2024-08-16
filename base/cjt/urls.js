/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including urls.js!");
} else {

    /**
	The urls module contains URLs for AJAX calls.
	@module urls
*/

    /**
	The urls class URLs for AJAX calls.
	@class urls
	@namespace CPANEL
	@extends CPANEL
*/
    CPANEL.urls = {

        /**
		URL for the password strength AJAX call.<br />
		GET request<br />
		arg1: password=password
		@property password_strength
		@type string
	*/
        password_strength: function() {
            return CPANEL.security_token + "/backend/passwordstrength.cgi";
        },

        // build a JSON API call from an object
        json_api: function(object) {

            // build the query string
            var query_string = "";
            for (var item in object) {
                if (object.hasOwnProperty(item)) {
                    query_string += encodeURIComponent(item) + "=" + encodeURIComponent(object[item]) + "&";
                }
            }

            // add some salt to prevent browser caching
            query_string += "cache_fix=" + new Date().getTime();

            return CPANEL.security_token + "/json-api/cpanel?" + query_string;
        },

        // build a JSON API call from an object
        uapi: function(module, func, args) {

            // build the query string
            var query_string = "";
            for (var item in args) {
                if (args.hasOwnProperty(item)) {
                    query_string += encodeURIComponent(item) + "=" + encodeURIComponent(args[item]) + "&";
                }
            }

            // add some salt to prevent browser caching
            query_string += "cache_fix=" + new Date().getTime();

            return CPANEL.security_token + "/execute/" + module + "/" + func + "?" + query_string;
        },

        whm_api: function(script, params, api_mode) {
            if (!api_mode) {
                api_mode = "json-api";
            } else if (api_mode == "xml") {
                api_mode = "xml-api";
            }

            // build the query string
            // TODO: turn this into a general object->query string function
            // 		 also have a query params -> object function
            var query_string = "";
            for (var item in params) {
                if (params.hasOwnProperty(item)) {
                    query_string += encodeURIComponent(item) + "=" + encodeURIComponent(params[item]) + "&";
                }
            }

            // add some salt to prevent browser caching
            query_string += "cache_fix=" + new Date().getTime();

            return CPANEL.security_token + "/" + api_mode + "/" + script + "?" + query_string;
        }

    }; // end urls object
} // end else statement
