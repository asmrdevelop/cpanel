//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/share/libraries/cjt2/src/io/base.js
// Generated: /usr/local/cpanel/share/libraries/cjt2/src/io/base-tr.js
// Module:    cjt/io/base-tr
// Locale:    tr
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"An unknown error occurred.":"Bilinmeyen bir hata oluştu.","No specific error was returned with the failed API call.":"Başarısız API çağırmadan belirli hiçbir hata döndürülmedi.","The API response could not be parsed.":"API yanıtı ayrıştırılamadı."};

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