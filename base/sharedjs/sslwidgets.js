/* global LOCALE:false */
/* eslint camelcase: 0 */

(function(window) {
    "use strict";

    // -------------------------------------------------------------------------
    // Shortcuts
    // -------------------------------------------------------------------------
    var CPANEL = window.CPANEL;
    var DOM = window.DOM;
    var EVENT = window.EVENT;
    var YAHOO = window.YAHOO;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    var ONE_DAY = 1000 * 60 * 60 * 24;

    var DEFAULT_KEY_SIZE = CPANEL.ssl.DEFAULT_KEY_SIZE;

    var TOKEN_PLUS_THEME = location.pathname.match(/^\/.+?\/.+?\/[^/]+/)[0];

    /**
     * Checks if the notAfter date represents an expired certificate.
     * @param  {Date} notAfter Date from the noafter field from a certificate.
     * @return {Boolean}       true if expired, false is still valid.
     */
    function isCertificateExpired(notAfter) {
        return notAfter < Date.now();
    }

    /**
     * Checks if the noAfter date represets a certificate that is about
     * to expire. The expiration window is currently 30 day.
     * @param  {Date} notAfter Date from the noafter field from a certificate.
     * @return {Boolean}       true if the certificate will expire in 30 days
     *  or less; false otherwise.
     */
    function isCertificateNearlyExpired(notAfter) {
        return (notAfter.getTime() - Date.now()) < CPANEL.ssl.NEARLY_EXPIRED_WINDOW;
    }

    /**
     * Generates a human-readable string that describes a certificate’s key.
     *
     * @param  {CertificateParse} certParse The parse object.
     * @return {String} the description
     */
    function _generateKeyInfoString(certParse) {
        var header = certParse.getKeyTypeLabel();

        var detail = certParse.dispatchForKeyAlgorithm(
            function() {
                return certParse.modulus;
            },
            function() {
                return certParse.ecdsaPublic;
            }
        );

        return header + " (" + detail.substr(0, 8) + " …)";
    }

    /**
     * Display a certificate's salient features in a "container" DOM node.
     * It replaces the container's HTML with a table that shows the parse,
     * or empty string if the certText is not a valid certificate.
     *
     * NOTE: This requires ssl_certificate_parse.tmpl to be included.
     * It reads the "ssl_certificate_parse_template" element for the (Handlebars) template.
     *
     * @method showCertificateParse
     * @param {string} certText The certificate's PEM text content.
     * @param {string|DOM} container The container node, as an ID or a DOM node.
     * @param {Object} opts Options
     *     leading_rows: [ {key_html:"...", value_html:"..."}, ... ]
     *     is_apns: boolean, whether the cert is for APNS or not
     * @return {object|boolean} The parsed certificate, or boolean false if no parse.
     */
    function showCertificateParse(certText, container, opts) {

        var certParse;
        container = DOM.get(container);

        try {
            certParse = CPANEL.ssl.parseCertificateText(certText);
        } catch (e) {}

        if (certParse) {

            var keyinfo_html = _generateKeyInfoString(certParse);

            var expireTime = new Date(certParse.notAfter.getTime() + 1000);

            var expiration_html = LOCALE.datetime(expireTime, "datetime_format_medium");
            var templateEl = DOM.get("ssl_certificate_parse_template");

            var daysUntilExpiration = Math.floor((expireTime.getTime() - Date.now()) / ONE_DAY);
            var template = window.Handlebars.compile(templateEl.text);

            var is_expired = isCertificateExpired(certParse.notAfter);
            var is_too_short = certParse.modulusLength && (certParse.modulusLength < DEFAULT_KEY_SIZE);

            var about_to_expire = !is_expired && isCertificateNearlyExpired(certParse.notAfter);

            container.innerHTML = template({
                leading_rows: opts && opts.leading_rows,
                domains: certParse.domains,
                issuer: certParse.issuer.organizationName,
                keyinfo_html: keyinfo_html,
                expiration_html: expiration_html,
                isSelfSigned: certParse.isSelfSigned,
                days_to_expire: daysUntilExpiration,
                domains_error: certParse.domains.length === 0,
                issuer_warn: certParse.isSelfSigned,
                key_strength_critical: is_too_short,
                expiration_warn: about_to_expire,
                expiration_error: is_expired,
                expire_warn_msg: LOCALE.maketext("This certificate will expire in [quant,_1,day,days].", daysUntilExpiration),

                // for APNS
                is_apns: !!(opts && opts.is_apns),
                subject_userId: certParse.subject.userId
            });

            if (certParse.isSelfSigned) {
                EVENT.on(CPANEL.Y(container).one("a.self-signed-info"), "click", function() {
                    CPANEL.ajax.toggleToolTip(this, LOCALE.maketext("Self-Signed Certificates"));
                });
            }

            var the_link, link_warning;
            if (is_too_short) {
                the_link = CPANEL.Y(container).one("a.modulus-info");

                // Add information specific to this certificate to the message.
                // NOTE: The template already contains some default text here
                // as the_link.title.
                link_warning = LOCALE.maketext("This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.", certParse.modulusLength);

                link_warning += " " + LOCALE.maketext("The recommended key size for a certificate is currently [quant,_1,bit,bits].", DEFAULT_KEY_SIZE);

                if (certParse.isSelfSigned) {
                    link_warning += " " + LOCALE.maketext("You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.", certParse.domains.length, DEFAULT_KEY_SIZE);
                } else if (certParse.issuer && certParse.issuer.organizationName) {
                    link_warning += " " + LOCALE.maketext("Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.", certParse.issuer.organizationName, DEFAULT_KEY_SIZE); // no html_encode!
                } else {
                    link_warning += " " + LOCALE.maketext("Contact your certificate authority to reissue this certificate with a longer key.");
                }

                link_warning += "\n\n" + LOCALE.maketext("It is highly recommended that you do not install this certificate.");

                the_link.title = link_warning + "\n\n" + the_link.title;

                EVENT.on(the_link, "click", function(e) {
                    CPANEL.ajax.toggleToolTip(this, LOCALE.maketext("Certificate Key Sizes"));
                });
            }

            if (about_to_expire || is_expired) {
                the_link = CPANEL.Y(container).one("a.expiration-info");

                var cpmarket_can_sell_ssl = CPANEL.is_cpanel() && window.PAGE && window.PAGE.cpmarket_can_sell_ssl;

                // Add information specific to this certificate to the message.
                // NOTE: The template already contains some default text here
                // as the_link.title.
                var warning;
                if (certParse.isSelfSigned) {
                    warning = LOCALE.maketext("Generate and install a new self-signed certificate immediately. Then, replace this certificate with a certificate signed by a valid certificate authority as soon as possible.");
                } else if (cpmarket_can_sell_ssl) {

                    var url = TOKEN_PLUS_THEME + "/security/tls_wizard/";

                    the_link.textContent = LOCALE.maketext("Purchase a new certificate.");
                    the_link.href = url;
                } else if (certParse.issuer && certParse.issuer.organizationName) {
                    warning = LOCALE.maketext("You should request a replacement certificate from the issuer ([_1]) as soon as possible.", certParse.issuer.organizationName); // no html_encode!
                }

                var shouldUseTooltip = !!warning;

                if (shouldUseTooltip) {
                    the_link.title = warning + "\n\n" + the_link.title;

                    EVENT.on(the_link, "click", function() {
                        CPANEL.ajax.toggleToolTip(this, LOCALE.maketext("Certificate Expiration"));
                    });
                }
            }
        } else {
            container.innerHTML = "";
        }

        return certParse || false;
    }

    CPANEL.namespace("CPANEL.widgets.ssl");
    YAHOO.lang.augmentObject(CPANEL.widgets.ssl, {
        showCertificateParse: showCertificateParse
    });

})(window);
