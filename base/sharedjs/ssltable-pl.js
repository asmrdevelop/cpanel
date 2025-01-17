//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/ssltable.js
// Generated: /usr/local/cpanel/base/sharedjs/ssltable-pl.js
// Module:    legacy_shared/ssltable-pl
// Locale:    pl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate ID:":"Identyfikator certyfikatu:","Contact your Certificate Authority ([_1]) to request a certificate renewal.":"Skontaktuj się ze swoim urzędem certyfikacji ([_1]), aby złożyć wniosek o odnowienie certyfikatu.","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"Skontaktuj się ze swoim urzędem certyfikacji ([_1]), aby wystawił certyfikat z kluczem [numf,_2]-bitowym.","Purchase a replacement certificate in the “[_1]”.":"Purchase a replacement certificate in the “[_1]”.","SSL/TLS Wizard":"SSL/TLS Wizard","This certificate has expired.":"Ten certyfikat wygasł.","This certificate will expire in [quant,_1,day,days].":"Ten certyfikat wygaśnie za [quant,_1,dzień,dni].","This certificate will expire later today.":"Ten certyfikat wygaśnie później w dniu dzisiejszym.","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"Ten klucz certyfikatu jest za krótki ([quant,_1,bit,bity(-ów)]). Nie będzie on chronił przed atakami polegającymi na podszywaniu się pod inną tożsamość.","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"Należy wygenerować dla [quant,_1,tej domeny,tych domen] kolejny certyfikat z podpisem własnym, tym razem z kluczem [numf,_2]-bitowym.","unknown":"nieznane"};

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
