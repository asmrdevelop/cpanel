//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sslwidgets.js
// Generated: /usr/local/cpanel/base/sharedjs/sslwidgets-de.js
// Module:    legacy_shared/sslwidgets-de
// Locale:    de
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate Expiration":"Ablaufdatum des Zertifikats","Certificate Key Sizes":"Größen des Zertifikatsschlüssels","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.","Contact your certificate authority to reissue this certificate with a longer key.":"Wenden Sie sich an Ihre Zertifizierungsstelle, um das Zertifikat mit einem längeren Schlüssel auszustellen.","Generate and install a new self-signed certificate immediately. Then, replace this certificate with a certificate signed by a valid certificate authority as soon as possible.":"Generieren und installieren Sie umgehend ein neues selbstsigniertes Zertifikat. Ersetzen Sie dieses Zertifikat dann so schnell wie möglich durch ein von einer gültigen Zertifizierungsstelle signiertes Zertifikat.","It is highly recommended that you do not install this certificate.":"Es wird dringend davon abgeraten, dieses Zertifikat zu installieren.","Purchase a new certificate.":"Neues Zertifikat kaufen.","Self-Signed Certificates":"Selbstsignierte Zertifikate","The recommended key size for a certificate is currently [quant,_1,bit,bits].":"The recommended key size for a certificate is currently [quant,_1,bit,bits].","This certificate will expire in [quant,_1,day,days].":"This certificate will expire in [quant,_1,day,days].","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.","You should request a replacement certificate from the issuer ([_1]) as soon as possible.":"You should request a replacement certificate from the issuer ([_1]) as soon as possible."};

    if (!this.LEXICON) {
        this.LEXICON = {};
    }

    for(var item in newLex) {
        if(newLex.hasOwnProperty(item)) {
            var value = newLex[item];
            if (typeof(value) === "string" && value !== "") {
                // Only add it if there is a value.
                this.LEXICON[item] = value;
            }
        }
    }
})();
//~~END-GENERATED~~
