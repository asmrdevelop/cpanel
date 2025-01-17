//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/ssltable.js
// Generated: /usr/local/cpanel/base/sharedjs/ssltable-tr.js
// Module:    legacy_shared/ssltable-tr
// Locale:    tr
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate ID:":"Sertifika Kimliği:","Contact your Certificate Authority ([_1]) to request a certificate renewal.":"Bir sertifikayı yenileme isteğinde bulunmak için Belgelendirme Kuruluşunuzla ([_1]) bağlantıya geçin.","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"Bu sertifikayı [numf,_2] bitlik bir anahtarla yeniden yayınlamak için sertifika kuruluşunuzla ([_1]) bağlantıya geçin.","Purchase a replacement certificate in the “[_1]”.":"Purchase a replacement certificate in the “[_1]”.","SSL/TLS Wizard":"SSL/TLS Wizard","This certificate has expired.":"Bu sertifikanın süresi dolmuş.","This certificate will expire in [quant,_1,day,days].":"Bu sertifika [quant,_1,gün,gün] içinde sona erecek.","This certificate will expire later today.":"Bu sertifika bugün içinde sona erecek.","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"Bu sertifikanın anahtarı çok kısa ([quant,_1,bit,bit]). Bu anahtar bir sahtekarlık saldırısına karşı korumayacaktır.","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"[quant,_1,bu etki alanı,bu etki alanları] için [numf,_2] bitlik anahtarı olan başka bir kendinden imzalı sertifika üretmelisiniz.","unknown":"bilinmiyor"};

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
