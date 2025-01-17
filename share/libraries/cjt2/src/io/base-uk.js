//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/share/libraries/cjt2/src/io/base.js
// Generated: /usr/local/cpanel/share/libraries/cjt2/src/io/base-uk.js
// Module:    cjt/io/base-uk
// Locale:    uk
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"An unknown error occurred.":"Сталася невідома помилка.","No specific error was returned with the failed API call.":"Під час невдалого виклику API не вдалося визначити помилку.","The API response could not be parsed.":"Відповідь API не вдалося проаналізувати."};

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
