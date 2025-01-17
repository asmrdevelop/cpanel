/*
# mail/lists/lists.js                                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */
/* jshint -W098 */

(function(window) {
    "use strict";

    var LOCALE = window.LOCALE,
        CPANEL = window.CPANEL,
        YAHOO = window.YAHOO,
        DOM = YAHOO.util.Dom,
        EVENT = YAHOO.util.Event,
        PAGE = window.CPANEL.PAGE;

    var Handlebars = window.Handlebars;

    var privacy_opts_maker;

    var record_by_email = {};

    if (PAGE.lists && PAGE.lists.length) {
        for (var l = PAGE.lists.length - 1; l >= 0; l--) {
            record_by_email[PAGE.lists[l].list] = PAGE.lists[l];
        }
    }

    // NOTE: Keep this in sync with Cpanel::Mailman!
    var PRIVATE_PRIVACY_OPTIONS = {
        advertised: false,
        archive_private: true,
        subscribe_policy: ["3", "2"]
    };

    /*
     * Submit handler that triggers when the "Proceed" button is pressed on "Edit Privacy Options" dialog
     *
     * @method privacy_opts_popup
     * @param {String} type The event type
     * @param {Array} args
     * @param {Object} obj The object returned on callback
     */

    function _privacy_opts_submit_handler(type, args, obj) {
        var dialog = obj.dialog;

        var params = CPANEL.dom.get_data_from_form(
            dialog.form, {
                include_unchecked_checkboxes: 0 // represents these as a "0"
            }
        );

        params.list = obj.list;

        CPANEL.api({
            version: 3,
            module: "Email",
            func: "set_list_privacy_options",
            data: params,

            callback: CPANEL.ajax.build_page_callback(function() {
                obj.onSuccess.call();
                dialog.destroy();
            }, {
                on_error: dialog.destroy.bind(dialog)
            })
        });
    }

    /* Sets the values in the "Edit Privacy Options" dialog based on existing object that should mirror Cpanel::Mailman
     *
     * @method _set_private_values_in_form
     */

    function _set_private_values_in_form() {
        /* jshint validthis: true */
        var clicked_el = this;

        var form = DOM.getAncestorByTagName(clicked_el, "form");
        var form_data = CPANEL.dom.get_data_from_form(form);

        for (var key in PRIVATE_PRIVACY_OPTIONS) {
            if (form[key].type === "checkbox") {
                form[key].checked = PRIVATE_PRIVACY_OPTIONS[key];
            } else {
                var acceptable = PRIVATE_PRIVACY_OPTIONS[key];
                if (!YAHOO.lang.isArray(acceptable)) {
                    acceptable = [acceptable];
                }

                if (acceptable.indexOf(form_data[key]) === -1) {
                    CPANEL.dom.set_form_el_value(form[key], acceptable[0]);
                }
            }
        }

        _update_access_type_text_in_form("private");
    }


    /*
     * Update the displayed access type in the access type dialog box.
     *
     * @method _update_access_type_text_in_form
     * @param {String} new_type The access type to translate and display.
     */

    function _update_access_type_text_in_form(new_type) {
        DOM.get("form_access_type").innerHTML = PAGE.translated_access_type[new_type];
    }


    /*
     * Re-evaluate and update the displayed access type in the access type dialog box.
     *
     * @method _reevaluate_access_type_in_form
     * @param {Event | null} evt The event that triggered this call. (unused)
     * @param {DOM} the_form The form DOM node to evaluate for public/private-setting.
     */

    function _reevaluate_access_type_in_form(evt, the_form) {
        var type = "private";
        var to_compare;

        var form_data = CPANEL.dom.get_data_from_form(the_form);

        for (var key in PRIVATE_PRIVACY_OPTIONS) {
            if (PRIVATE_PRIVACY_OPTIONS.hasOwnProperty(key)) {
                if (the_form[key].type === "checkbox") {
                    to_compare = !!form_data[key];
                } else {
                    to_compare = form_data[key];
                }

                var acceptable_for_private = PRIVATE_PRIVACY_OPTIONS[key];
                if (YAHOO.lang.isArray(acceptable_for_private)) {
                    if (acceptable_for_private.indexOf(to_compare) === -1) {
                        type = "public";
                    }
                } else if (to_compare !== acceptable_for_private) {
                    type = "public";
                }

                if (type === "public") {
                    break;
                }
            }
        }

        _update_access_type_text_in_form(type);
    }


    /*
     * Same as _reevaluate_access_type_in_form(), but with a slight delay
     * so that this can be used on reset() event listeners.
     *
     * @method _delayed_reevaluate_access_type_in_form
     * @param {Event | null} evt The event that triggered this call. (unused)
     * @param {DOM} the_form The form DOM node to evaluate for public/private-setting.
     */

    function _delayed_reevaluate_access_type_in_form(evt, the_form) {
        setTimeout(
            function() {
                _reevaluate_access_type_in_form(evt, the_form);
            },
            1
        );
    }

    /*
     * Show the popup of privacy options in the mailing list UI.
     *
     * @method privacy_opts_popup
     * @param {Object} list The list record.
     * @param {DOM} clicked_obj The DOM node that received the "click" that opens this popup.
     */

    function privacy_opts_popup(list, clicked_obj, successFunction) {

        if (!privacy_opts_maker) {
            privacy_opts_maker = Handlebars.compile(DOM.get("change_list_privacy_template").text.trim());
        }

        var dialog = new CPANEL.ajax.Common_Dialog(null, {
            close: true,
            show_status: true,
            status_html: LOCALE.maketext("Saving …")
        });

        dialog.setHeader(CPANEL.widgets.Dialog.applyDialogHeader(
            LOCALE.maketext("Edit Privacy Options: “[_1]”", list.list.html_encode())
        ));

        var list_record = list;
        var subscribe_policy = String(list_record.subscribe_policy);

        dialog.form.innerHTML = privacy_opts_maker({
            advertised: String(list_record.advertised) === "1",

            archive_private: String(list_record.archive_private) === "1",

            subscribe_policy_is_1: subscribe_policy === "1",
            subscribe_policy_is_2: subscribe_policy === "2",
            subscribe_policy_is_3: subscribe_policy === "3"
        });

        dialog.submitEvent.subscribe(
            _privacy_opts_submit_handler, {
                list: list.list.html_encode(),
                dialog: dialog,
                onSuccess: successFunction
            }
        );

        dialog.show_from_source(clicked_obj);

        _reevaluate_access_type_in_form(null, dialog.form);

        EVENT.on(dialog.form, "change", _reevaluate_access_type_in_form, dialog.form);
        EVENT.on(dialog.form, "reset", _delayed_reevaluate_access_type_in_form, dialog.form);

        var private_values_el = CPANEL.Y(dialog.form).one(".set-private-values");
        EVENT.on(private_values_el, "click", _set_private_values_in_form);
    }

    YAHOO.lang.augmentObject(window, {
        privacy_opts_popup: privacy_opts_popup
    });

    if (PAGE.notice) {
        PAGE.noticeHandle = new CPANEL.widgets.Page_Notice(PAGE.notice);
    }
}(window));

define(
    [
        "angular",
        "cjt/modules"
    ],
    function(angular) {
        "use strict";

        angular.module("App", ["ui.bootstrap", "cjt2.cpanel"]);

        /*
         * this looks funky, but these require that
         * angular be loaded before they can be loaded
         * so the nested requires become relevant
         */
        var app = require(
            [
                "cjt/directives/toggleSortDirective",
                "cjt/directives/spinnerDirective",
                "cjt/directives/searchDirective",
                "cjt/directives/pageSizeDirective",
                "app/services/mailingListsService",
                "app/controllers/mailingListsController",
                "app/controllers/mainController",
                "uiBootstrap"
            ],
            function() {

                var app = angular.module("App");

                /*
                 * filter used to escape emails and urls
                 * using native js escape
                 */
                app.filter("escape", function() {
                    return window.escape;
                });

                /* PrivacyWindowController */

                /*
                 * Creates a new PrivacyWindowController
                 * @class PrivacyWindowController
                 *
                 * serves as a controller to connect to the privacy window pop_up
                 *
                 */
                function PrivacyWindowController(mailingListsService) {
                    var _self = this;

                    /*
                     * @method closed
                     * callback on close of the popup
                     *
                     */
                    PrivacyWindowController.prototype.closed = function() {
                        mailingListsService.getLists();
                    };

                    /*
                     * @method open
                     * opens the popup
                     *
                     * @param list {object} lists item
                     * @param target {string} id of dom js target
                     *
                     */
                    PrivacyWindowController.prototype.open = function(list, target) {
                        window.privacy_opts_popup(list, target.currentTarget, _self.closed);
                    };
                }

                PrivacyWindowController.$inject = ["mailingListsService"];
                app.controller("PrivacyWindowController", PrivacyWindowController);

                /*
                 * because of the race condition with the dom loading and angular loading
                 * before the establishment of the app
                 * a manual initiation is required
                 * and the ng-app is left out of the dom
                 */
                app.init = function() {
                    var appContent = angular.element("#content");

                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        angular.bootstrap(appContent[0], ["App"]);
                    }

                    return app;
                };

                app.init();
            });

        return app;
    }
);
