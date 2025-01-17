//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/share/libraries/cjt2/src/validator/email-validator.js
// Generated: /usr/local/cpanel/share/libraries/cjt2/src/validator/email-validator-pl.js
// Module:    cjt/validator/email-validator-pl
// Locale:    pl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Do not include the [asis,@] character or the domain name.":"Nie należy dodawać znaku [asis,@] ani nazwy domeny.","The email must contain a username and a domain.":"Adres e-mail musi zawierać nazwę użytkownika i domenę.","The username can only contain letters, numbers, periods, hyphens, and underscores.":"Nazwa użytkownika może się składać wyłącznie z liter, cyfr, kropek, łączników i znaków podkreślenia.","The username can only contain the following characters: [asis,a-zA-Z0-9!#$%][output,asis,amp()][output,apos][asis,*+/=?^_`{|}~-]":"Nazwa użytkownika może się składać tylko z następujących znaków: [asis,a-zA-Z0-9!#$%][output,asis,amp()][output,apos][asis,*+/=?^_`{|}~-]","The username cannot begin or end with a period.":"Nazwa użytkownika nie może zaczynać się ani kończyć kropką.","The username cannot contain two consecutive periods.":"Nazwa użytkownika nie może zawierać dwóch kropek z rzędu.","The username cannot exceed [numf,_1] characters.":"Długość nazwy użytkownika nie może przekraczać [numf,_1] znaków.","You must enter a username.":"Musisz podać nazwę użytkownika."};

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
