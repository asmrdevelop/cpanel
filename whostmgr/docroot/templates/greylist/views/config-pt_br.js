//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/config.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/config-pt_br.js
// Module:    /templates/greylist/views/config-pt_br
// Locale:    pt_br
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The number of minutes during which the mail server accepts a resent email from an unknown triplet.":"O número de minutos durante os quais o servidor de correio aceita um e-mail reenviado de um trio desconhecido.","The number of minutes during which the mail server defers email from an unknown triplet.":"O número de minutos durante os quais o servidor de e-mail adia o e-mail de um trio desconhecido.","The system successfully saved your [asis,Greylisting] configuration settings.":"O sistema salvou com sucesso suas definições de configuração de [asis,Greylisting].","The time at which the mail server treats a resent email as coming from a new, unknown triplet.":"A hora em que o servidor de e-mail trata um e-mail reenviado como proveniente de um trio novo e desconhecido.","Whether the system automatically accepts email from hosts with a valid [asis,SPF] record.[comment,this text is used in a tooltip]":"Se o sistema aceita automaticamente e-mails de hosts com um registro [asis,SPF] válido.[comment,this text is used in a tooltip]"};

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
