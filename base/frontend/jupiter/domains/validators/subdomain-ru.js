//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/frontend/jupiter/domains/validators/subdomain.js
// Generated: /usr/local/cpanel/base/frontend/jupiter/domains/validators/subdomain-ru.js
// Module:    /jupiter/domains/validators/subdomain-ru
// Locale:    ru
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The server reserves this subdomain for system use only. Enter a different subdomain.":"Этот субдомен зарезервирован на сервере только для системного использования. Введите другой субдомен.","You must enter a valid subdomain.":"Необходимо ввести действительный субдомен."};

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
