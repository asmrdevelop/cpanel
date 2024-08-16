/*
 * cjt2/services/pageIdentifierService.js             Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * Service that generates a page specific identifer for use by other services
 *
 * @module cjt/services/pageIdentifer
 *
 */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
    ],
    function(angular, CJT, LOCALE) {
        "use strict";

        // Retrieve the current application
        var module = angular.module("cjt2.services.pageIdentiferService", []);

        module.factory("pageIdentifierService", [
            "$document",
            function($document) {
                return {

                    /**
                     * Generated page identifier.
                     *
                     * @name _pageIdentifier
                     * @type {?String}
                     * @private
                     */
                    _pageIdentifier: null,

                    /**
                     * jqLite wrapped dom element.
                     *
                     * @external jqLiteObject
                     * @see {@link https://docs.angularjs.org/api/ng/function/angular.element|jqLiteObject}
                     */

                    /**
                     * Get the jqlite wrapped document object.
                     *
                     * @method _getDocument
                     * @return {jqLiteObject} Document wrapped in a jqList wrapper.
                     */
                    _getDocument: function _getDocument() {
                        return $document;
                    },

                    /**
                     * Get the document id from the markup.
                     *
                     * @method _getDocumentId
                     * @return {String} The unique id for the body element of the page.
                     */
                    _getDocumentId: function _getDocumentId() {
                        return this._getDocument().find("body").attr("id");
                    },

                    /**
                     * Builds the page identifier to be used for saving components
                     *
                     * @method  _buildPageIdentifier
                     * @private
                     * @return {Boolean|String} Returns a boolean value of false if it fails,
                     * otherwise it returns the identifier generated.
                     *
                     */
                    _buildPageIdentifier: function _buildPageIdentifier() {
                        if (this._pageIdentifier) {
                            return this._pageIdentifier;
                        }

                        if (!CJT.applicationName) {
                            throw new Error(LOCALE.maketext("The system could not generate a page identifier with the [asis,pageIdentiferService]. It also could not determine the “[asis,(cjt/core).applicationName]” for the running application."));
                        }

                        var bodyId = this._getDocumentId();
                        if (!bodyId) {
                            throw new Error(LOCALE.maketext("The system could not generate a page identifier with the [asis,pageIdentiferService]. You must specify the [asis,body.id]."));
                        }

                        if (CJT.applicationName && bodyId) {
                            this._pageIdentifier = "CSSS_" + CJT.applicationName + "_" + bodyId;
                        }

                        return this._pageIdentifier;
                    },

                    /**
                     * Get the page identifier for the current page.
                     *
                     * @method getPageIdentifier
                     * @return {String|Boolean}  Returns the identifier or false if it can not be generated
                     *                           for the page.
                     */
                    getPageIdentifier: function getPageIdentifier() {
                        if (this._pageIdentifier) {
                            return this._pageIdentifier;
                        }
                        return this._buildPageIdentifier();
                    }
                };
            }
        ]);
    }
);
