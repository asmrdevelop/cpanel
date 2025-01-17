//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sslwidgets.js
// Generated: /usr/local/cpanel/base/sharedjs/sslwidgets-uk.js
// Module:    legacy_shared/sslwidgets-uk
// Locale:    uk
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate Expiration":"Термін дії сертифіката","Certificate Key Sizes":"Розміри ключа сертифіката","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"Зв’яжіться з центром сертифікації ([_1]) для повторної видачі сертифіката з [numf,_2]-розрядним ключем.","Contact your certificate authority to reissue this certificate with a longer key.":"Зв’яжіться з центром сертифікації для повторної видачі сертифіката з довшим ключем.","Generate and install a new self-signed certificate immediately. Then, replace this certificate with a certificate signed by a valid certificate authority as soon as possible.":"Негайно створіть та інсталюйте новий самопідписаний сертифікат. Потім якнайшвидше замініть цей сертифікат на інший, підписаний припустимим центром сертифікації.","It is highly recommended that you do not install this certificate.":"Настійно рекомендується не встановлювати цей сертифікат.","Purchase a new certificate.":"Purchase a new certificate.","Self-Signed Certificates":"Самопідписані сертифікати","The recommended key size for a certificate is currently [quant,_1,bit,bits].":"Рекомендований розмір ключа для сертифіката наразі складає [quant,_1,біт,біт].","This certificate will expire in [quant,_1,day,days].":"Термін дії цього сертифіката спливає через [quant,_1,день,дн.].","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"Ключ цього сертифіката закороткий ([quant,_1,біт,біт]). Цей ключ не захищатиме від спуфінг-атак.","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"Вам слід створити інший самопідписаний сертифікат для [quant,_1,цього домену,цих доменів] з [numf,_2]-розрядним ключем.","You should request a replacement certificate from the issuer ([_1]) as soon as possible.":"Вам слід якнайшвидше запросити новий сертифікат у постачальника ([_1])."};

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
