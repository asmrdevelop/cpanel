/*
# cjt/jquery/plugins/rangeSelection.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "jquery"
    ],
    function($) {

        /**
         * Simple jquery plugin to select a range in a textbox
         *
         * @method  selectRange
         * @param  {Number} start
         * @param  {Number} end
         * @return {JqueryNodeWrapper}
         */
        $.fn.selectRange = function(start, end) {
            if (!end) {
                end = start;
            }
            return this.each(function() {
                if (this.setSelectionRange) {
                    this.focus();
                    this.setSelectionRange(start, end);
                } else if (this.createTextRange) {
                    var range = this.createTextRange();
                    range.collapse(true);
                    range.moveEnd("character", end);
                    range.moveStart("character", start);
                    range.select();
                }
            });
        };
    }
);
