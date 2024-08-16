/*
# cjt/util/httpStatus.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define([
    "cjt/util/locale"
],
function(LOCALE) {
    return {

        /**
             * Convert the status code into a human readable string.
             *
             * @static
             * @method convertHttpStatusToReadable
             * @param  {Numer} status String with html characters that need encoding
             * @return {String}       Human readable string for the status.
             */
        convertHttpStatusToReadable: function(status) {
            switch (status) {
                case 100:
                    return LOCALE.maketext("Continue");
                case 101:
                    return LOCALE.maketext("Switching Protocols");
                case 200:
                    return LOCALE.maketext("OK");
                case 201:
                    return LOCALE.maketext("Created");
                case 202:
                    return LOCALE.maketext("Accepted");
                case 203:
                    return LOCALE.maketext("Non-Authoritative Information");
                case 204:
                    return LOCALE.maketext("No Content");
                case 205:
                    return LOCALE.maketext("Reset Content");
                case 206:
                    return LOCALE.maketext("Partial Content");
                case 300:
                    return LOCALE.maketext("Multiple Choices");
                case 301:
                    return LOCALE.maketext("Moved Permanently");
                case 302:
                    return LOCALE.maketext("Found");
                case 303:
                    return LOCALE.maketext("See Other");
                case 304:
                    return LOCALE.maketext("Not Modified");
                case 305:
                    return LOCALE.maketext("Use Proxy");
                case 307:
                    return LOCALE.maketext("Temporary Redirect");
                case 400:
                    return LOCALE.maketext("Bad Request");
                case 401:
                    return LOCALE.maketext("Unauthorized");
                case 402:
                    return LOCALE.maketext("Payment Required");
                case 403:
                    return LOCALE.maketext("Forbidden");
                case 404:
                    return LOCALE.maketext("Not Found");
                case 405:
                    return LOCALE.maketext("Method Not Allowed");
                case 406:
                    return LOCALE.maketext("Not Acceptable");
                case 407:
                    return LOCALE.maketext("Proxy Authentication Required");
                case 408:
                    return LOCALE.maketext("Request Timeout");
                case 409:
                    return LOCALE.maketext("Conflict");
                case 410:
                    return LOCALE.maketext("Gone");
                case 411:
                    return LOCALE.maketext("Length Required");
                case 412:
                    return LOCALE.maketext("Precondition Failed");
                case 413:
                    return LOCALE.maketext("Request Entity Too Large");
                case 414:
                    return LOCALE.maketext("Request-URI Too Long");
                case 415:
                    return LOCALE.maketext("Unsupported Media Type");
                case 416:
                    return LOCALE.maketext("Requested Range Not Satisfiable");
                case 417:
                    return LOCALE.maketext("Expectation Failed");
                case 500:
                    return LOCALE.maketext("Internal Server Error");
                case 501:
                    return LOCALE.maketext("Not Implemented");
                case 502:
                    return LOCALE.maketext("Bad Gateway");
                case 503:
                    return LOCALE.maketext("Service Unavailable");
                case 504:
                    return LOCALE.maketext("Gateway Timeout");
                case 505:
                    return LOCALE.maketext("HTTP Version Not Supported");
                default:
                    return LOCALE.maketext("Unknown Error");
            }
        }
    };
}
);
