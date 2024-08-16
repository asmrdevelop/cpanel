/*
# email_deliverability/services/domainFactory.js     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define([
    "lodash",
    "shared/js/email_deliverability/services/Domain.class"
], function(_, Domain) {

    "use strict";

    /**
         * Factory for Creating Domain based on type
         *
         * @module DomainFactory
         * @memberof cpanel.emailDeliverability
         *
         */

    var DOMAIN_TYPE_CONSTANTS = {
        SUBDOMAIN: "subdomain",
        ADDON: "addon",
        ALIAS: "alias",
        MAIN: "main_domain"
    };

    /**
     * Creates a Domain
     *
     * @method
     * @return {Domain}
     */
    function DomainFactory(mainHomedir, mainDomain) {
        this._mainHomedir = mainHomedir;
        this._mainDomain = mainDomain;

        /**
         *
         * Clean a raw API object
         *
         * @param {Object} rawDomain raw API Object
         * @returns {Object} cleaned object
         */
        function _cleanRaw(rawDomain) {
            rawDomain.homedir = this._mainHomedir;
            rawDomain.documentRoot = rawDomain.documentRoot || rawDomain.dir;
            rawDomain.rootDomain = rawDomain.rootDomain || rawDomain.rootdomain || this._mainDomain;
            rawDomain.redirectsTo = rawDomain.status === "not redirected" ? null : rawDomain.status,

            delete rawDomain.dir;
            delete rawDomain.rootdomain;
            delete rawDomain.status;

            return rawDomain;
        }

        /**
         * create a new Domain from a raw API result
         *
         * @method create
         * @public
         *
         * @param {Object} rawDomain raw API domain object
         * @returns {Domain} new Domain();
         */
        function _create(rawDomain) {
            var cleanedDomain = this._cleanRaw(rawDomain);
            return new Domain(cleanedDomain);
        }

        /**
         * Get the Domain Type Constants
         *
         * @method getTypeConstants
         * @public
         *
         * @returns {Object} domain type constants
        */
        function _getTypeConstants() {
            return DOMAIN_TYPE_CONSTANTS;
        }

        /**
         * Set the main home dir for the user
         *
         * @method setMainHomedir
         * @public
         *
         * @param {String} homedir main home dir for the user
         */
        function _setMainHomedir(homedir) {
            this._mainHomedir = homedir;
        }

        /**
         * Set the main domain for the user
         *
         * @method setMainDomain
         * @public
         *
         * @param {String} domain main domain for the user
         */
        function _setMainDomain(domain) {
            this._mainDomain = domain;
        }

        /**
         * Get the class for the Factory
         *
         * @method getClass
         * @public
         *
         * @returns {Class} returns the Domain class
         */
        function getClass() {
            return Domain;
        }

        this._cleanRaw = _cleanRaw.bind(this);
        this.create = _create.bind(this);
        this.setMainHomedir = _setMainHomedir.bind(this);
        this.setMainDomain = _setMainDomain.bind(this);
        this.getTypeConstants = _getTypeConstants.bind(this);
        this.getClass = getClass.bind(this);
    }

    return new DomainFactory();
}
);
