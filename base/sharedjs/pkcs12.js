( function(window) {
    "use strict";

    var forge = window.forge;

    // ----------------------------------------------------------------------
    // - Requires forge
    //
    // - Errors are left untranslated for now. It’s fairly unlikely (?)
    //   that they’ll be needed in the wild anyway. (?)
    // ----------------------------------------------------------------------

    // Won’t throw if the failure is a bad password.
    function _pkcs12FromAsn1(forge_asn1) {
        var p12;
        try {
            p12 = forge.pkcs12.pkcs12FromAsn1.apply(forge.pkcs12, arguments);
        } catch (err) {
            if (!/password/.test(err.message)) {
                throw err;
            }
        }

        return p12;
    }

    window.CPANEL.pkcs12 = {

        // Abstracts the difference between no password and empty password
        pkcs12FromAsn1: function(forge_asn1, password) {
            var p12;

            // Necessary or else any multi-byte characters will fail decode.
            // Note that “vanilla-JS” can do unescape( encodeURIComponent(…) )
            // to achieve the same effect.
            password = forge.util.encodeUtf8(password);

            p12 = _pkcs12FromAsn1(forge_asn1, password);

            if (!p12 && (password === "")) {
                p12 = _pkcs12FromAsn1(forge_asn1);
            }

            return p12;
        },

        // Expects there to be exactly one private key.
        // Throws if none; warns if more.
        extractOnlyPrivateKeyPem: function _extractOnlyPrivateKeyPem(p12) {
            var kbags;

            // find() would be ideal here, but no IE version supports it. :-(
            ["keyBag", "pkcs8ShroudedKeyBag"].forEach( function(oid_idr) {
                if (!kbags) {
                    var bags = p12.getBags({ bagType: forge.pki.oids[oid_idr] });
                    bags = bags[forge.pki.oids[oid_idr]];

                    if (bags.length) {
                        kbags = bags;
                        return 1;
                    }
                }
            } );

            if (!kbags) {
                throw new Error("There should be at least 1 key!");
            } else if (kbags.length !== 1) {
                console.warn("Expected 1 key but found " + kbags.length);
            }

            var keyBag = kbags[0];
            var key = keyBag.key;
            return forge.pki.privateKeyToPem(key).trim();
        },

        // Expects there to be exactly one certificate.
        // Throws if none; warns if more.
        extractOnlyCertificatePem: function _extractOnlyCertificatePem(p12) {
            var certBags = p12.getBags({
                bagType: forge.pki.oids.certBag
            });

            var cbags = certBags[forge.pki.oids.certBag];

            if (cbags.length < 1) {
                throw new Error("There should be at least 1 certificate!");
            } else if (cbags.length !== 1) {
                console.warn("Expected 1 certificate but found " + cbags.length);
            }

            var certBag = cbags[0];
            var cert = certBag.cert;
            return forge.pki.certificateToPem(cert).trim();
        },
    };

} )(window);
