//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/mod_security/vendors.cmb.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/mod_security/vendors.cmb-pl.js
// Module:    /templates/mod_security/vendors.cmb-pl
// Locale:    pl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Add Vendor":"Dodaj dostawcę","An error occurred in the attempt to retrieve the vendor information.":"Przy próbie pobrania informacji o dostawcy wystąpił błąd.","Manage Vendors":"Zarządzaj dostawcami","Select Vendor Rule Sets":"Wybierz zbiory reguł dostawców","The URL must contain a protocol, domain, and file name in the correct format. (Example: [asis,https://example.com/example/meta_example.yaml])":"Adres URL musi zawierać protokół, domenę i nazwę pliku w prawidłowym formacie. (Przykład: [asis,https://example.com/example/meta_example.yaml])","The URL must use one of the following recognized protocols: [join,~, ,_1]":"Adres URL musi korzystać z jednego z następujących rozpoznawanych protokołów:[join,~, ,_1]","The file name must have the .yaml extension. (Example: [asis,meta_example.yaml])":"Nazwa pliku musi zawierać rozszerzenie .yaml. (Przykład: [asis,meta_example.yaml])","The file name must start with meta_, followed by the vendor name and have the .yaml extension. (Example: [asis,meta_example.yaml])":"Nazwa pliku musi zaczynać się prefiksem meta_, po którym następują: nazwa dostawcy i rozszerzenie .yaml. (Przykład: [asis,meta_example.yaml])","The file name must use the meta_ prefix, followed by the vendor name and a .yaml extension. The vendor name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])":"Nazwa pliku musi składać się z prefiksu meta_ oraz nazwy dostawcy i rozszerzenia .yaml. Nazwa dostawcy może zawierać znaki tylko z następującego zestawu: [join,~, ,_1] (np. [asis,meta_example.yaml])","The file name must use the meta_ prefix. (Example: [asis,meta_example.yaml])":"Nazwa pliku musi zawierać prefiks meta_. (Przykład: [asis,meta_example.yaml])","The protocol should be followed by a colon and two forward slashes. (Example: [asis,https://])":"Po identyfikatorze protokołu powinien znajdować się dwukropek, a po nim dwa ukośniki („/”). (Przykład: [asis,https://])","The system could not disable the configuration files.":"System nie mógł wyłączyć plików konfiguracji.","The system could not enable the configuration files.":"System nie mógł włączyć plików konfiguracji.","The system could not find the specified [asis,vendor_id].":"System nie mógł znaleźć podanego [asis,vendor_id].","The system experienced the following error when it attempted to install the “[_1]” vendor: [_2]":"W systemie wystąpił następujący błąd przy próbie zainstalowania dostawcy „[_1]”: [_2]","The system experienced the following error when it attempted to remove the vendor [_1]: [_2]":"W systemie wystąpił następujący błąd przy próbie usunięcia dostawcy [_1]: [_2]","The system failed to pass the ID query string parameter.":"System nie przekazał parametru ciągu zapytania o identyfikator.","The vendor name part of the file name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])":"Część nazwy pliku będąca nazwą dostawcy może zawierać znaki tylko z następującego zestawu: [join,~, ,_1] (np. [asis,meta_example.yaml])","You have multiple vendors with the same [asis,vendor_id].":"Występuje wielu dostawców, którzy mają ten sam [asis,vendor_id].","You have successfully added “[_1]” to the vendor configuration list.":"Pomyślnie dodano „[_1]” do listy konfiguracji dostawców.","You have successfully disabled all of the configuration files.":"Pomyślnie wyłączono wszystkie pliki konfiguracji.","You have successfully disabled automatic updates for the vendor: [_1]":"Pomyślnie wyłączono automatyczne aktualizacje dostawcy: [_1]","You have successfully disabled some of the configuration files. The files that the system failed to disable are marked below.":"Pomyślnie wyłączono część plików konfiguracji. Pliki, których system nie mógł wyłączyć, są oznaczone poniżej.","You have successfully disabled the configuration file: [_1]":"Pomyślnie wyłączono plik konfiguracji: [_1]","You have successfully disabled the vendor: [_1]":"Pomyślnie wyłączono dostawcę: [_1]","You have successfully enabled all of the configuration files.":"Pomyślnie włączono wszystkie pliki konfiguracji.","You have successfully enabled automatic updates for the vendor: [_1]":"Pomyślnie włączono automatyczne aktualizacje dostawcy: [_1]","You have successfully enabled some of the configuration files. The files that the system failed to enable are marked below.":"Pomyślnie włączono część plików konfiguracji. Pliki, których system nie mógł włączyć, są oznaczone poniżej.","You have successfully enabled the configuration file: [_1]":"Pomyślnie włączono plik konfiguracji: [_1]","You have successfully enabled the vendor: [_1]":"Pomyślnie włączono dostawcę: [_1]","You have successfully installed the vendor: [_1]":"Pomyślnie zainstalowano dostawcę: [_1]","You have successfully removed the vendor: [_1]":"Pomyślnie usunięto dostawcę: [_1]"};

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