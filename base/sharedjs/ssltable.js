/* global LOCALE:false */
/* eslint camelcase: 0 */

/*
A set of utilities common to tables of SSL cert installs.

REQUIRES:
    sslwidgets.js (and accompanying template)
    yui2_datatable_row_expansion.js

NOTE: This might do well in sslwidgets.js, but a table almost seems like a
"mega-widget" that deserves its own namespace.

Also, a lot of this stuff could be more generally useful beyond just tables
of SSL information.
*/
(function(window) {
    "use strict";

    var CPANEL = window.CPANEL;
    var DOM    = window.DOM;
    var Handlebars = window.Handlebars;

    var content_with_warning_maker = Handlebars.compile(DOM.get("content_with_warning_template").text);

    var DEFAULT_KEY_SIZE = CPANEL.ssl.DEFAULT_KEY_SIZE;

    /**
    * Show a cert parse, with the cert's ID (if given) as the first table row.
    *
    * @param opts {Object}
    *   id - the certificate ID (optional)
    *   text - the certificate text
    *   container - the container node (ID, or DOM node)
    */
    function _showCertParseWithId(opts, extra_parse_args) {
        var show_opts = opts.id && {
            leading_rows: [
                {
                    key_html: LOCALE.maketext("Certificate ID:"),
                    value_html: opts.id
                }
            ]
        };

        if (extra_parse_args) {
            if (!show_opts) {
                show_opts = {};
            }

            for (var key in extra_parse_args) {
                show_opts[key] = extra_parse_args[key];
            }
        }

        CPANEL.widgets.ssl.showCertificateParse(
            opts.text,
            opts.container,
            show_opts
        );
    }

    CPANEL.namespace( "CPANEL.widgets.ssltable" );
    YAHOO.lang.augmentObject( CPANEL.widgets.ssltable, {

        listTemplate: window.Handlebars.compile( DOM.get("list_template").text),

        /**
        * Sorter for arrays of (single-line) strings.
        *
        * @param a {Array} The first sort item
        * @param b {Array} The second sort item
        * @return {Number} -1, 0, or 1
        */
        sorterStringArray: function(a, b) {
            return a.join("\n") < b.join("\n") ? -1 : ( a.join("\n") > b.join("\n") ? 1 : 0 );
        },

        /**
        * Sorter for key types, as given by CertificateParse’s getKeyType().
        *
        * @param a {Array} The first sort item
        * @param b {Array} The second sort item
        * @return {Number} -1, 0, or 1
        */
        sorterKeyType: function(a, b) {
            var aRsa, bRsa;

            // For speed, this assumes that anything not ECDSA is RSA.

            if (0 === a.lastIndexOf("ecdsa-", 0)) {
                aRsa = CPANEL.ssl.ecdsaEquivalentRSAModulusLength(a.substring(6));
            } else {
                aRsa = parseInt(a.substring(4), 10);
            }

            if (0 === b.lastIndexOf("ecdsa-", 0)) {
                bRsa = CPANEL.ssl.ecdsaEquivalentRSAModulusLength(b.substring(6));
            } else {
                bRsa = parseInt(b.substring(4), 10);
            }

            return aRsa < bRsa ? -1 : aRsa > bRsa ? 1 : 0;
        },

        /**
        * Parser for YUI 2 DataSource to receive unix timestamps as dates.
        *
        * @param {String|Number} oData String or number representation of a unix timestamp.
        * @return {Date} A JavaScript Date object from the passed-in parameter.
        */
        parseUnixDate: function(oData) {
            if ( oData instanceof Date ) {
                return oData;
            }

            return new Date( 1000 * oData );
        },

        /**
        * YUI 2 DataTable formatter for certificate "notAfter".
        * NOTE: This formats as "expiration", which is 1 second AFTER "notAfter".
        *
        * @param elCell {HTMLElement} DOM object for the cell.
        * @param oRecord {YAHOO.widget.Record} Record for this row.
        * @param oColumn {YAHOO.widget.Column} Column definition for this cell.
        * @param oData {Object} Data for the specific cell.
        */
        formatCertificateExpiration: function(elCell, oRecord, oColumn, oData) {
            if (!oData) {
                return;
            }

            var expiration = new Date( oData.getTime() + 1000 );
            if ( isNaN( expiration.getTime() ) ) {
                return false;
            }
            var warning, expired_class;
            var now = new Date();

            var time_left = expiration - now.getTime();
            if (time_left < 0) {
                expired_class = "error";
                warning = LOCALE.maketext("This certificate has expired.");
            } else if (time_left < CPANEL.ssl.NEARLY_EXPIRED_WINDOW) {
                expired_class = "warning";

                var days = Math.ceil( time_left / 24 / 60 / 60 / 1000 );

                if ( (now.getDate() === expiration.getDate()) && (now.getMonth() === expiration.getMonth()) ) {
                    warning = LOCALE.maketext("This certificate will expire later today.");
                } else {
                    warning = LOCALE.maketext("This certificate will expire in [quant,_1,day,days].", days);
                }
            }

            var cert_parse, useLinkYN;

            if (warning) {
                cert_parse = CPANEL.ssl.parseCertificateText( oRecord.getData("certificate_text") );
                if (!cert_parse.isSelfSigned) {
                    var cpmarket_can_sell_ssl = CPANEL.is_cpanel() && window.PAGE && window.PAGE.cpmarket_can_sell_ssl;

                    warning += " ";

                    if (cpmarket_can_sell_ssl) {
                        var notAfter = new Date( cert_parse.notAfter );
                        notAfter.setSeconds( notAfter.getSeconds() + 1 );

                        useLinkYN = true;

                        warning += LOCALE.maketext("Purchase a replacement certificate in the “[_1]”.", LOCALE.maketext("SSL/TLS Wizard"));
                    } else {
                        warning += LOCALE.maketext("Contact your Certificate Authority ([_1]) to request a certificate renewal.", cert_parse.issuer.organizationName || LOCALE.maketext("unknown"));
                    }
                }
            }

            var warningHtml = content_with_warning_maker( {
                content_html: LOCALE.datetime( expiration, "date_format_short" ),
                warning_class: expired_class,
                warning_html: warning
            } );

            if (useLinkYN) {
                var TOKEN_PLUS_THEME = location.pathname.match(/^\/.+?\/.+?\/[^/]+/)[0];

                var link = document.createElement("a");
                link.href = TOKEN_PLUS_THEME + "/security/tls_wizard/";
                link.innerHTML = warningHtml;

                elCell.appendChild(link);
                elCell.title = warning;
            } else {
                elCell.innerHTML = warningHtml;
                elCell.title = LOCALE.datetime( expiration, "datetime_format_long" );
            }
        },

        formatCertificateKeyType: function(el, rec, col, value) {
            var cert_text = rec.getData("certificate_text");
            var cert_parse = CPANEL.ssl.parseCertificateText(cert_text);

            var label = cert_parse.getKeyTypeLabel();

            cert_parse.dispatchForKeyAlgorithm(
                function() {
                    var modlen = cert_parse.modulusLength;

                    if (!parseInt(modlen, 10)) {
                        return;
                    }

                    var warning, warning_class;

                    if ( modlen < DEFAULT_KEY_SIZE ) {
                        warning_class = "error";
                        warning = LOCALE.maketext("This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.", modlen);
                    }

                    if (warning) {
                        warning += " ";

                        if (cert_parse.is_self_signed) {
                            warning += LOCALE.maketext("You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.", cert_parse.domains.length, DEFAULT_KEY_SIZE);
                        } else {
                            warning += LOCALE.maketext("Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.", cert_parse.issuer.organizationName.html_encode(), DEFAULT_KEY_SIZE);
                        }
                    }

                    el.innerHTML = content_with_warning_maker( {
                        content_html: label,
                        warning_class: warning_class,
                        warning_html: warning
                    } );
                },
                function() {
                    el.textContent = label;
                }
            );
        },

        /**
        * Inject an SSL certificate parse into the table row expansion.
        *
        * @param args {Object} The element that rowExpansionTemplate receives
        * @param extra_parse_args {Object} Additional args to pass to the parser
        */
        detailsExpand: function(args, extra_parse_args) {
            _showCertParseWithId(
                {
                    text: args.data.getData("certificate_text"),
                    container: args.liner_element,
                    id: args.data.getData("certificate_id")
                },
                extra_parse_args
            );

            CPANEL.align_panels_event.fire();
        },

        /**
        * Call load() on a datatable, then sync its displayed sort with its state.
        * This is useful for tables that load LocalDataSource instances.
        *
        * @param table {DataTable} The DataTable instance
        * @param loadArgs {Object} The object to pass to the table's load() method
        */
        loadTableAndSort: function( table, loadArgs ) {

            // Restoring sorting has to be done in a callback because
            // the render from load() below happens asynchronously. Otherwise,
            // the _attach_table_click_listeners call on postRenderEvent will hit
            // the same DOM elements twice, making each click fire two listeners.
            var sorted_by = table.get("sortedBy");
            if (sorted_by) {
                var col = table.getColumn( sorted_by.key );
                var sorter = function() {
                    table.unsubscribe("postRenderEvent", sorter);
                    table.sortColumn( col, sorted_by.dir );

                    CPANEL.align_panels_event.fire();
                };
                table.subscribe("postRenderEvent", sorter);
            }

            table.load( loadArgs );
        }
    } );

} )(window);
