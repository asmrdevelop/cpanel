(function() {

    /* -----------------------------------------------*/
    /* Explicit JSHINT RULES                         */
    /* -----------------------------------------------*/
    /* jshint sub:true */
    /* global CPANEL:true, YAHOO:true, window:true, document: true */
    /* -----------------------------------------------*/

    "use strict";

    // Shortcuts
    var VALIDATION = CPANEL.validate;
    var DOM = YAHOO.util.Dom;

    // Generate the needed namespaces
    var APPLICATIONS = CPANEL.namespace("CPANEL.Applications");

    /**
     * This module contains the common code for the ssl applications in cPanel.
     * @module CPANEL.Applications.SSL
     */

    APPLICATIONS.SSL = {

        /**
         * Check if the given string is a valid SSL domain;
         * i.e., it's either a valid domain, or *.<valid domain>.
         *
         * @method isValidSSLDomain
         * @param {HTMLElement} el The Dom element to validate contains a domain
         * @return {Boolean} Whether the given string is a valid SSL domain.
         */
        isValidSSLDomain: function(el) {
            var domain = el.value.trim();
            return VALIDATION.host(domain.replace(/^\*\./, ""));
        },

        /**
         * Check if the given string is a valid SSL domain;
         * i.e., it"s either a valid domain, or *.<valid domain>.
         *
         * @method isValidSSLDomain
         * @param {HTMLElement} el The Dom element to validate contains a domain
         * @return {Boolean} Whether the given string is a valid SSL domain.
         */
        areValidSSLDomains: function(el) {
            var domains = el.value.trim().split(/[,;\s]+/);
            return domains.every( function(d) {
                return VALIDATION.host(d.replace(/^\*\./, ""));
            } );
        },

        /**
         * Returns true if the value is defined, false otherwise, allowing
         * validation rules to be defined for optional fields.
         * @method  isOptionalIfUndefined
         * @param  {HTMLElement}  el Element to check.
         * @return {Boolean}    Returns true if the element has a value, false otherwise.
         */
        isOptionalIfUndefined: function(el) {
            if (el && el.value !== "") {
                return true;
            }
            return false;
        },

        /**
         * Test the element to see if it contains only ASCII alpha,
         * and spaces and dashes.
         * @method  isAlphaOrWhitespace
         * @param  {[type]}  el [description]
         * @return {Boolean}    [description]
         */
        isAlphaOrWhitespace: function(el) {
            if (el && el.value !== "") {
                return (/^[\-A-Za-z ]+$/).test(el.value);
            }
            return false;
        }
    };
})();
