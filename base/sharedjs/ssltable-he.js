//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/ssltable.js
// Generated: /usr/local/cpanel/base/sharedjs/ssltable-he.js
// Module:    legacy_shared/ssltable-he
// Locale:    he
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate ID:":"מזהה אישור:","Contact your Certificate Authority ([_1]) to request a certificate renewal.":"פנה לרשות האישורים שלך ([_1]) כדי לבקש חידוש של אישור.","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"פנה לרשות האישורים שלך ([_1]) כדי להנפיק מחדש אישור זה עם מפתח של [numf,_2] סיביות.","Purchase a replacement certificate in the “[_1]”.":"Purchase a replacement certificate in the “[_1]”.","SSL/TLS Wizard":"SSL/TLS Wizard","This certificate has expired.":"התוקף של אישור זה פג.","This certificate will expire in [quant,_1,day,days].":"התוקף של אישור זה יפוג בעוד [quant,_1,יום ,ימים].","This certificate will expire later today.":"התוקף של אישור זה יפוג בהמשך היום.","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"המפתח של אישור זה קצר מדי ([quant,_1,סיבית ,סיביות]). מפתח זה לא יגן מפני התקפות זיוף.","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"יש להפיק אישור נוסף בחתימה עצמית עבור [quant,_1,תחום זה,תחומים אלה] עם מפתח של [numf,_2] סיביות.","unknown":"לא ידוע"};

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
