//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/config.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/config-es.js
// Module:    /templates/greylist/views/config-es
// Locale:    es
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The number of minutes during which the mail server accepts a resent email from an unknown triplet.":"La cantidad de minutos durante los que el servidor de correo acepta un correo electrónico reenviado de un triplo desconocido.","The number of minutes during which the mail server defers email from an unknown triplet.":"La cantidad de minutos durante los que el servidor de correo aplaza el correo electrónico de un triplo desconocido.","The system successfully saved your [asis,Greylisting] configuration settings.":"El sistema guardó correctamente los valores de configuración [asis,Greylisting].","The time at which the mail server treats a resent email as coming from a new, unknown triplet.":"La hora en que el servidor de correo trata un correo electrónico reenviado como proveniente de un triplo nuevo y desconocido.","Whether the system automatically accepts email from hosts with a valid [asis,SPF] record.[comment,this text is used in a tooltip]":"Si el sistema acepta automáticamente el correo electrónico de los anfitriones con un registro válido [asis,SPF].[comment,this text is used in a tooltip]"};

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
