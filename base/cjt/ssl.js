// NOTE: This module requires Lapo Luchini's ASN.1 decoder library.
// It does NOT wrap calls to that library in try/catch; be sure to
// trap errors yourself if you use this module.
//
// IE <8 will require a JSON compatibility shim.
// IE <10 also requires an atob() compatibility shim.

/* eslint camelcase: 0 */

(function ssl_js(window) {
    "use strict";

    var atob = window.atob;
    var ASN1 = window.ASN1;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    var ONE_DAY = 1000 * 60 * 60 * 24;
    var NEARLY_EXPIRED_WINDOW = 30 * ONE_DAY;

    var toLowerCase = Function.prototype.call.bind(String.prototype.toLowerCase);

    // TODO: Get these from the backend at build time
    // rather than hard-coding them here.
    var DEFAULT_KEY_SIZE = 2048;

    var ECDSA_CURVES = {
        "1.2.840.10045.3.1.7": "prime256v1",
        "1.3.132.0.34": "secp384r1"
    };

    // Accommodates RSA and ECDSA keys.
    var KEY_TEXT_REGEXP = /^[^-]*(-+\s*BEGIN\s+(?:EC\s+|RSA\s+)?PRIVATE\s+KEY\s*-+[^-]*-+\s*END\s+(?:EC\s+|RSA\s+)?PRIVATE\s+KEY\s*-+)[^-]*$/;

    var CERTIFICATE_TEXT_REGEXP = /^[^-]*(-+\s*BEGIN\s+CERTIFICATE\s*-+[^-]*-+\s*END\s+CERTIFICATE\s*-+)[^-]*$/;

    var X509_EXTENSION_OID = {
        "netscape-cert-type": "2.16.840.1.113730.1",
        keyUsage: "2.5.29.15",
        subjectAltName: "2.5.29.17",
        basicConstraints: "2.5.29.19"
    };

    var OID_NAME = {
        "1.2.840.113549.1.1.5": "sha1WithRSAEncryption",
        "1.2.840.113549.1.9.1": "emailAddress",
        "2.5.4.3": "commonName",
        "2.5.4.5": "serialNumber",
        "2.5.4.6": "countryName",
        "2.5.4.7": "localityName",
        "2.5.4.8": "stateOrProvinceName",
        "2.5.4.9": "streetAddress",
        "2.5.4.10": "organizationName",
        "2.5.4.11": "organizationalUnitName",

        // For APNS certificates
        "0.9.2342.19200300.100.1.1": "userId",
    };

    Object.assign( OID_NAME, ECDSA_CURVES );

    Object.keys(X509_EXTENSION_OID).forEach( function(name) {
        OID_NAME[X509_EXTENSION_OID[name]] = name;
    } );

    var rsaEncryption_OID = "1.2.840.113549.1.1.1";
    var id_ecPublicKey_OID = "1.2.840.10045.2.1";

    // cf. RFC 2459, 4.1.2.5.1
    // year, month, mday, hour, minute, second
    var TIME_REGEXP = /^([0-9]*)([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})Z$/;

    var X509V3_ORDER = ["version", "serial", null, "issuer", "dates", "subject", "key"];

    // Unsure what the first element should be, but it seems always to be 0.
    var RSA_ORDER = [null, "modulus", "publicExponent", "privateExponent", "prime1", "prime2", "exponent1", "exponent2", "coefficient"];

    var keyUsage_order = ["digitalSignature", "contentCommitment", "keyEncipherment", "dataEncipherment", "keyAgreement", "keyCertSign", "cRLSign", "encipherOnly", "decipherOnly"];

    /**
     * Extract the raw content octets from an ASN1 object.
     *
     * @method _getContentOctets
     * @param {ASN1} asn1 The ASN1 object to parse.
     * @return {array} The octets, as number primitives.
     */
    var _getContentOctets = function(asn1) {
        return asn1.stream.enc.slice(asn1.posContent(), asn1.posEnd());
    };

    /**
     * Extract the raw binary content from an ASN1 object.
     *
     * @method _getBinary
     * @param {ASN1} asn1 The ASN1 object to parse.
     * @return {string} The binary content, as a byte string.
     */
    var _getBinary = function(asn1) {
        return String.fromCharCode.apply(String, _getContentOctets(asn1));
    };

    /**
     * Extract the raw binary content from an ASN1 object and return hex.
     *
     * @method _getHex
     * @param {ASN1} asn1 The ASN1 object to parse.
     * @return {string} The binary content, as lower-case hex.
     */
    var _getHex = function(asn1) {
        var octets = _getContentOctets(asn1);
        var hex = [];
        for (var o = octets.length - 1; o >= 0; o--) {
            var octet = octets[o];

            // Ensure that each octet uses two hex digits.
            hex[o] = (octet < 16 ? "0" : "") + octet.toString(16);
        }
        return hex.join("").toLowerCase().replace(/^00/, "");
    };

    /**
     * Parse a certificate or CSR subject into an array.
     *
     * @method _parseSubject
     * @param {ASN1} asn1 The ASN1 object to parse.
     * @return {array} The return list: [ [ key,  value ], .. ]
     */
    var _parseSubject = function(asn1) {
        var attrs = [];
        var sub = asn1.sub;
        for (var s = sub.length - 1; s >= 0; s--) {
            var sequence_sub = sub[s].sub[0].sub;
            var label = sequence_sub[0].content();
            if (label in OID_NAME) {
                label = OID_NAME[label];
            }
            attrs.unshift([label, sequence_sub[1].content()]);
        }

        return attrs;
    };

    /**
     * Turn a [ [ key, value], .. ] array into a single object.
     *
     * @method _unrollKeyValueList
     * @param {array} theArray The array-of-arrays to unroll.
     * @return {object} The return object: { key: value, key2: value2, .. }
     */
    var _unrollKeyValueList = function(theArray) {
        var attrs = {};
        var len = theArray.length;
        for (var l = 0; l < len; l++) {
            attrs[theArray[l][0]] = theArray[l][1];
        }

        return attrs;
    };

    /**
     * Do an ASN1.decode() on an octet array, but strip leading 0 first.
     * This is useful for decoding ASN.1 structures that are embedded
     * within other ASN.1 structures.
     *
     * @method _asn1DecodeOctets
     * @param {array} theArray The array of octets to decode.
     * @return {ASN1} The parsed ASN1 object
     */
    var _asn1DecodeOctets = function(octets) {
        if (octets[0] === 0) {
            octets.shift();
        }

        return ASN1.decode(octets);
    };

    /**
     * Extract the base64 from a text string and ASN1-decode it.
     *
     * @method _startParse
     * @param {string} text The text of whatever we are decoding
     * @return {ASN1} The decoded ASN1 object
     */
    var _startParse = function(text) {
        var b64 = text.replace(/-[^\n]+-/g, "").replace(/\s+/g, "");

        if (b64.length % 4) {
            throw new Error("Invalid base64: must be a multiple of 4 in length.");
        }

        // Node.js's Buffer object would be ideal here, but
        // browser atob works.
        var binary = atob(b64);
        var stream = [];
        for (var c = binary.length - 1; c >= 0; c--) {
            stream[c] = binary.charCodeAt(c);
        }

        var decode = ASN1.decode(stream);

        // Before we return the parse, ensure that its length matches what
        // the ASN.1 scaffolding says it should be.
        var second_byte = binary.charCodeAt(1);
        var should_be_length;
        if (second_byte > 0x80) {
            var size_octets_length = second_byte - 0x80;
            var size_octets = binary.substr(2, size_octets_length).split("");
            should_be_length = 2 + size_octets_length + size_octets.reduce(function(a, b) {
                return a * 256 + b.charCodeAt(0);
            }, 0);
        } else {
            should_be_length = 2 + second_byte;
        }

        if (should_be_length !== binary.length) {
            throw new Error("ASN.1 data length mismatch: expected " + should_be_length + ", got " + binary.length);
        }

        return decode;
    };

    /**
     * Figure how many bits a hex string takes up.
     *
     * @method _hexBinaryLength
     * @param {string} hex The hex string
     * @return {number} The number of bits in the hex string
     */
    var _hexBinaryLength = function(hex) {
        hex = hex.replace(/^0+/, "");
        return 4 * (hex.length - 1) + parseInt(hex.charAt(0), 16).toString(2).length;
    };

    /**
     * Extract the RSA key components from an ASN1 object.
     *
     * @method _parseRSA
     * @param {ASN1} asn1 The ASN1 representation of the key.
     * @return {object} The key components.
     */
    var _parseRSA = function(asn) {
        var parsed = {};
        for (var i = RSA_ORDER.length - 1; i >= 0; i--) {
            var part = RSA_ORDER[i];
            if (part) {
                parsed[part] = _getHex(asn.sub[i]);
            }
        }

        parsed.keyAlgorithm = "rsaEncryption";

        // Convenience
        parsed.modulusLength = _hexBinaryLength(parsed.modulus);

        return parsed;
    };

    function _parseECDSAPublic(asn) {

        // Normalize to compressed since we might receive a compressed or
        // uncompressed key, and it’s MUCH easier to derive the compressed
        // form from the uncompressed than vice-versa. (See CPAN’s Crypt::Perl
        // for an implementation of the “decompression” if you’re curious.)
        var hex = _compressECDSAPublic( _getHex(asn) );

        // Sanity check.
        if ( !/^0[23]/.test(hex) ) {
            throw new Error("Unrecognized public point encoding: the leading non-null byte is “_”.".replace(/_/, hex.substr(0, 2)));
        }

        return hex;
    }

    function _compressECDSAPublic(pubHex) {

        // Might as well support hybrid keys (06/07), just in case.
        if ( /^0[467]/.test(pubHex) ) {
            var x = pubHex.substr(2);
            if (x.length % 4) {
                throw ( "Public hex (_) should be even … ?".replace(/_/, pubHex) );
            }

            var leading_octet = ( parseInt(pubHex.substr(-1), 16) % 2 ) ? "03" : "02";

            return leading_octet + x.substr( 0, x.length / 2 );
        }

        return pubHex; // already compressed … ?
    }

    function _getCurveName(curveOID) {
        if ( OID_NAME[curveOID] ) {
            return OID_NAME[curveOID];
        }

        throw new Error("Unknown ECDSA curve OID: “_”".replace(/_/, curveOID));
    }

    function _packageECDSAParse(curveName, pubASN1) {
        return {
            keyAlgorithm: "id-ecPublicKey",
            ecdsaCurveName: curveName,
            ecdsaPublic: _parseECDSAPublic(pubASN1)
        };
    }

    function _checkECDSAVersion(asn) {
        var version = asn.sub[0].content();
        if ( version !== 1 ) {
            throw new Error("Unsupported ECDSA version: “_”".replace(/_/, version));
        }
    }

    /**
     * Parse an RSA or ECDSA private key (algorithm-specific or PKCS8 format)
     *
     * @method parseKeyText
     * @param {string} text The key as a string
     * @return {object} A data structure representing the key's data.
     */
    var _cachedKeyParses = {};

    function parseKeyText(text) {
        if (!(text in _cachedKeyParses)) {
            if (!KEY_TEXT_REGEXP.test(text)) {
                throw new Error("The key text was not valid.");
            }

            var decoded = _startParse(text);

            var curveOID, curveName, pubPart;

            // RSA's special key file format, e.g., "openssl genrsa"
            if (/BEGIN RSA/.test(text)) {
                _cachedKeyParses[text] = _parseRSA(decoded);
            } else if (/BEGIN EC /.test(text)) {
                _checkECDSAVersion(decoded);

                curveOID = decoded.sub[2].sub[0].content();
                curveName = _getCurveName(curveOID);

                pubPart = decoded.sub[3].sub[0];

                _cachedKeyParses[text] = _packageECDSAParse( curveName, pubPart );
            } else {

                // Generic PKCS8 key file format
                // e.g., "openssl genpkey"
                var format = decoded.sub[1].sub[0].content();

                if (format === rsaEncryption_OID) {
                    var subRSA = _asn1DecodeOctets(_getContentOctets(decoded.sub[2]));
                    _cachedKeyParses[text] = _parseRSA(subRSA);
                } else if (format === id_ecPublicKey_OID) {

                    // PKCS8 for ECDSA puts the curve name in the PKCS8
                    // part, not with the rest of the key. So we can’t just
                    // parse the “meat” of the PKCS8 encoding as we could
                    // above with _parseRSA().
                    curveOID = decoded.sub[1].sub[1].content();
                    curveName = _getCurveName(curveOID);

                    var subECDSA = _asn1DecodeOctets(_getContentOctets(decoded.sub[2]));
                    _checkECDSAVersion(subECDSA);
                    pubPart = subECDSA.sub[2].sub[0];

                    return _packageECDSAParse( curveName, pubPart );
                } else {
                    _throwUnknownKeyOID(format);
                }
            }
        }
        return JSON.parse(JSON.stringify(_cachedKeyParses[text]));
    }

    function _throwUnknownKeyOID(format) {
        throw new Error("Unknown key algorithm OID: “_”".replace(/_/, format));
    }

    /**
     * Parse an SSL certificate's time as described in RFC 2459, 4.1.2.5.1
     *
     * @method parseTime
     * @param {string} text The string, either in UTCTime or GeneralizedTime.
     * @return {date} A JavaScript Date object.
     */

    function parseTime(text) {
        var match = TIME_REGEXP.exec(text);
        if (!match) {
            return;
        }
        if (match[1].length === 2) { // cf. RFC 2459, 4.1.2.5.1
            match[1] = ((match[1] <= 50) ? "20" : "19") + match[1];
        }

        var date = new Date(Date.UTC(
            match[1],
            Number(match[2]) - 1,
            match[3],
            match[4],
            match[5],
            match[6]
        ));

        return date;
    }

    function _parseSubjectKey(keyASN1) {
        var algOID = keyASN1.sub[0].sub[0].content();
        if ( algOID === rsaEncryption_OID ) {
            var modulusSubStructureOctets = _getContentOctets(keyASN1.sub[1]);
            var modulus = _getHex(_asn1DecodeOctets(modulusSubStructureOctets).sub[0]);
            return {
                keyAlgorithm: "rsaEncryption",
                modulus: modulus,
                modulusLength: _hexBinaryLength(modulus)    // convenience
            };
        } else if ( algOID === id_ecPublicKey_OID ) {
            var curveOID = keyASN1.sub[0].sub[1].content();
            var curveName = _getCurveName(curveOID);
            var pubPart = keyASN1.sub[1];

            return {
                keyAlgorithm: "id-ecPublicKey",
                ecdsaCurveName: curveName,
                ecdsaPublic: _compressECDSAPublic( _getHex(pubPart) )
            };
        }

        _throwUnknownKeyOID(algOID);
    }

    var ecdsaCurveNickname = {
        prime256v1: "P-256",
        secp384r1: "P-384",
    };

    function _ecdsaCurveDisplayName(curveName) {
        return ecdsaCurveNickname[curveName] + "/" + curveName;
    }

    // Contents are as returned by parseCertificateText().
    //
    // This class is more or less “designed” for its internal properties
    // to be accessed directly because parseCertificateText() historically
    // returned a plain object, and we want compatibility with that.
    //
    function CertificateParse(source) {
        Object.assign(this, source);
    }

    Object.assign(
        CertificateParse.prototype,
        {
            dispatchForKeyAlgorithm: function dispatchForKeyAlgorithm(onRsa, onEcdsa) {
                switch (this.keyAlgorithm) {
                    case "rsaEncryption":
                        return onRsa.bind(this)();
                    case "id-ecPublicKey":
                        return onEcdsa.bind(this)();
                }

                throw ("Bad key algorithm: " + this.keyAlgorithm);
            },

            getKeyType: function getKeyType() {
                return this.dispatchForKeyAlgorithm(
                    function() {
                        return "rsa-" + this.modulusLength;
                    },
                    function() {
                        return "ecdsa-" + this.ecdsaCurveName;
                    }
                );
            },

            getKeyTypeLabel: function getKeyLabel() {
                return this.dispatchForKeyAlgorithm(
                    function() {
                        return "RSA, " + LOCALE.maketext("[numf,_1]-bit", this.modulusLength);
                    },
                    function() {
                        return "ECDSA, " + _ecdsaCurveDisplayName(this.ecdsaCurveName);
                    }
                );
            },
        }
    );

    /**
     * Parse an x509 SSL certificate
     *
     * @method parseCertificateText
     * @param {string} text The SSL certificate as a string
     * @return {CertificateParse} A data structure representing the SSL certificate's data.
     */
    var _cachedCertificateParses = {};

    function parseCertificateText(text) {
        if (!(text in _cachedCertificateParses)) {
            if (!CERTIFICATE_TEXT_REGEXP.test(text)) {
                throw new Error("The certificate text was not valid.");
            }

            var decoded = _startParse(text).sub[0];

            var order = X509V3_ORDER.slice(0);

            var version;
            try {
                version = _getContentOctets(decoded.sub[0].sub[0])[0];
            } catch (e) {
                version = 0;
                order.shift();
            }

            var parsed_extensions;

            var componentIndex = {};
            for (var o = order.length; o >= 0; o--) {
                componentIndex[order[o]] = o;
            }

            var keyASN1 = decoded.sub[componentIndex.key];
            var subjectKeyParse = _parseSubjectKey(keyASN1);

            var subjectList = _parseSubject(decoded.sub[componentIndex.subject]);
            var issuerList = _parseSubject(decoded.sub[componentIndex.issuer]);

            var extensions = (version > 0) ? decoded.sub[decoded.sub.length - 1] : undefined;
            extensions = extensions && extensions.sub[0];

            if (extensions) {
                var extensions_count = extensions.sub.length;

                parsed_extensions = {};

                EXTENSION: for (var e = 0; e < extensions_count; e++) {
                    var curExt = extensions.sub[e];

                    var oid = curExt.sub && curExt.sub[0] && curExt.sub[0].content();
                    var name = oid && OID_NAME[oid];

                    // Ignore extensions that we don't know about.
                    if (!name) {
                        continue EXTENSION;
                    }

                    var payload_node = curExt.sub.slice(-1)[0];
                    var ext_value = _asn1DecodeOctets(_getContentOctets(payload_node));

                    switch (name) {
                        case "subjectAltName":
                            var san_values = [];

                            // Some SAN values are objects. There seems to be no value
                            // for us to parse these since CAs always seem to duplicate
                            // the object SAN values as plain values.
                            for (var s = 0; s < ext_value.sub.length; s++) {
                                var value = ext_value.sub[s];
                                if (value.sub) {
                                    try {
                                        san_values.push({
                                            oid: value.sub[0].content(),
                                            value: _getBinary(value.sub[1].sub[0])
                                        });
                                    } catch (err) {
                                        if (window.console && console.warn) {
                                            console.warn("Unparsable subjectAltName entry in certificate: ");
                                            console.warn(value, err);
                                        }
                                    }
                                } else {
                                    san_values.push(_getBinary(ext_value.sub[s]));
                                }
                            }

                            ext_value = san_values;

                            break; // because we don't check for any other extensions

                        case "basicConstraints":
                            ext_value = {
                                cA: ext_value.sub[0] && (_getBinary(ext_value.sub[0]) !== "0"),
                                pathLenConstraint: ext_value.sub[1] && ext_value.sub[1].content()
                            };

                            break;

                        case "keyUsage":
                            var ones_zeros = ext_value.content().match(/[01]+$/)[0];

                            ext_value = {};

                            for (var b = 0; b < ones_zeros.length; b++) {
                                if (ones_zeros.charAt(ones_zeros.length - 1 - b) === "1") {
                                    ext_value[keyUsage_order[b]] = true;
                                }
                            }
                            break;

                            // TODO: Is this needed?
                        case "netscape-cert-type":
                            continue EXTENSION;
                    }

                    var is_critical = false;
                    if (curExt.sub.length > 2) {
                        var critical_node = curExt.sub[1];
                        is_critical = (critical_node.tag === 1) && (critical_node.content() === "true");
                    }

                    parsed_extensions[name] = {
                        critical: is_critical,
                        value: ext_value
                    };
                }
            }

            var subject = _unrollKeyValueList(subjectList);

            var subjectAltName = parsed_extensions && parsed_extensions.subjectAltName && parsed_extensions.subjectAltName.value || [];

            // per RFC 2818, subject.commonName is deprecated; as a result,
            // some CAs are issuing single-domain certs with the domain in
            // both the subject commonName and subjectAltName.
            var domains;
            if (subject.commonName && subjectAltName.indexOf(subject.commonName) === -1) {
                domains = [subject.commonName].concat(subjectAltName);
            } else {
                domains = subjectAltName.slice(0);
            }

            domains = domains.filter( function(d) {
                return typeof d !== "object";
            } );

            // Add to this return object as needed.
            var the_parse = {

                // Certs store version as 0-indexed, but publicly they're 1-indexed.
                version: 1 + version,
                notBefore: _getBinary(decoded.sub[componentIndex.dates].sub[0]),
                notAfter: _getBinary(decoded.sub[componentIndex.dates].sub[1]),
                issuer: _unrollKeyValueList(issuerList),
                subject: subject,
                subjectList: subjectList,
                issuerList: issuerList,
                extensions: parsed_extensions,

                // Convenience
                domains: domains,
                isSelfSigned: (_getBinary(decoded.sub[componentIndex.subject]) === _getBinary(decoded.sub[componentIndex.issuer]))
            };

            Object.assign( the_parse, subjectKeyParse );

            the_parse = new CertificateParse(the_parse);

            _cachedCertificateParses[text] = the_parse;
        }
        var clone = JSON.parse(JSON.stringify(_cachedCertificateParses[text]));
        clone.notBefore = parseTime(clone.notBefore);
        clone.notAfter = parseTime(clone.notAfter);

        return new CertificateParse(clone);
    }

    /**
     * Returns an ordered list of certificate parses, with the leaf node first,
     * as is consistent with the TLS protocol.
     *
     * To facilitate reassembly of the CA bundle, each certificate parse has a "text"
     * property added.
     *
     * No caching here because the certificate parses are already cached.
     *
     * @method parseCABundleText
     * @param {string} text The CA bundle text.
     * @return {array} An ordered list of parsed certificates, each with a "text" property added.
     */

    function parseCABundleText(text) {
        var certs = text.match(/(-+BEGIN[^\n]+-+\s+[a-zA-Z0-9\/+=\s]+\s+-+END[^\n]+-+)/g);
        if (!certs || !certs.length) {
            return;
        }

        var parses = certs.map(function(c) {
            var parsed = parseCertificateText(c);
            parsed.text = c;
            return parsed;
        });

        var cab_chain = [];
        if (certs.length === 1) {
            cab_chain.push(parses[0]);
        } else {
            var subjectLookup = {};
            var issuers = [];
            var chain = {};
            var cur, subject, issuer;
            while (parses.length) {
                cur = parses.shift();
                subject = JSON.stringify(cur.subjectList);
                issuer = JSON.stringify(cur.issuerList);

                subjectLookup[subject] = cur;
                issuers.push(issuer);
                if (subject !== issuer) {
                    chain[subject] = cur;
                }
            }

            // Delete every cert from "chain" that was issued by something else
            // in the bundle. The remaining node will be the leaf node.
            while (issuers.length) {
                delete chain[issuers.shift()];
            }

            var chainKeys = Object.keys(chain);
            if (chainKeys.length !== 1) {
                throw new Error("The certificates do not form a chain.");
            }

            var leafSubject = chainKeys[0];

            cur = subjectLookup[leafSubject];
            while (cur) {
                subject = JSON.stringify(cur.subjectList);
                issuer = JSON.stringify(cur.issuerList);
                cab_chain.push(cur);

                if (subject === issuer) {
                    break;
                }

                cur = subjectLookup[issuer];
            }
        }

        // The root cert in a CA bundle SHOULD have both flags, but just in
        // case there are "weird" situations out there, allow either/or.
        var root_exts_ok;
        try {
            root_exts_ok = cab_chain[0].extensions.keyUsage.value.keyCertSign;
            root_exts_ok = root_exts_ok || cab_chain[0].extensions.basicConstraints.value.cA;
        } catch (e) {}

        if (!_check_ca(cab_chain[0])) {
            throw new Error("Root node is not a CA cert.");
        }

        return cab_chain;
    }

    // cf. openssl/crypto/x509v3/v3_purp.c
    // NOTE: Ensure parity between this and Cpanel::SSL::Objects::Certificate.

    function _check_ca(cert) {
        var exts = cert.extensions;

        if (exts) {
            if (exts.basicConstraints) {
                return exts.basicConstraints.value.cA ? 1 : 0;
            } else if (exts.keyUsage) {
                return exts.keyUsage.value.keyCertSign ? 4 : 0;
            }
        } else if (cert.isSelfSigned && (cert.version === 1)) {
            return 3;
        }

        return 0;
    }

    /**
     * Determine if an x509 SSL certificate will support the given domain.
     *
     * @method validateCertificateForDomain
     * @param {string} text The SSL certificate as a string
     * @param {string} domain The domain to match against the given certificate.
     * @return {boolean} A boolean value indicating if the certificate supports the given domain.
     */

    function validateCertificateForDomain(text, domain) {
        var parsed = parseCertificateText(text);

        return doesDomainMatchOneOf(domain, parsed.domains);
    }

    /**
     * Lower-case only the 7-bit ASCII portions of a string.
     *
     * @method _to_dns_lower_case
     * @param {string} domain The domain to lower-case per DNS.
     * @return {string} The ASCII-lower-cased string
     */

    function _ascii_lower_case(domain) {
        return domain.replace(
            /([A-Z]+)/g,
            toLowerCase
        );
    }

    /**
     * Determine if a domain or wildcard domain matches an item in a list of domains.
     *
     * @method doesDomainMatchOneOf
     * @param {string} domain The domain/wildcard to match against the given list of domains.
     * @param {array} domains The list against which to match the given domain.
     * @return {boolean} A boolean value indicating if the domain matches an item in the list of domains.
     */

    function doesDomainMatchOneOf(domain, domains) {
        if (domains === null || domain === null) {
            return false;
        }

        // This only does ASCII because that’s the most common use case.
        // TODO: Implement case-folding to match how DNS does it.
        // (.toLowerCase() may be all we need...?)
        domain = _ascii_lower_case(domain);
        domains = domains.map(_ascii_lower_case);

        var domains_count = domains.length;

        for (var i = 0; i < domains_count; i++) {
            if (!domains[i]) {
                continue;
            }

            if (domains[i] === domain) {
                return true;
            } else {
                var domain_1 = domains[i];
                var domain_2 = domain;
                var possible_wildcard;
                var domain_to_match;

                if (/^\*/.test(domain_1)) {
                    possible_wildcard = domain_1;
                    domain_to_match = domain_2;
                } else if (/^\*/.test(domain_2)) {
                    possible_wildcard = domain_2;
                    domain_to_match = domain_1;
                } else {
                    continue;
                }

                possible_wildcard = possible_wildcard.replace(/^\*\./, "");
                domain_to_match = domain_to_match.replace(/^[^\.]+\./, "");

                if (possible_wildcard === domain_to_match) {
                    return true;
                }
            }
        }

        return false;
    }

    // This duplicates logic from Cpanel::Crypt::ECDSA::Data.
    function ecdsaEquivalentRSAModulusLength(curveName) {
        switch (curveName) {
            case "prime256v1":
                return 2529;

            case "secp384r1":
                return 6692;

            default:
                throw ( "Bad curve name: " + curveName );
        }
    }

    var ssl = {
        DEFAULT_KEY_SIZE: DEFAULT_KEY_SIZE,
        NEARLY_EXPIRED_WINDOW: NEARLY_EXPIRED_WINDOW,

        parseTime: parseTime,
        parseKeyText: parseKeyText,
        parseCertificateText: parseCertificateText,
        parseCABundleText: parseCABundleText,
        validateCertificateForDomain: validateCertificateForDomain,
        doesDomainMatchOneOf: doesDomainMatchOneOf,

        ecdsaEquivalentRSAModulusLength: ecdsaEquivalentRSAModulusLength,
    };

    if (typeof window.CPANEL !== "undefined") {
        window.CPANEL.namespace("CPANEL.ssl");
        window.YAHOO.lang.augmentObject(window.CPANEL.ssl, ssl);
    }

    return ssl;
})(window);
