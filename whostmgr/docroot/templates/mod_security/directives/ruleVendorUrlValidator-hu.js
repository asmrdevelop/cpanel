//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/mod_security/directives/ruleVendorUrlValidator.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/mod_security/directives/ruleVendorUrlValidator-hu.js
// Module:    /templates/mod_security/directives/ruleVendorUrlValidator-hu
// Locale:    hu
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The URL must contain a protocol, domain, and file name in the correct format. (Example: [asis,https://example.com/example/meta_example.yaml])":"A helyes formátumú URL-címnek egy protokollt, egy tartományt és egy fájlnevet kell tartalmaznia. (Példa: [asis,https://example.com/example/meta_example.yaml])","The URL must use one of the following recognized protocols: [join,~, ,_1]":"Az URL-címnek az alábbi ismert protokollok egyikét kell megadnia: [join,~, ,_1]","The file name must have the .yaml extension. (Example: [asis,meta_example.yaml])":"A fájlnévnek .yaml kiterjesztést kell tartalmaznia. (Példa: [asis,meta_example.yaml])","The file name must start with meta_, followed by the vendor name and have the .yaml extension. (Example: [asis,meta_example.yaml])":"A fájlnévnek a meta_ előtagból, a szállító nevéből és a .yaml kiterjesztésből kell állnia. (Példa: [asis,meta_example.yaml])","The file name must use the meta_ prefix, followed by the vendor name and a .yaml extension. The vendor name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])":"A fájlnévnek a meta_ előtagból, a szállító nevéből és a .yaml kiterjesztésből kell állnia. A szállító neve csak a következő halmaz karaktereit tartalmazhatja: [join,~, ,_1] (Példa: [asis,meta_example.yaml])","The file name must use the meta_ prefix. (Example: [asis,meta_example.yaml])":"A fájlnévnek a meta_ előtaggal kell kezdődnie. (Példa: [asis,meta_example.yaml])","The protocol should be followed by a colon and two forward slashes. (Example: [asis,https://])":"A protokolljelzést egy kettőspontnak és két perjelnek kell követnie. (Példa: [asis,https://])","The vendor name part of the file name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])":"A fájlnév szállítónév része csak a következő halmazban előforduló karaktereket tartalmazhatja: [join,~, ,_1] (Példa: [asis,meta_example.yaml])"};

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