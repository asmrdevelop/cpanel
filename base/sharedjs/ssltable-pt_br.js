//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/ssltable.js
// Generated: /usr/local/cpanel/base/sharedjs/ssltable-pt_br.js
// Module:    legacy_shared/ssltable-pt_br
// Locale:    pt_br
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate ID:":"ID do Certificado:","Contact your Certificate Authority ([_1]) to request a certificate renewal.":"Entre em contato com sua Autoridade de Certificação ([_1]) para solicitar uma renovação de certificado.","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"Entre em contato com a autoridade de certificação ([_1]) para emitir novamente este certificado com uma chave de [numf,_2] bit(s).","Purchase a replacement certificate in the “[_1]”.":"Compre um certificado de substituição no “[_1]”.","SSL/TLS Wizard":"Assistente SSL/TLS","This certificate has expired.":"Este certificado expirou.","This certificate will expire in [quant,_1,day,days].":"Este certificado vai expirar em [quant,_1,dia,dias].","This certificate will expire later today.":"Este certificado irá expirar ainda hoje.","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"A chave deste certificado é muito curta ([quant,_1,bit,bits]). Essa chave não protegerá contra um ataque de falsificação.","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"Você deve gerar outro certificado autoassinado para [quant,_1,este domínio,estes domínios] com uma chave de [numf,_2] bits.","unknown":"desconhecido"};

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
