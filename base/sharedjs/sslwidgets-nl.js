//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sslwidgets.js
// Generated: /usr/local/cpanel/base/sharedjs/sslwidgets-nl.js
// Module:    legacy_shared/sslwidgets-nl
// Locale:    nl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate Expiration":"Verloop certificaat","Certificate Key Sizes":"Groottes van certificaatsleutels","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"Neem contact op met uw certificeringsinstantie ([_1]) om dit certificaat opnieuw te verlenen met een [numf,_2]-bits sleutel.","Contact your certificate authority to reissue this certificate with a longer key.":"Neem contact op met uw certificeringsinstantie om dit certificaat opnieuw te verlenen met een langere sleutel.","Generate and install a new self-signed certificate immediately. Then, replace this certificate with a certificate signed by a valid certificate authority as soon as possible.":"Genereer en installeer direct een nieuw zelfondertekend certificaat. Vervang dit certificaat vervolgens zo snel mogelijk door een certificaat dat is ondertekend door een geldige certificeringsinstantie.","It is highly recommended that you do not install this certificate.":"Het wordt ten zeerste afgeraden dit certificaat te installeren.","Purchase a new certificate.":"Purchase a new certificate.","Self-Signed Certificates":"Zelfondertekende certificaten","The recommended key size for a certificate is currently [quant,_1,bit,bits].":"De aanbevolen sleutelgrootte voor een certificaat is momenteel [quant,_1,bit,bits].","This certificate will expire in [quant,_1,day,days].":"Dit certificaat verloopt over [quant,_1,dag,dagen].","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"Deze certificaatsleutel is te kort ([quant,_1,bit,bits]). Deze sleutel biedt geen bescherming tegen een spoofing-aanval.","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"U moet nog een zelfondertekend certificaat voor [quant,_1,dit domein,deze domeinen] genereren met een [numf,_2]-bits sleutel.","You should request a replacement certificate from the issuer ([_1]) as soon as possible.":"U moet zo snel mogelijk een vervangend certificaat aanvragen bij de uitgever ([_1])."};

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
