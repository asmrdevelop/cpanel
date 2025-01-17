//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/mod_security/directives/ruleVendorUrlValidator.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/mod_security/directives/ruleVendorUrlValidator-pl.js
// Module:    /templates/mod_security/directives/ruleVendorUrlValidator-pl
// Locale:    pl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The URL must contain a protocol, domain, and file name in the correct format. (Example: [asis,https://example.com/example/meta_example.yaml])":"Adres URL musi zawierać protokół, domenę i nazwę pliku w prawidłowym formacie. (Przykład: [asis,https://example.com/example/meta_example.yaml])","The URL must use one of the following recognized protocols: [join,~, ,_1]":"Adres URL musi korzystać z jednego z następujących rozpoznawanych protokołów:[join,~, ,_1]","The file name must have the .yaml extension. (Example: [asis,meta_example.yaml])":"Nazwa pliku musi zawierać rozszerzenie .yaml. (Przykład: [asis,meta_example.yaml])","The file name must start with meta_, followed by the vendor name and have the .yaml extension. (Example: [asis,meta_example.yaml])":"Nazwa pliku musi zaczynać się prefiksem meta_, po którym następują: nazwa dostawcy i rozszerzenie .yaml. (Przykład: [asis,meta_example.yaml])","The file name must use the meta_ prefix, followed by the vendor name and a .yaml extension. The vendor name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])":"Nazwa pliku musi składać się z prefiksu meta_ oraz nazwy dostawcy i rozszerzenia .yaml. Nazwa dostawcy może zawierać znaki tylko z następującego zestawu: [join,~, ,_1] (np. [asis,meta_example.yaml])","The file name must use the meta_ prefix. (Example: [asis,meta_example.yaml])":"Nazwa pliku musi zawierać prefiks meta_. (Przykład: [asis,meta_example.yaml])","The protocol should be followed by a colon and two forward slashes. (Example: [asis,https://])":"Po identyfikatorze protokołu powinien znajdować się dwukropek, a po nim dwa ukośniki („/”). (Przykład: [asis,https://])","The vendor name part of the file name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])":"Część nazwy pliku będąca nazwą dostawcy może zawierać znaki tylko z następującego zestawu: [join,~, ,_1] (np. [asis,meta_example.yaml])"};

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
