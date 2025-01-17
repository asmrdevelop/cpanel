//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/config.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/config-da.js
// Module:    /templates/greylist/views/config-da
// Locale:    da
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The number of minutes during which the mail server accepts a resent email from an unknown triplet.":"Det antal minutter, hvor mailserveren accepterer en gensendt mail fra en ukendt triplet.","The number of minutes during which the mail server defers email from an unknown triplet.":"Det antal minutter, hvor mailserveren udskyder mail fra en ukendt triplet.","The system successfully saved your [asis,Greylisting] configuration settings.":"Systemet har gemt dine [asis,Greylisting]-konfigurationsindstillinger.","The time at which the mail server treats a resent email as coming from a new, unknown triplet.":"Det tidspunkt, hvor mailserveren behandler en gensendt mail, som om den kommer fra en ny, ukendt triplet.","Whether the system automatically accepts email from hosts with a valid [asis,SPF] record.[comment,this text is used in a tooltip]":"Om systemet automatisk accepterer mail fra værter med en gyldig [asis,SPF]-post.[comment,this text is used in a tooltip]"};

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
