/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including icons.js!");
} else {

    /**
    The icons module contains properties that reference icons for our product.
    @module icons
*/

    /**
    The icons class contains properties that reference icons for our product.
    @class icons
    @namespace CPANEL
    @extends CPANEL
*/
    CPANEL.icons = {

        /** /cPanel_magic_revision_XXXXX/ is used to allow caching of images -- XXXXX needs to be incremented when the image changes **/

        /**
        Error icon located at cjt/images/icons/error.png
        @property error
        @type string
    */
        error: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/error.png" width="16" height="16" alt="error" />',
        error_src: "/cPanel_magic_revision_0/cjt/images/icons/error.png",
        error24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/error24.png" width="24" height="24" alt="error" />',
        error24_src: "/cPanel_magic_revision_0/cjt/images/icons/error24.png",

        /**
        success icon located at cjt/images/icons/success.png
        @property success
        @type string
    */
        success: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/success.png" alt="success" width="16" height="16" />',
        success_src: "/cPanel_magic_revision_0/cjt/images/icons/success.png",
        success24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/success24.png" alt="success" width="24" height="24" />',
        success24_src: "/cPanel_magic_revision_0/cjt/images/icons/success24.png",

        /**
        unknown icon located at cjt/images/icons/unknown.png
        @property unknown
        @type string
    */
        unknown: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/unknown.png" alt="unknown" width="16" height="16" />',
        unknown_src: "/cPanel_magic_revision_0/cjt/images/icons/unknown.png",
        unknown24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/unknown24.png" alt="unknown" width="24" height="24" />',
        unknown24_src: "/cPanel_magic_revision_0/cjt/images/icons/unknown24.png",

        /**
        warning icon located at cjt/images/icons/warning.png
        @property warning
        @type string
    */
        warning: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/warning.png" alt="warning" width="16" height="16"/>',
        warning_src: "/cPanel_magic_revision_0/cjt/images/icons/warning.png",
        warning24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/warning24.png" alt="warning" width="24" height="24"/>',
        warning24_src: "/cPanel_magic_revision_0/cjt/images/icons/warning24.png",

        /**
        AJAX loading icon located at cjt/images/ajax-loader.gif
        @property ajax
        @type string
    */
        ajax: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/loading.gif" alt="loading" />',
        ajax_src: "/cPanel_magic_revision_0/cjt/images/loading.gif",

        // /cjt/images/1px_transparent.gif
        transparent: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/1px_transparent.gif" alt="" width="1" height="1"/>',
        transparent_src: "/cPanel_magic_revision_0/cjt/images/1px_transparent.gif",

        // /cjt/images/rejected.png
        rejected: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/rejected.png" alt="rejected" width="16" height="16"/>',
        rejected_src: "/cPanel_magic_revision_0/cjt/images/rejected.png",
        rejected24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/rejected24.png" alt="rejected" width="24" height="24"/>',
        rejected24_src: "/cPanel_magic_revision_0/cjt/images/rejected24.png",

        // /base/yui/container/assets/info16_1.gif
        info: '<img align="absmiddle" src="/cPanel_magic_revision_0/yui/container/assets/info16_1.gif" alt="" width="16" height="16"/>',
        info_src: "/cPanel_magic_revision_0/yui/container/assets/info16_1.gif",

        // /cjt/images/filtered.png
        filtered: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/filter.png" alt="" width="16" height="16"/>',
        filtered_src: "/cPanel_magic_revision_0/cjt/images/filtered.png",
        filtered24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/filter24.png" alt="" width="24" height="24"/>',
        filtered24_src: "/cPanel_magic_revision_0/cjt/images/filtered24.png",

        // /cjt/images/archive.png
        archive: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/archive.png" alt="" width="16" height="16"/>',
        archive_src: "/cPanel_magic_revision_0/cjt/images/archive.png",
        archive24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/archive24.png" alt="" width="24" height="24"/>',
        archive24_src: "/cPanel_magic_revision_0/cjt/images/archive24.png"

    }; // end icons object
} // end else statement
