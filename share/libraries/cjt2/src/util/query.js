/*
# cjt/util/query.js                               Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* jshint -W089             */
/* --------------------------*/

// TODO: Add tests for these

/**
 *
 * @module cjt/util/query
 * @example
 *
 */
define(["lodash"], function(_) {
    "use strict";

    /**
     * Utility module for parsing and building querystrings.
     *
     * @static
     * @public
     * @class query
     */
    var query = {

        // Converts
        //
        //  { foo: [ 1, 2, 3] }
        //
        // to:
        //
        //  {
        //      foo:     1,
        //      "foo-1": 2,
        //      "foo-2": 3
        //  }
        //
        // This is useful for interacting with cPanel’s API.
        expand_arrays_for_cpanel_api: function( data ) {
            var my_args = {};
            for ( var key in data ) {
                if (Array.isArray(data[key])) {
                    my_args[key] = data[key][0];
                    for ( var v = 1; v < data[key].length; v++ ) {
                        my_args[key + "-" + v] = data[key][v];
                    }
                } else {
                    my_args[key] = data[key];
                }
            }

            return my_args;
        },

        // creates an HTTP query string from a JavaScript object
        // For convenience when assembling the data, we make null and undefined
        // values not be part of the query string.
        make_query_string: function( data ) {
            var query_string_parts = [];
            for ( var key in data ) {
                if ( data.hasOwnProperty(key) ) {
                    var value = data[key];
                    if ((value !== null) && (value !== undefined)) {
                        var encoded_key = encodeURIComponent(key);
                        if ( _.isArray( value ) ) {
                            for ( var cv = 0; cv < value.length; cv++ ) {
                                query_string_parts.push( encoded_key + "=" + encodeURIComponent(value[cv]) );
                            }
                        } else {
                            query_string_parts.push( encoded_key + "=" + encodeURIComponent(value) );
                        }
                    }
                }
            }

            return query_string_parts.join("&");
        },

        // parses a given query string, or location.search if none is given
        // returns an object corresponding to those values
        parse_query_string: function( qstr ) {
            if ( qstr === undefined ) {
                qstr = location.search.replace(/^\?/, "");
            }

            var parsed = {};

            if (qstr) {

                // This rejects invalid stuff
                var pairs = qstr.match(/([^=&]*=[^=&]*)/g);
                var plen = pairs.length;
                if ( pairs && pairs.length ) {
                    for (var p = 0; p < plen; p++) {

                        var key_val = _.map(pairs[p].split(/=/), decodeURIComponent);
                        var key = key_val[0].replace(/\+/g, " ");
                        if ( key in parsed ) {
                            if ( typeof parsed[key] !== "string" ) {
                                parsed[key].push(key_val[1].replace(/\+/g, " "));
                            } else {
                                parsed[key] = [ parsed[key_val[0]], key_val[1].replace(/\+/g, " ") ];
                            }
                        } else {
                            parsed[key] = key_val[1].replace(/\+/g, " ");
                        }
                    }
                }
            }

            return parsed;
        }
    };

    return query;
});
