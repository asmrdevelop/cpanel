//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/cpanel_customization/constants.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/cpanel_customization/constants-id.js
// Module:    /templates/cpanel_customization/constants-id
// Locale:    id
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Colors":"Warna","Favicon":"Favicon","Links":"Tautan","Logos":"Logo","Public Contact":"Kontak Publik"};

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